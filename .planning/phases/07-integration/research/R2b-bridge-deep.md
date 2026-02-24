# R2b: Observation Bridge Deep Dive

**Created:** 2026-02-22
**Scope:** Exhaustive analysis of every code path, edge case, and failure mode in the observation bridge. Covers testability, mock-bridge feasibility, diagnostics internals, and gap analysis vs existing tests.

---

## 1. Complete Bridge Source Analysis

### 1.1 Observation.swift — Full File Map (323 lines)

The entire file is wrapped in `#if SKIP_BRIDGE` (line 3 through line 323). Nothing in this file compiles on macOS.

**Imports (lines 5-14):**
- `CJNI` — C header for JNI types (always imported under SKIP_BRIDGE)
- `FoundationEssentials` or `Foundation` — for `ProcessInfo`, `TimeInterval`
- `Android` — conditional, only on Android
- `Dispatch` — for `DispatchSemaphore`, `DispatchQueue.main.async`

**Three major components:**

#### Component A: `Observation` struct (lines 16-75) — Namespace + ObservationRegistrar

```swift
public struct Observation {
    public struct ObservationRegistrar: Sendable, Equatable, Hashable { ... }
    public typealias Observable = ObservationModule.ObservableType
    public func withObservationTracking<T>(...) -> T { ... }
}
```

**`ObservationRegistrar` (lines 18-66):**
- Wraps TWO inner registrars:
  1. `registrar` = `ObservationModule.ObservationRegistrarType()` — the real Swift `ObservationRegistrar` from the Observation framework
  2. `bridgeSupport` = `BridgeObservationSupport()` — JNI bridge to Kotlin's `MutableStateBacking`
- Both are `private let`, created once per registrar instance

**`access()` method (lines 25-34) — THE critical code path:**
```swift
public func access<Subject, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) where Subject : Observable {
    if ObservationRecording.isRecording {
        ObservationRecording.recordAccess(
            replay: { [registrar] in registrar.access(subject, keyPath: keyPath) },
            trigger: { [bridgeSupport] in bridgeSupport.triggerSingleUpdate() }
        )
    }
    bridgeSupport.access(subject, keyPath: keyPath)  // ALWAYS called
    registrar.access(subject, keyPath: keyPath)       // ALWAYS called
}
```

Key observations:
- `recordAccess` is called ONLY when `isRecording` is true (during body evaluation)
- `bridgeSupport.access()` and `registrar.access()` are ALWAYS called regardless of recording state
- The replay closure captures `registrar` (the real ObservationRegistrar) to re-invoke `access()` later inside `withObservationTracking`
- The trigger closure captures `bridgeSupport` to call `triggerSingleUpdate()` which increments the Compose `MutableStateBacking` counter

**`willSet()` method (lines 36-41):**
```swift
public func willSet<Subject, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) where Subject : Observable {
    if !ObservationRecording.isEnabled {
        bridgeSupport.willSet(subject, keyPath: keyPath)
    }
    registrar.willSet(subject, keyPath: keyPath)
}
```

Key observations:
- `bridgeSupport.willSet()` is SUPPRESSED when `isEnabled` is true
- `registrar.willSet()` is ALWAYS called
- The suppression prevents double-triggering: when `isEnabled`, the `withObservationTracking` onChange handler triggers recomposition instead of direct `willSet` -> `Java_update`

**`didSet()` method (lines 43-45):**
```swift
public func didSet<Subject, Member>(_ subject: Subject, keyPath: KeyPath<Subject, Member>) where Subject : Observable {
    registrar.didSet(subject, keyPath: keyPath)
}
```

- Only delegates to the real registrar. No bridge interaction.
- `bridgeSupport` has no `didSet` equivalent — Compose doesn't need post-mutation notification.

**`withMutation()` method (lines 47-52):**
```swift
public func withMutation<Subject, Member, T>(of subject: Subject, keyPath: KeyPath<Subject, Member>, _ mutation: () throws -> T) rethrows -> T where Subject : Observable {
    if !ObservationRecording.isEnabled {
        bridgeSupport.willSet(subject, keyPath: keyPath)
    }
    return try registrar.withMutation(of: subject, keyPath: keyPath, mutation)
}
```

- Same `isEnabled` suppression as `willSet()`
- Delegates mutation to the real registrar

**Equatable/Hashable/Codable conformance (lines 54-65):**
- All registrars compare equal (`== returns true`)
- Hash contributes nothing
- Codable init/encode are no-ops
- This matches Swift's standard `ObservationRegistrar` behavior

#### Component B: `ObservationRecording` class (lines 83-186) — Record-Replay Stack

**Static properties:**

| Property | Type | Default | Thread Safety | Purpose |
|----------|------|---------|---------------|---------|
| `isEnabled` | `Bool` | `false` | NOT thread-safe (single write at startup) | One-way gate: set by `nativeEnable()` at app startup |
| `diagnosticsEnabled` | `Bool` | `false` | NOT thread-safe (test/debug use) | Enables timing/counting in `stopAndObserve()` |
| `diagnosticsHandler` | `((Int, TimeInterval) -> Void)?` | `nil` | NOT thread-safe (test/debug use) | Callback for diagnostics consumers |
| `isRecording` (computed) | `Bool` | — | Thread-safe (reads thread-local) | True when current thread has non-empty frame stack |

**Thread-local stack implementation (lines 107-131):**

```swift
private static let tlsKey: pthread_key_t = {
    var key: pthread_key_t = 0
    pthread_key_create(&key) { ptr in
        let rawPtr: UnsafeMutableRawPointer? = ptr
        guard let rawPtr else { return }
        Unmanaged<FrameStack>.fromOpaque(rawPtr).release()
    }
    return key
}()
```

- `pthread_key_t` is created ONCE (static lazy initializer)
- Destructor releases the `FrameStack` when a thread exits
- The `UnsafeMutableRawPointer?` assignment handles platform optionality differences (Darwin vs Android/Bionic)

```swift
private final class FrameStack {
    var frames: [Frame] = []
}
```

- `FrameStack` is a reference type (class) so it can be stored via `Unmanaged`
- Contains a mutable array of `Frame` values

```swift
private static var threadStack: FrameStack {
    if let ptr = pthread_getspecific(tlsKey) {
        return Unmanaged<FrameStack>.fromOpaque(ptr).takeUnretainedValue()
    }
    let stack = FrameStack()
    pthread_setspecific(tlsKey, Unmanaged.passRetained(stack).toOpaque())
    return stack
}
```

- Lazy per-thread initialization: first access creates and retains a `FrameStack`
- `takeUnretainedValue()` on subsequent accesses (ownership is held by the TLS slot)
- `passRetained()` on first creation (ownership transferred to TLS; released by destructor)

**Frame struct (lines 137-140):**
```swift
private struct Frame {
    var replayClosures: [() -> Void] = []
    var triggerClosure: (() -> Void)?
}
```

- `replayClosures`: accumulated during body evaluation, one per property access
- `triggerClosure`: set on FIRST access only (all observables share one recomposition trigger per view)

**`startRecording()` (line 142-143):**
```swift
public static func startRecording() {
    threadStack.frames.append(Frame())
}
```

- Pushes a new empty frame onto the thread-local stack
- Very cheap operation: array append + struct init

**`stopAndObserve()` (lines 146-169):**
```swift
public static func stopAndObserve() {
    guard let frame = threadStack.frames.popLast() else { return }
    guard !frame.replayClosures.isEmpty else { return }
    guard let trigger = frame.triggerClosure else {
        assertionFailure("ObservationRecording: replay closures recorded but no trigger")
        return
    }

    let closures = frame.replayClosures
    let startTime = diagnosticsEnabled ? ProcessInfo.processInfo.systemUptime : 0
    ObservationModule.withObservationTrackingFunc({
        for closure in closures {
            closure()
        }
    }, onChange: {
        DispatchQueue.main.async {
            trigger()
        }
    })
    if diagnosticsEnabled {
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        diagnosticsHandler?(closures.count, elapsed)
    }
}
```

Edge cases and failure modes:
1. **No frame on stack** (`popLast()` returns nil): Silent return. This happens if `stopAndObserve()` is called without a matching `startRecording()`. Harmless but indicates a bug.
2. **Empty replay closures**: Silent return. This means the view body accessed no `@Observable` properties. No observation subscription is set up — the view will never recompose from observation changes. This is correct for static views.
3. **Replay closures but no trigger**: `assertionFailure` in debug, silent return in release. This is a logic error — `recordAccess` always sets the trigger on first access, so this should be impossible unless `recordAccess` is called with a nil trigger.
4. **Diagnostics overhead**: Only `ProcessInfo.processInfo.systemUptime` calls when enabled. Negligible cost.

**`recordAccess()` (lines 171-185):**
```swift
static func recordAccess(
    replay: @escaping () -> Void,
    trigger: @escaping () -> Void
) {
    let stack = threadStack
    guard !stack.frames.isEmpty else { return }
    stack.frames[stack.frames.count - 1].replayClosures.append(replay)
    if stack.frames[stack.frames.count - 1].triggerClosure == nil {
        stack.frames[stack.frames.count - 1].triggerClosure = trigger
    }
}
```

Key observations:
- Empty stack guard: if somehow `recordAccess` is called outside a recording session, it's a no-op
- Replay closures accumulate (one per property access)
- Trigger closure is set ONCE (first access wins) — all subsequent accesses reuse the same trigger
- The trigger closure is `bridgeSupport.triggerSingleUpdate()` which calls `Java_update(0)` — always index 0 because a single MutableStateBacking counter increment triggers full recomposition of the enclosing scope

#### Component C: `BridgeObservationSupport` class (lines 188-280) — JNI Bridge

```swift
private final class BridgeObservationSupport: @unchecked Sendable { ... }
```

- `@unchecked Sendable` — manual thread safety via `DispatchSemaphore`
- `private` — only used within `Observation.ObservationRegistrar`

**Thread safety mechanism:**
```swift
private let lock = DispatchSemaphore(value: 1)
```

- Binary semaphore used as a mutex
- Guards: `Java_init(forKeyPath:)`, `triggerSingleUpdate()`
- Does NOT guard `Java_access()` or `Java_update()` — these read `Java_peer` without locking

**POTENTIAL RACE CONDITION:** `Java_access()` (line 245) and `Java_update()` (line 257) check `isJNIInitialized` and read `Java_peer` WITHOUT acquiring the lock. If `Java_init(forKeyPath:)` is being called concurrently on another thread (first-time initialization), there's a window where `Java_hasInitialized` is true but `Java_peer` is being written. However, in practice this is safe because:
1. `Java_hasInitialized` is set BEFORE `Java_peer` assignment in `Java_init`... wait, no — line 222-224:
```swift
if !Java_hasInitialized {
    Java_hasInitialized = true
    Java_peer = Java_initPeer()
}
```
`Java_hasInitialized` is set to `true` BEFORE `Java_peer` is assigned. So another thread could see `Java_hasInitialized == true` but `Java_peer == nil`. However, `Java_access` and `Java_update` check `let peer = Java_peer` with a nil guard, so they'd just return early. The lock in `Java_init` prevents concurrent initialization.

**Actually, the real protection is different:** `Java_access` and `Java_update` don't check `Java_hasInitialized` — they check `isJNIInitialized` (the global JNI singleton) AND `Java_peer`. Since `Java_peer` starts nil and is only set inside the locked `Java_init`, the nil guard in `Java_access`/`Java_update` is sufficient for safety (they'd just no-op until initialization completes).

**KeyPath indexing (lines 270-279):**
```swift
private var indexes: [AnyKeyPath: Int] = [:]

private func index(forKeyPath keyPath: AnyKeyPath) -> Int {
    if let index = indexes[keyPath] {
        return index
    }
    let nextIndex = indexes.count
    indexes[keyPath] = nextIndex
    return nextIndex
}
```

- Maps Swift KeyPaths to integer indices for Java's `MutableStateBacking.access(Int)` / `update(Int)`
- Index 0 is reserved for `triggerSingleUpdate()` (which passes 0 directly)
- Regular property indices start at 0 for the first keypath, incrementing from there
- **OVERLAP:** `triggerSingleUpdate()` calls `Java_update(0)` and the first keypath also gets index 0. This means index 0 is overloaded: it serves both as the "generic trigger" and as a specific property index. This is fine because `MutableStateBacking.update(index)` just increments a Compose state counter — any index triggers recomposition.

**THREAD SAFETY OF `indexes`:** The `indexes` dictionary is mutated in `index(forKeyPath:)` which is called from `Java_init(forKeyPath:)` which holds the lock. But `index(forKeyPath:)` itself is called only from within the locked section. So this is safe.

Wait — re-reading: `Java_init(forKeyPath:)` acquires the lock, then calls `index(forKeyPath:)` at line 229. The `indexes` dictionary is only mutated inside the locked path. Safe.

**`Java_initPeer()` (lines 232-243):**
```swift
private func Java_initPeer() -> JObject? {
    guard isJNIInitialized else {
        return nil
    }
    return jniContext {
        guard let cls = Self.Java_stateClass, let initMethod = Self.Java_state_init_methodID else {
            return nil
        }
        let ptr: JavaObjectPointer = try! cls.create(ctor: initMethod, options: [], args: [])
        return JObject(ptr)
    }
}
```

Returns nil when:
1. `isJNIInitialized` is false — JNI singleton (`JNI.jni`) not yet set. This happens on macOS or if the JVM hasn't loaded yet.
2. `Java_stateClass` is nil — `JClass(name: "skip/model/MutableStateBacking")` failed. The class doesn't exist in the classpath.
3. `Java_state_init_methodID` is nil — The `<init>` method wasn't found on the class.

The `try!` force-unwrap on `cls.create()` means a Java exception during `MutableStateBacking()` construction will crash the app. This is P2-7 in the reconciled research.

**Static JNI lookups (lines 211-214):**
```swift
private static let Java_stateClass = try? JClass(name: "skip/model/MutableStateBacking")
private static let Java_state_init_methodID = Java_stateClass?.getMethodID(name: "<init>", sig: "()V")
private static let Java_state_access_methodID = Java_stateClass?.getMethodID(name: "access", sig: "(I)V")
private static let Java_state_update_methodID = Java_stateClass?.getMethodID(name: "update", sig: "(I)V")
```

- `try?` on class lookup — swallows errors, returns nil
- Method IDs are cached statically — looked up once per process
- `(I)V` signature = takes one `int`, returns `void`
- These static lets are lazy (Swift static let initialization is thread-safe and lazy)

#### Component D: JNI Exports (lines 288-308)

Three exported functions, all gated with `#if os(Android)`:

| JNI Name | Swift Function | Action |
|----------|---------------|--------|
| `Java_skip_ui_ViewObservation_nativeEnable` | `_jni_nativeEnable` | Sets `ObservationRecording.isEnabled = true` |
| `Java_skip_ui_ViewObservation_nativeStartRecording` | `_jni_nativeStartRecording` | Calls `ObservationRecording.startRecording()` |
| `Java_skip_ui_ViewObservation_nativeStopAndObserve` | `_jni_nativeStopAndObserve` | Calls `ObservationRecording.stopAndObserve()` |

Each takes `(OpaquePointer?, OpaquePointer?)` — the JNI env and `this` pointer, both unused.

#### Component E: `swiftThreadingFatal` stub (lines 310-321)

```swift
#if os(Android) && !swift(>=6.3)
@_cdecl("_ZN5swift9threading5fatalEPKcz")
public func swiftThreadingFatal() {
    print("swiftThreadingFatal")
}
#endif
```

- Mangled C++ symbol for `swift::threading::fatal(const char*, ...)`
- Required because `libswiftObservation.so` references this symbol which is missing from the Android SDK's Swift runtime
- Version-gated: will auto-remove when Swift 6.3 ships the upstream fix
- The `print()` prevents the function from being stripped in release builds

### 1.2 ObservationModule.swift — Full File Map (23 lines)

Entire file gated `#if SKIP_BRIDGE`.

```swift
import Observation
import func Observation.withObservationTracking

public struct ObservationModule {
    public typealias ObservableType = Observable
    public typealias ObservationRegistrarType = ObservationRegistrar
    public static func withObservationTrackingFunc<T>(_ apply: () -> T, onChange: @autoclosure () -> @Sendable () -> Void) -> T {
        return withObservationTracking(apply, onChange: onChange())
    }
}
```

Purpose: Indirection layer that forwards to the real Swift Observation framework types. This exists because Skip's transpiler needs concrete function references rather than protocol-based dispatch. The `withObservationTrackingFunc` static method wraps the stdlib's free function `withObservationTracking`.

### 1.3 View.swift — ViewObservation + Evaluate() (skip-ui)

**File gate:** `#if !SKIP_BRIDGE` (line 3) — this is the INVERSE gate. The entire View.swift compiles when SKIP_BRIDGE is NOT defined. On Android with SKIP_BRIDGE, a different version of View is used (the bridged version from skip-android-bridge).

Wait — this needs clarification. The file starts with `#if !SKIP_BRIDGE`, meaning on macOS (no SKIP_BRIDGE), this file compiles. On Android with SKIP_BRIDGE, this file does NOT compile. But `ViewObservation` is defined INSIDE this `#if !SKIP_BRIDGE` block...

This means `ViewObservation` compiles on BOTH macOS AND Android-without-bridge (Lite mode). On bridge-mode Android, ViewObservation comes from the transpiled Kotlin, not from this Swift source. The `// SKIP DECLARE: object ViewObservation` and `// SKIP INSERT:` comments are Skip transpiler directives that generate the Kotlin equivalent.

**ViewObservation (lines 27-39):**

Swift side (macOS):
```swift
struct ViewObservation {
    static var startRecording: (() -> Void)? = nil
    static var stopAndObserve: (() -> Void)? = nil
}
```

On macOS, both closures are nil. They're never set. The Evaluate() method calls `ViewObservation.startRecording?()` which is a no-op (nil optional call).

Kotlin side (Android, from SKIP INSERT directives):
```kotlin
object ViewObservation {
    var startRecording: (() -> Unit)? = null
    var stopAndObserve: (() -> Unit)? = null

    init {
        try {
            nativeEnable()
            startRecording = { try { nativeStartRecording() } catch (e: Throwable) { error("...") } }
            stopAndObserve = { try { nativeStopAndObserve() } catch (e: Throwable) { error("...") } }
        } catch (e: Throwable) {
            error("ViewObservation: nativeEnable() failed. Observation bridge is NOT active. This is fatal in Fuse mode...")
        }
    }

    private external fun nativeEnable()
    private external fun nativeStartRecording()
    private external fun nativeStopAndObserve()
}
```

The `init` block (Kotlin's static initializer for `object`):
1. Calls `nativeEnable()` — sets `ObservationRecording.isEnabled = true` via JNI
2. If successful, wires `startRecording` and `stopAndObserve` closures to their JNI counterparts
3. If `nativeEnable()` throws, calls `error()` (Kotlin's equivalent of `fatalError`)
4. If subsequent JNI calls fail mid-session, also calls `error()`

**This is the "one-way gate" for isEnabled:** The Kotlin `ViewObservation` object is initialized lazily on first access. Once `nativeEnable()` succeeds, `isEnabled` is permanently true.

**Evaluate() method (lines 86-99):**
```swift
@Composable public func Evaluate(context: ComposeContext, options: Int) -> kotlin.collections.List<Renderable> {
    if let renderable = self as? Renderable {
        return listOf(self)
    } else {
        ViewObservation.startRecording?()
        StateTracking.pushBody()
        let renderables = body.Evaluate(context: context, options: options)
        StateTracking.popBody()
        ViewObservation.stopAndObserve?()
        return renderables
    }
}
```

The recording brackets `body.Evaluate()`:
1. `startRecording()` — push new frame
2. `body` evaluation — property accesses are recorded
3. `stopAndObserve()` — pop frame, replay inside `withObservationTracking`

**Nested views:** When `body.Evaluate()` recursively evaluates child views, each child's `Evaluate()` pushes its own frame. The stack handles this correctly — each frame is independent.

### 1.4 ViewModifier.swift — Evaluate() hooks

```swift
@Composable public func Evaluate(content: Content, context: ComposeContext, options: Int) -> kotlin.collections.List<Renderable> {
    ViewObservation.startRecording?()
    StateTracking.pushBody()
    let renderables = body(content: content).Evaluate(context: context, options: options)
    StateTracking.popBody()
    ViewObservation.stopAndObserve?()
    return renderables
}
```

Identical pattern to View.Evaluate() — ViewModifiers also get their own observation scope. This means a `ViewModifier` with `@Observable` state gets independent recomposition tracking.

### 1.5 ObservationStateRegistrar.swift (TCA)

```swift
#if !os(visionOS) && !os(Android)
    let registrar = PerceptionRegistrar()
#elseif os(Android)
    let registrar = SkipAndroidBridge.Observation.ObservationRegistrar()
#else
    let registrar = Observation.ObservationRegistrar()
#endif
```

Three paths:
1. **macOS/iOS (not visionOS)**: Uses `PerceptionRegistrar` from swift-perception (backport for pre-iOS 17)
2. **Android**: Uses the bridge's `Observation.ObservationRegistrar` which wraps real `ObservationRegistrar` + `BridgeObservationSupport`
3. **visionOS**: Uses the system `Observation.ObservationRegistrar` directly

The `access()`, `mutate()`, `willModify()`, `didModify()` methods all delegate to `self.registrar`. On Android, this means every TCA state access flows through the bridge's recording mechanism.

---

## 2. SKIP_BRIDGE Flag Mapping

### 2.1 Where it's defined

`SKIP_BRIDGE` is **NOT** defined in any Package.swift `swiftSettings`. It is injected by Skip's `skipstone` Swift Package Manager plugin at build time. Evidence:

1. `forks/skip-android-bridge/Package.swift` has NO `swiftSettings` at all — no `.define("SKIP_BRIDGE")` anywhere
2. `forks/skip-ui/Package.swift` line 20: `if Context.environment["SKIP_BRIDGE"] ?? "0" != "0"` — reads it from the build ENVIRONMENT, not from Swift compiler flags
3. No `.gradle` files define it (searched, no matches)
4. The skipstone plugin sets this flag when building for Android/Fuse mode

The skipstone plugin (`skip` package) runs as an SPM build tool plugin. When the target is an Android Fuse build, it:
1. Sets the `SKIP_BRIDGE` environment variable
2. Adds `-DSKIP_BRIDGE` to Swift compiler flags for the target
3. Configures dynamic library linking for bridge support

### 2.2 Can it be enabled on macOS for testing?

**Technically possible but practically infeasible.** You would need to:

1. Add `.define("SKIP_BRIDGE")` to the target's `swiftSettings` in Package.swift
2. Satisfy all import dependencies:
   - `CJNI` — the C JNI headers. These exist on macOS via the JDK but the `swift-jni` package conditionally imports them
   - `Android` — `#if canImport(Android)` guards this, so it's skipped on macOS
   - `Dispatch` — available on macOS
3. Handle `isJNIInitialized` — would always return false on macOS (no JVM loaded into the process)

**What would break:**
- `BridgeObservationSupport` would compile but `Java_initPeer()` would always return nil (no JNI)
- All `Java_access()` / `Java_update()` calls would be no-ops
- `ObservationRecording` itself would work perfectly — it has no JNI dependency
- JNI exports (`@_cdecl`) would compile on macOS but never be called
- The `Observation.ObservationRegistrar.access()` would record and replay correctly, but `bridgeSupport.access()` would be a no-op

**Verdict:** Enabling SKIP_BRIDGE on macOS would let `ObservationRecording` compile and be testable. The JNI parts would gracefully degrade to no-ops. This is a viable path for mock-bridge testing.

### 2.3 Minimum extractable set for macOS compilation

The following code from Observation.swift could compile on macOS with ZERO changes:

- `ObservationRecording` class (lines 83-186) — uses only `pthread_key_t`, `withObservationTracking`, `ProcessInfo`, `DispatchQueue`
- `ObservationModule` struct (entire file) — just type aliases and forwarding

Would need JNI stubs or removal:
- `BridgeObservationSupport` — all JNI calls would need to be stubbed
- `Observation.ObservationRegistrar` — depends on `BridgeObservationSupport`
- JNI exports — could be `#if os(Android)` gated (already are)
- `swiftThreadingFatal` — already `#if os(Android)` gated

---

## 3. Diagnostics API Deep Dive

### 3.1 Implementation

**`diagnosticsEnabled` (line 95):**
```swift
public static var diagnosticsEnabled = false
```
- Simple boolean flag
- Checked only in `stopAndObserve()` at line 155
- No synchronization — intended for test/debug use where a single thread sets it before tests run

**`diagnosticsHandler` (line 99):**
```swift
public static var diagnosticsHandler: ((Int, TimeInterval) -> Void)?
```
- Optional closure, called at the end of `stopAndObserve()` (line 167)
- Receives `(closureCount: Int, elapsed: TimeInterval)`

### 3.2 What `closureCount` means

`closureCount` = `frame.replayClosures.count` = the number of `recordAccess()` calls during the view's body evaluation.

Each `recordAccess()` call corresponds to one `ObservationRegistrar.access()` call when `isRecording` is true. This happens once per `@Observable` property access in the view body.

**Concrete example:**
```swift
var body: some View {
    Text("\(model.name)")          // 1 access: model.name
    Text("\(model.count)")         // 1 access: model.count
    Text("\(model.details.info)")  // 2 accesses: model.details + details.info
}
```
`closureCount` would be 4.

**Computed properties:** Accessing `model.doubleCount` (which reads `model.count` internally) registers as 1 access to `doubleCount` from the view body's perspective, BUT the computed property's getter triggers `access()` on `count`. So the closure count includes both the computed property access AND its underlying stored property access. This depends on how the `@Observable` macro expands the computed property.

Actually, re-reading the `@Observable` macro behavior: computed properties are NOT tracked by `@Observable` — only stored properties are. `doubleCount` is a computed property that reads `count`. When the view accesses `model.doubleCount`, the getter runs, which accesses `model.count`, which triggers `registrar.access(model, keyPath: \.count)`. So `closureCount` would be 1 (for `\.count`), not 2.

### 3.3 What `elapsed` measures

```swift
let startTime = diagnosticsEnabled ? ProcessInfo.processInfo.systemUptime : 0
ObservationModule.withObservationTrackingFunc({
    for closure in closures {
        closure()
    }
}, onChange: { ... })
if diagnosticsEnabled {
    let elapsed = ProcessInfo.processInfo.systemUptime - startTime
    diagnosticsHandler?(closures.count, elapsed)
}
```

`elapsed` measures the wall-clock time of the `withObservationTrackingFunc` call, which includes:
1. Setting up the observation tracking scope
2. Executing ALL replay closures (each calls `registrar.access()`)
3. Registering the onChange handler
4. Returning

It does NOT include the onChange handler execution (that runs later, asynchronously via `DispatchQueue.main.async`).

For a typical view with 5 property accesses, `elapsed` would be microseconds (sub-millisecond). High values would indicate:
- Excessive property accesses (thousands of closures)
- Slow `registrar.access()` (unlikely unless the registrar has complex internals)
- Thread contention on the registrar's internal lock

### 3.4 Can diagnostics detect infinite recomposition? (TEST-10)

**Yes, with caveats.**

Infinite recomposition would manifest as an unbounded number of `stopAndObserve()` calls. Each recomposition triggers `Evaluate()` -> `startRecording()` -> body eval -> `stopAndObserve()`. If a view's body evaluation causes a mutation (e.g., via a side effect in a computed property), that mutation triggers `onChange`, which triggers recomposition, which calls `Evaluate()` again, creating an infinite loop.

Detection approach:
```swift
var recomposeCount = 0
ObservationRecording.diagnosticsHandler = { _, _ in
    recomposeCount += 1
    if recomposeCount > 100 {
        // Infinite recomposition detected
    }
}
```

**Caveat 1:** The diagnostics handler fires during `stopAndObserve()`, which is synchronous within `Evaluate()`. If recomposition is truly infinite, it would be an infinite loop on the same thread — the handler would fire but the count check would only execute between loop iterations.

**Caveat 2:** Compose has its own recomposition loop detection. The Compose runtime limits recomposition passes. So in practice, infinite recomposition would hit Compose's limit before exhausting the diagnostics handler.

**Caveat 3:** The `onChange` handler dispatches to `DispatchQueue.main.async`, which means recomposition is deferred. So the loop is: `Evaluate()` -> `stopAndObserve()` -> (later) `onChange` fires -> `DispatchQueue.main.async { trigger() }` -> Compose schedules recomposition -> `Evaluate()`. This async gap means the loop isn't truly synchronous — it's bounded by the main queue's processing rate.

### 3.5 Thread safety of the diagnostics handler

**Not thread-safe.** Both `diagnosticsEnabled` and `diagnosticsHandler` are plain static properties with no synchronization. If multiple threads call `stopAndObserve()` concurrently (possible with concurrent Compose recomposition), they could read `diagnosticsHandler` while another thread is setting it.

In practice, this is acceptable because:
1. `diagnosticsEnabled` and `diagnosticsHandler` are set ONCE during test setup, before any concurrent activity
2. Reading a `Bool` or `Optional` closure pointer is atomic on arm64/x86_64 in practice (though not guaranteed by Swift)
3. The handler closure itself should be thread-safe if it uses proper synchronization

For testing, the pattern would be:
```swift
// Set up BEFORE any observation activity
ObservationRecording.diagnosticsEnabled = true
let counter = AtomicInt(0) // need thread-safe counter
ObservationRecording.diagnosticsHandler = { _, _ in counter.increment() }
// ... run tests ...
// Tear down AFTER all observation activity
ObservationRecording.diagnosticsEnabled = false
ObservationRecording.diagnosticsHandler = nil
```

---

## 4. ObservationRecording Internals

### 4.1 Thread-local stack lifecycle

```
Thread A:                          Thread B:
─────────────                      ─────────────
threadStack (lazy init)            threadStack (lazy init)
  -> pthread_getspecific = nil       -> pthread_getspecific = nil
  -> create FrameStack A             -> create FrameStack B
  -> pthread_setspecific(A)           -> pthread_setspecific(B)
  -> return A                         -> return B

startRecording()                   startRecording()
  -> A.frames.append(Frame())       -> B.frames.append(Frame())
  isRecording = true                 isRecording = true

... body eval ...                  ... body eval ...
  recordAccess(...)                  recordAccess(...)
  -> A.frames.last.append(...)       -> B.frames.last.append(...)

stopAndObserve()                   stopAndObserve()
  -> A.frames.popLast()              -> B.frames.popLast()
  -> replay in wOT                   -> replay in wOT
  isRecording = false                isRecording = false

Thread A exits:                    Thread B exits:
  -> pthread destructor               -> pthread destructor
  -> Unmanaged<FrameStack>.release()   -> Unmanaged<FrameStack>.release()
  -> FrameStack A deallocated          -> FrameStack B deallocated
```

Each thread has a completely independent recording stack. No cross-thread interference.

### 4.2 Nested views (recording within recording)

```
View.Evaluate() — outer view
  startRecording()         // Stack: [Frame_outer]
  body eval:
    Text(model.name)       // recordAccess -> Frame_outer.replay += [closure_name]
    ChildView.Evaluate()   // inner view
      startRecording()     // Stack: [Frame_outer, Frame_child]
      body eval:
        Text(child.value)  // recordAccess -> Frame_child.replay += [closure_value]
      stopAndObserve()     // Pop Frame_child, replay child closures in wOT
                           // Stack: [Frame_outer]
    Text(model.count)      // recordAccess -> Frame_outer.replay += [closure_count]
  stopAndObserve()         // Pop Frame_outer, replay outer closures in wOT
                           // Stack: []
```

Key observations:
- Each view gets its own independent observation subscription
- Child view's `stopAndObserve()` completes BEFORE parent's `stopAndObserve()`
- Child's `withObservationTracking` onChange only covers child's accessed properties
- Parent's `withObservationTracking` onChange only covers parent's accessed properties (NOT child's)
- This is correct: changing `child.value` only recomposes the child, not the parent

### 4.3 startRecording without stopAndObserve (leak scenario)

If `startRecording()` is called but `stopAndObserve()` is never called:

1. **Frame accumulation**: The frame stays on the stack. Future `startRecording()` calls push more frames on top.
2. **isRecording stays true**: Any `access()` calls continue recording into the orphaned frame's successors.
3. **Memory impact**: Each frame holds an array of closures, each capturing `registrar` and `subject` references. These won't be released until the thread exits (pthread destructor releases the entire FrameStack).
4. **No crash**: Silent behavior. The recording just accumulates without being observed.
5. **Subsequent stopAndObserve**: Would pop the MOST RECENT frame (LIFO), not the orphaned one. So a later stop would process the wrong frame.

**Risk assessment:** Low in production (Evaluate() always brackets start/stop), but relevant for testing — if a test calls `startRecording()` and fails before `stopAndObserve()`, the thread-local stack would have a stale frame. This is cleaned up when the thread exits or when the next `stopAndObserve()` pops it.

### 4.4 Memory profile of accumulated replay closures

Each replay closure captures:
```swift
replay: { [registrar] in registrar.access(subject, keyPath: keyPath) }
```

Captured values:
- `registrar`: `ObservationRegistrar` instance (lightweight — wraps two registrars)
- `subject`: The `@Observable` object (strong reference)
- `keyPath`: `KeyPath<Subject, Member>` (lightweight value type)

Per closure: ~48-64 bytes (closure context allocation on heap) + strong ref to subject.

For a typical view with 5-10 property accesses: ~500 bytes per frame. Negligible.

**Concern for stress testing:** If a view accesses thousands of properties (unusual but possible with ForEach over large arrays), the closure array grows linearly. At 10,000 accesses: ~640KB per frame. Still manageable.

The closures are released when `stopAndObserve()` processes the frame (the `frame` local goes out of scope, releasing the array). So memory is bounded by the maximum frame depth (stack size) times the max closures per frame.

---

## 5. BridgeObservationSupport Deep Dive

### 5.1 Java_initPeer() — What it does and when it returns nil

```swift
private func Java_initPeer() -> JObject? {
    guard isJNIInitialized else {
        return nil  // Case 1: no JVM
    }
    return jniContext {
        guard let cls = Self.Java_stateClass, let initMethod = Self.Java_state_init_methodID else {
            return nil  // Case 2: class/method not found
        }
        let ptr: JavaObjectPointer = try! cls.create(ctor: initMethod, options: [], args: [])
        return JObject(ptr)  // Case 3: success
    }
}
```

**Case 1: `isJNIInitialized` is false**
- `JNI.jni` singleton is nil
- Happens on macOS (no JVM) or before JNI_OnLoad runs on Android
- Returns nil — all subsequent `Java_access`/`Java_update` calls are no-ops

**Case 2: Class/method lookup failed**
- `JClass(name: "skip/model/MutableStateBacking")` returned nil (class not in classpath)
- OR `getMethodID(name: "<init>", sig: "()V")` returned nil (no matching constructor)
- Returns nil — same no-op behavior

**Case 3: Success**
- Creates a new `MutableStateBacking` Java object
- Returns a `JObject` wrapper holding a JNI global reference
- This object is stored as `Java_peer` for the lifetime of the `BridgeObservationSupport` instance

**`jniContext` behavior:** From SwiftJNI source (lines 67-97):
- If current thread is attached to JVM (`JNI_OK`): runs block directly
- If detached (`JNI_EDETACHED`): attaches, runs block, detaches
- Sets thread class loader for reflection-based class loading
- Crashes (`fatalError`) on unsupported JNI version or unexpected status

### 5.2 The isEnabled one-way gate

**How it's set:**
1. Kotlin `ViewObservation` object is first accessed (static init)
2. `init` block calls `nativeEnable()` (JNI)
3. `nativeEnable()` calls `ObservationRecording.isEnabled = true`
4. If `nativeEnable()` throws, Kotlin `error()` terminates the app

**What triggers it:**
The first call to `ViewObservation.startRecording` or `ViewObservation.stopAndObserve` triggers Kotlin's lazy object initialization. In practice, this happens on the first `View.Evaluate()` call.

**Why one-way:**
The bridge is either present or not. Once the native library loads and `nativeEnable()` succeeds, there's no reason to disable it. The comment in source (lines 88-91) explicitly states this.

**Behavioral impact:**
| `isEnabled` | `access()` behavior | `willSet()` behavior |
|-------------|--------------------|--------------------|
| `false` | `bridgeSupport.access()` + `registrar.access()` (no recording) | `bridgeSupport.willSet()` + `registrar.willSet()` |
| `true` | Recording if `isRecording` + `bridgeSupport.access()` + `registrar.access()` | `registrar.willSet()` ONLY (bridgeSupport suppressed) |

When `isEnabled = false`:
- `bridgeSupport.willSet()` triggers `Java_update()` directly on mutation
- This is the "original behavior" — direct Compose state update per property change
- No record-replay; recomposition is triggered per-willSet

When `isEnabled = true`:
- `bridgeSupport.willSet()` is suppressed in `willSet()` and `withMutation()`
- Instead, the record-replay path handles recomposition
- `withObservationTracking` onChange -> `DispatchQueue.main.async` -> `triggerSingleUpdate()` -> `Java_update(0)`
- This batches observation: one recomposition per onChange, not per property mutation

### 5.3 willSet() path — direct dispatch vs withObservationTracking

**When `isEnabled = false` (no bridge hooks / Lite mode):**
```
Property mutation
  -> registrar.willSet()      // registers with Swift Observation
  -> bridgeSupport.willSet()  // Java_update(index) -> MutableStateBacking.update(index)
                              // Direct Compose recomposition per mutation
```

**When `isEnabled = true` (bridge active / Fuse mode):**
```
Property mutation
  -> registrar.willSet()      // registers with Swift Observation
  -> (bridgeSupport.willSet suppressed)

  // Later, from withObservationTracking's onChange:
  -> DispatchQueue.main.async { bridgeSupport.triggerSingleUpdate() }
  -> Java_update(0)           // Single recomposition trigger

  // Compose recomposition:
  -> Evaluate() -> startRecording -> body eval -> stopAndObserve
  -> New withObservationTracking subscription set up
```

The key difference: `isEnabled = false` triggers recomposition per property mutation (potentially many updates), while `isEnabled = true` batches through withObservationTracking's coalescing (one onChange per tracking scope).

### 5.4 JNI function naming convention — Complete map

| Swift `@_cdecl` name | Java class | Java method | Signature |
|----------------------|-----------|-------------|-----------|
| `Java_skip_ui_ViewObservation_nativeEnable` | `skip.ui.ViewObservation` | `nativeEnable` | `()V` |
| `Java_skip_ui_ViewObservation_nativeStartRecording` | `skip.ui.ViewObservation` | `nativeStartRecording` | `()V` |
| `Java_skip_ui_ViewObservation_nativeStopAndObserve` | `skip.ui.ViewObservation` | `nativeStopAndObserve` | `()V` |

JNI naming convention: `Java_<package>_<class>_<method>` where package dots become underscores.
- Package: `skip.ui` -> `skip_ui`
- Class: `ViewObservation`
- Combined: `Java_skip_ui_ViewObservation_<method>`

Java-side method signatures (from Kotlin `external fun` declarations):
```kotlin
private external fun nativeEnable()           // -> ()V
private external fun nativeStartRecording()   // -> ()V
private external fun nativeStopAndObserve()   // -> ()V
```

All three take no arguments (beyond the implicit JNI env and this pointers) and return void.

**BridgeObservationSupport Java calls (outbound, Swift -> Java):**

| Swift method | Java class | Java method | JNI signature |
|-------------|-----------|-------------|---------------|
| `Java_access(_ index:)` | `skip.model.MutableStateBacking` | `access` | `(I)V` |
| `Java_update(_ index:)` | `skip.model.MutableStateBacking` | `update` | `(I)V` |
| `Java_initPeer()` | `skip.model.MutableStateBacking` | `<init>` | `()V` |

---

## 6. Mock-Bridge Feasibility Analysis

### 6.1 Could we create a macOS-compatible mock of ObservationRecording?

**Yes.** `ObservationRecording` has ZERO JNI dependencies. Every line of code uses standard Swift/POSIX APIs:

| API Used | macOS Available | Notes |
|----------|----------------|-------|
| `pthread_key_t`, `pthread_key_create`, `pthread_getspecific`, `pthread_setspecific` | YES | POSIX threads, fully available |
| `Unmanaged<T>` | YES | Swift standard library |
| `ObservationModule.withObservationTrackingFunc` | YES (via real Observation framework) | Just forwards to `withObservationTracking` |
| `ProcessInfo.processInfo.systemUptime` | YES | Foundation |
| `DispatchQueue.main.async` | YES | Dispatch framework |

### 6.2 Mock implementation approaches

**Approach A: Copy-paste extraction (simplest)**

Copy `ObservationRecording` from Observation.swift into a test helper file, removing the `#if SKIP_BRIDGE` gate. Replace `ObservationModule.withObservationTrackingFunc` with direct `withObservationTracking` call.

Effort: ~30 minutes. Downside: code duplication; must be kept in sync with the real class.

**Approach B: Conditional compilation flag (cleanest)**

Add a test-only flag to the skip-android-bridge Package.swift:
```swift
.target(name: "SkipAndroidBridge",
    swiftSettings: [
        .define("OBSERVATION_RECORDING_TESTABLE", .when(configuration: .debug))
    ])
```

Then restructure Observation.swift:
```swift
#if SKIP_BRIDGE || OBSERVATION_RECORDING_TESTABLE
// ObservationRecording class
#endif

#if SKIP_BRIDGE
// BridgeObservationSupport, ObservationRegistrar, JNI exports
#endif
```

Effort: ~1 hour (fork change). Benefit: tests run against the REAL code, not a copy.

**Approach C: Protocol extraction (most flexible)**

Define a protocol for the recording interface:
```swift
protocol ObservationRecordingProtocol {
    static func startRecording()
    static func stopAndObserve()
    static var isRecording: Bool { get }
    static func recordAccess(replay: @escaping () -> Void, trigger: @escaping () -> Void)
    static var diagnosticsEnabled: Bool { get set }
    static var diagnosticsHandler: ((Int, TimeInterval) -> Void)? { get set }
}
```

Create a `MockObservationRecording` conforming to this protocol for macOS tests, and have the real `ObservationRecording` conform on Android.

Effort: ~2 hours. Downside: protocol adds indirection; doesn't test the real thread-local implementation.

### 6.3 What the mock interface should cover

Minimum viable mock for testing the record-replay contract:

```swift
final class MockObservationRecording {
    // Thread-local stack (same as real implementation)
    // startRecording() — push frame
    // stopAndObserve() — pop frame, replay in withObservationTracking
    // recordAccess(replay:trigger:) — append to current frame
    // isRecording — check stack non-empty
    // diagnosticsEnabled / diagnosticsHandler — same API
}
```

The mock does NOT need:
- `isEnabled` flag (that's for suppressing `bridgeSupport.willSet()`)
- Any JNI interaction
- `BridgeObservationSupport` equivalent (the trigger closure can be a test-observable callback)

### 6.4 Is it worth the effort vs emulator testing?

**Yes, it's worth it for these reasons:**

1. **Speed**: macOS tests run in <1s. Android emulator tests take 30-60s per run (boot + deploy + execute).
2. **CI reliability**: Emulator tests are flaky (timeout, boot failure). macOS tests are deterministic.
3. **Coverage depth**: The mock can test edge cases (nested recording, empty frames, thread isolation) that are hard to trigger through the Compose UI on Android.
4. **Development velocity**: Engineers can iterate on bridge logic changes with `swift test` before deploying to emulator.

The emulator tests remain essential for validating JNI integration, Compose recomposition behavior, and end-to-end correctness. The mock-bridge tests complement them by covering the pure-Swift logic layer.

---

## 7. Existing Observation Tests — Gap Analysis

### 7.1 ObservationVerifier (12 methods)

| Method | What It Tests | Bridge Coverage |
|--------|--------------|-----------------|
| `verifyBasicTracking` | `withObservationTracking` fires onChange on mutation | Tests native observation contract, NOT bridge recording |
| `verifyMultiplePropertyTracking` | Multiple property access, one onChange | Same |
| `verifyIgnoredProperty` | `@ObservationIgnored` suppresses onChange | Same |
| `verifyComputedPropertyTracking` | Computed property dependency tracking | Same |
| `verifyMultipleObservables` | Independent observable instances | Same |
| `verifyNestedTracking` | Nested observable access | Same |
| `verifySequentialTracking` | Sequential re-subscription | Same |
| `verifyBulkMutationCoalescing` | Bulk mutations, single onChange | Same |
| `verifyObservationIgnoredNoTracking` | Ignored prop suppresses all tracking | Same |
| `verifyNestedObservationCycles` | Nested withObservationTracking scopes | Same |
| `verifySequentialObservationCyclesResubscribe` | Re-subscribe after onChange | Same |
| `verifyMultiPropertySingleOnChange` | Multi-property single onChange | Same |

### 7.2 ObservationTests (19 test methods)

- 7 property CRUD tests (transpiled Kotlin on Android — test model serialization/access)
- 12 verifier delegation tests (call ObservationVerifier methods above)

### 7.3 ObservationTrackingTests (7 methods, macOS-only)

- Subset of ObservationVerifier tests (basic, multi, ignored, computed, multi-observable, nested, sequential)
- **Redundant** with the verifier tests in ObservationTests (P1-5 in reconciled research)

### 7.4 Gap analysis: What's tested vs what the bridge does

| Bridge Functionality | Tested? | Gap |
|---------------------|---------|-----|
| `withObservationTracking` contract (onChange fires correctly) | YES (ObservationVerifier) | None |
| Property CRUD via `@Observable` | YES (ObservationTests) | None |
| `ObservationRecording.startRecording()` / `stopAndObserve()` lifecycle | **NO** | Not testable on macOS without mock |
| Record-replay: property access during recording creates replay closures | **NO** | Core bridge logic untested |
| Record-replay: replay closures fire inside `withObservationTracking` | **NO** | Core bridge logic untested |
| Nested recording frames (parent/child views) | **NO** | Critical for view hierarchy correctness |
| Empty frame handling (static view with no @Observable accesses) | **NO** | Edge case |
| Thread-local isolation (concurrent recording on different threads) | **NO** | Critical for Compose concurrency |
| Single trigger per frame (first access sets trigger, subsequent reuse) | **NO** | Bridge optimization untested |
| Diagnostics API (closureCount, elapsed) | **NO** | Instrumentation untested |
| `isEnabled` suppression of `bridgeSupport.willSet()` | **NO** | Mode switching untested |
| `BridgeObservationSupport.triggerSingleUpdate()` | **NO** | JNI trigger untested (Android only) |
| `BridgeObservationSupport.Java_initPeer()` nil handling | **NO** | Graceful degradation untested |
| KeyPath-to-index mapping | **NO** | Index assignment untested |
| JNI exports (`nativeEnable`, `nativeStartRecording`, `nativeStopAndObserve`) | **NO** | JNI entry points untested |
| `swiftThreadingFatal` stub presence | **NO** | Runtime linkage untested |
| `ViewObservation` Kotlin init block | **NO** | Kotlin-side init untested |
| `Evaluate()` bracketing (start/stop around body) | **NO** | Integration point untested |
| `ObservationStateRegistrar` Android path | **NO** | TCA registrar routing untested |

### 7.5 Summary of the testing gap

The existing tests validate that `withObservationTracking` works correctly as a Swift stdlib primitive. They do NOT test:

1. **The record-replay mechanism** — the core innovation of the bridge
2. **Thread-local recording stack** — the concurrency safety mechanism
3. **JNI integration** — Swift <-> Kotlin bridge calls
4. **Compose recomposition triggering** — the end goal of the bridge
5. **Diagnostics API** — the instrumentation layer
6. **Mode switching** — `isEnabled` flag behavior
7. **Error handling** — what happens when JNI fails, frames are orphaned, etc.

The gap between "ObservationVerifier validates tracking" and "bridge actually works" is essentially the ENTIRE record-replay layer. ObservationVerifier proves that IF observation is set up correctly, it works. The bridge's job is to SET UP observation correctly during Compose body evaluation — and that setup logic is completely untested.

---

## 8. Recommended Test Matrix

### Tier 1: macOS Mock-Bridge Tests (pure Swift, fast, deterministic)

| Test | What It Validates | Mock Required |
|------|------------------|---------------|
| `testRecordReplayCycle` | startRecording -> recordAccess -> stopAndObserve replays inside wOT | ObservationRecording copy |
| `testEmptyFrameNoOp` | stopAndObserve with no recorded accesses is silent | Same |
| `testNestedRecordingFrames` | Parent/child recording frames are independent | Same |
| `testStackPopOrder` | LIFO frame processing | Same |
| `testMultipleAccessesSingleTrigger` | Only first trigger closure is retained per frame | Same |
| `testDiagnosticsClosureCount` | diagnosticsHandler receives correct count | Same |
| `testDiagnosticsElapsedNonZero` | elapsed is positive | Same |
| `testThreadIsolation` | Two threads recording concurrently don't interfere | Same + GCD |
| `testStopWithoutStartIsNoOp` | stopAndObserve on empty stack returns silently | Same |
| `testIsRecordingReflectsStackState` | isRecording true during recording, false after | Same |
| `testTriggerFiresOnChange` | Mutation after replay triggers the closure | Same + observable model |

### Tier 2: Android-Only Bridge Tests (requires emulator)

| Test | What It Validates | Requirement |
|------|------------------|-------------|
| `testBridgeDiagnosticsEndToEnd` | Full pipeline: model access during recording -> diagnostics report | `skip android test` |
| `testSingleRecompositionPerMutation` | One recomposition per onChange | Compose runtime |
| `testJNIExportsCallable` | `nativeEnable`, `nativeStartRecording`, `nativeStopAndObserve` succeed | JVM + native lib |
| `testBridgeObservationRegistrarAccess` | TCA registrar routes through bridge on Android | `#if os(Android)` |
| `testMutableStateBackingUpdate` | `triggerSingleUpdate()` increments Compose state | JNI + skip-model |
| `testSwiftThreadingFatalPresent` | `libswiftObservation.so` loads without linker error | Runtime linkage |

---

## 9. Edge Cases and Failure Modes Catalog

### 9.1 Concurrency edge cases

| Scenario | Expected Behavior | Risk Level |
|----------|------------------|------------|
| Two threads call `startRecording` simultaneously | Each gets own frame on own stack | SAFE (thread-local) |
| Thread A records, Thread B stops | B stops its own stack (or no-op if empty) | SAFE (independent stacks) |
| `BridgeObservationSupport` first initialized from two threads | Lock serializes `Java_init`; second thread gets cached result | SAFE (semaphore) |
| `diagnosticsHandler` called from multiple threads | Handler closure must be thread-safe | CALLER RESPONSIBILITY |
| `Java_access` called during `Java_initPeer` | `Java_access` checks `isJNIInitialized` + `Java_peer` nil guard; early return | SAFE (nil guard) |

### 9.2 Memory edge cases

| Scenario | Expected Behavior | Risk Level |
|----------|------------------|------------|
| View with 10,000 property accesses | 10,000 replay closures per frame (~640KB) | LOW (bounded, released on stop) |
| Deeply nested view hierarchy (100 levels) | 100 frames on stack (~100 * avg_closures * 64B) | LOW (bounded by view depth) |
| Orphaned frame (start without stop) | Frame stays until thread exits | MEDIUM (memory leak per thread) |
| `diagnosticsHandler` captures large state | Captured state held by static var | MEDIUM (must nil handler in teardown) |

### 9.3 Timing edge cases

| Scenario | Expected Behavior | Risk Level |
|----------|------------------|------------|
| Mutation during body evaluation (inside startRecording/stopAndObserve) | `willSet` fires but `bridgeSupport.willSet()` is suppressed (isEnabled=true); mutation recorded in CURRENT frame's replay closures via access() | SAFE |
| Rapid sequential mutations after `stopAndObserve` | First mutation fires onChange (one-shot), subsequent mutations ignored until re-subscription | SAFE (wOT design) |
| `DispatchQueue.main.async` in onChange delayed | Recomposition deferred; view shows stale state briefly | LOW (expected async behavior) |
| `stopAndObserve` during another `stopAndObserve` (reentrant) | Cannot happen — `stopAndObserve` is synchronous and stack is per-thread | SAFE |

### 9.4 Error/failure modes

| Scenario | Behavior | Severity |
|----------|----------|----------|
| JNI not initialized (`isJNIInitialized = false`) | `Java_initPeer` returns nil; all Java_* calls are no-ops | SILENT DEGRADATION |
| `MutableStateBacking` class not found | `Java_stateClass = nil`; `Java_initPeer` returns nil | SILENT DEGRADATION |
| Java exception in `MutableStateBacking()` constructor | `try!` CRASHES the app | CRITICAL (P2-7) |
| Java exception in `access()` or `update()` JNI call | `try!` CRASHES the app | CRITICAL (P2-7) |
| `nativeEnable()` JNI call fails | Kotlin `error()` terminates app with message | FATAL (by design) |
| `nativeStartRecording()` fails mid-session | Kotlin `error()` terminates app | FATAL (by design) |
| `nativeStopAndObserve()` fails mid-session | Kotlin `error()` terminates app | FATAL (by design) |
| `ViewObservation` init block exception (non-JNI) | Kotlin `error()` terminates app | FATAL (by design) |
| `ObservationRecording.isEnabled` read from wrong thread | Non-atomic read of bool; in practice safe on modern hardware | THEORETICAL |

---

*Research completed: 2026-02-22*
*Sources: Observation.swift (323 lines), ObservationModule.swift (23 lines), View.swift (ViewObservation + Evaluate), ViewModifier.swift (Evaluate), ObservationStateRegistrar.swift (207 lines), ObservationVerifier.swift (280 lines), ObservationTests.swift (163 lines), ObservationTrackingTests.swift (54 lines), ObservationModels.swift (36 lines), SwiftJNI.swift (isJNIInitialized + jniContext), R2-observation-bridge.md, 07-RESEARCH-RECONCILED.md, skip-ui Package.swift, skip-android-bridge Package.swift*
