# Domain Pitfalls

**Domain:** Cross-platform Swift/Skip/TCA framework (observation bridge, JNI, fork management)
**Researched:** 2026-02-20
**Overall Confidence:** HIGH (grounded in codebase analysis + official docs + community evidence)

## Critical Pitfalls

Mistakes that cause rewrites, infinite loops, or project-blocking failures.

### Pitfall 1: withObservationTracking onChange Fires Only Once (Re-registration Required)

**What goes wrong:** Swift's `withObservationTracking` calls its `onChange` closure exactly once -- on the first observed property change -- then auto-cancels. If you do not re-register observation after each onChange, the view stops receiving updates after the first state mutation. This is by design (SE-0395) but is a trap when building a bridge layer that must continuously drive Compose recomposition.

**Why it happens:** Developers assume onChange behaves like a persistent subscription (KVO-style or Combine publisher). It does not. The Observation framework deliberately uses a fire-once model where SwiftUI internally re-registers on every body evaluation cycle.

**Consequences:**
- After the first state change triggers recomposition, subsequent mutations silently do nothing
- View appears "frozen" after first interaction -- works once, then stops
- Extremely confusing because the first tap works fine

**Prevention:**
- The `ObservationRecording.stopAndObserve()` implementation in `Observation.swift` already handles this correctly by calling `withObservationTracking` during each `Evaluate()` cycle in skip-ui's View.swift (lines 90-96). The record-replay pattern re-registers on every body evaluation, mirroring SwiftUI's internal behavior.
- When modifying this code, **never** cache or persist the observation subscription across body evaluations. Each `Evaluate()` call must start a fresh recording frame.
- Test by verifying that a counter increments on every tap, not just the first.

**Detection:** View updates work exactly once then freeze. Logging in `triggerSingleUpdate()` shows it fires once then never again.

**Phase relevance:** Phase 1 (observation bridge fix) -- this is the core semantic that must be correct.

**Confidence:** HIGH -- verified against Apple documentation and codebase implementation.

---

### Pitfall 2: Backwards Write Causing Infinite Compose Recomposition

**What goes wrong:** When `withMutation` calls increment a Compose `MutableState` counter during body evaluation (composition), Compose detects the state change and immediately schedules recomposition. If the state write happens synchronously inside the composition scope, this creates a backwards write: read state -> evaluate body -> write state -> triggers recomposition -> read state -> infinite loop.

**Why it happens:** TCA's `@ObservableState` macro generates `_$id` (a UUID) that changes on every state assignment via `_$willModify()`. Each `_$willModify` call triggers `withMutation`, which calls `BridgeObservationSupport.willSet()`, which calls `Java_update()` on the `MutableStateBacking` counter. With TCA, even reading a Store property can cascade into identity mutations, creating dozens of counter increments per body evaluation.

**Consequences:**
- App enters infinite recomposition loop (the exact bug documented in CONCERNS.md)
- 100% CPU usage, UI frozen or flickering
- Android app is completely unusable

**Prevention:**
- The `ObservationRecording.isEnabled` flag (line 88 of Observation.swift) gates `bridgeSupport.willSet()` -- when the observation bridge is enabled, willSet calls during recording are suppressed (lines 34-36, 45-46), preventing counter increments during body evaluation.
- The fix requires that `isEnabled` is set to `true` before any view renders. The `nativeEnable()` JNI call in ViewObservation's init block handles this.
- Counter increments must happen only from `withObservationTracking`'s onChange callback (via `triggerSingleUpdate`), never from direct willSet/withMutation calls during composition.
- **Critical invariant:** During body evaluation (between `startRecording` and `stopAndObserve`), zero `MutableStateBacking.update()` calls should fire. All recomposition triggers must be deferred to the onChange callback.

**Detection:** Logcat shows thousands of `MutableStateBacking.update()` calls per second. CPU pegged at 100%. Add logging to `Java_update` to count calls per frame.

**Phase relevance:** Phase 1 (observation bridge fix) -- this IS the primary bug to solve.

**Confidence:** HIGH -- root cause verified by reading Observation.swift, ObservationStateRegistrar.swift, and View.swift.

---

### Pitfall 3: JNI Thread Affinity Violations

**What goes wrong:** `JNIEnv` pointers are thread-local and cannot be shared across threads. If a Swift background thread (e.g., a TCA Effect returning on a different executor) calls `Java_update()` or `Java_access()` without being attached to the JVM, the app crashes with a SIGSEGV or `java.lang.RuntimeException`.

**Why it happens:** TCA Effects run on cooperative thread pools. When an Effect completes and sends an action, the Store processes the reducer on whatever thread the Effect completed on. If that thread was never attached to the JVM via `AttachCurrentThread()`, any JNI call crashes. The `jniContext` helper in skip-android-bridge may or may not handle this -- it depends on implementation.

**Consequences:**
- Crash (SIGSEGV) on Android when effects complete
- Intermittent failures that depend on thread scheduling -- hard to reproduce
- Stack traces show mangled Swift names, making diagnosis difficult

**Prevention:**
- Verify that `jniContext` in skip-android-bridge calls `AttachCurrentThread()` for non-main threads before making JNI calls. Read the skip-bridge source to confirm.
- TCA Store mutations should be funneled to the main thread/actor before triggering JNI bridge calls. Consider wrapping `triggerSingleUpdate()` in a `DispatchQueue.main.async` or `@MainActor` context.
- The `BridgeObservationSupport` already uses a `DispatchSemaphore` for synchronization (line 249), but this only prevents data races on the Swift side -- it does not ensure JNI thread attachment.
- Add stress tests with effects that complete on background threads.

**Detection:** Intermittent SIGSEGV crashes in `Java_update` or `Java_access`. Logcat shows JNI errors about invalid `JNIEnv`.

**Phase relevance:** Phase 1-2 (observation bridge fix + TCA integration testing).

**Confidence:** MEDIUM -- the `jniContext` implementation may already handle this, but it needs verification. JNI thread affinity is a well-documented Android NDK requirement.

---

### Pitfall 4: Fork Divergence Becomes Unmergeable

**What goes wrong:** With 12 forks on a single branch (`flote/service-app`), each accumulating Android-specific changes, the forks diverge from upstream to the point where merging new upstream releases becomes a multi-day effort or is abandoned entirely. The project becomes permanently stuck on old versions.

**Why it happens:**
- No systematic tracking of what changed in each fork and why
- Changes are mixed: some are surgical `#if os(Android)` guards (easy to merge), others are structural refactors (hard to merge)
- Upstream releases may refactor the exact files you modified
- 12 forks means 12x the merge conflict surface
- Branch naming (`flote/service-app`) does not encode the upstream base version

**Consequences:**
- Cannot adopt TCA 2.0 when it ships (Stephen Celis said "very soon")
- Security patches in upstream packages are missed
- New upstream features unavailable
- Eventually maintaining forks becomes a full-time job

**Prevention:**
- Create FORKS.md immediately, documenting for each fork: upstream base version, commits ahead, each change with rationale, and whether the change is upstream-PR-candidate
- Minimize diff surface: prefer `#if os(Android)` guards over structural changes
- Use `// SKIP ANDROID:` comment markers on every modified line for easy grep auditing
- Run `git log --oneline upstream/main..HEAD` monthly for each fork to track divergence
- When TCA 2.0 drops, plan a dedicated merge sprint -- do not try to trickle-merge

**Detection:** `git rev-list --count upstream/main..HEAD` exceeding 20 commits per fork. Any fork where you cannot explain every commit's purpose.

**Phase relevance:** All phases, but especially Phase 3 (stable releases) and whenever upstream ships major versions.

**Confidence:** HIGH -- this is a well-known pattern in fork-based projects; the 149 commits across forks already represent significant divergence.

---

## Moderate Pitfalls

### Pitfall 5: Compose Recomposition Skipping Breaks Observation Replay

**What goes wrong:** Compose aggressively skips recomposition of composables whose inputs have not changed (stability-based skipping). If the bridge triggers a `MutableState` increment but Compose determines the composable's parameters are "stable and unchanged," the `Evaluate()` call (and thus `startRecording`/`stopAndObserve`) is skipped entirely. The view does not update despite the state having changed.

**Why it happens:** Compose's smart recomposition compares function parameters. If the Skip-generated composable wrapper passes parameters that Compose considers stable (primitives, data classes), Compose may decide to skip recomposition even though the underlying Swift Observable has changed.

**Prevention:**
- Ensure the `MutableStateBacking` counter is read inside the composable scope so Compose tracks it as a dependency
- The `BridgeObservationSupport.access()` calls `Java_access(index)` which reads the counter -- verify this read happens inside the Compose snapshot system
- Do not mark Skip-generated composable wrappers with `@Stable` or `@Immutable` annotations that would encourage skipping
- Test with Compose's recomposition debugger (Layout Inspector) to verify views actually recompose

**Detection:** State changes fire but specific views do not update. Recomposition count (visible in Android Studio Layout Inspector) stays at 0 for affected composables.

**Phase relevance:** Phase 1-2 (observation bridge fix + integration testing).

**Confidence:** MEDIUM -- this is a known Compose behavior, but whether it affects Skip-generated code specifically needs runtime verification.

---

### Pitfall 6: Thread-Local Recording Stack Corruption Under Concurrent Composition

**What goes wrong:** The `ObservationRecording` class uses `pthread_key_t` thread-local storage for its frame stack (lines 96-118 of Observation.swift). If Compose recomposes multiple views concurrently on different threads (which it does), and a Swift callback re-enters the recording stack from an unexpected thread, frames can be mismatched -- a `stopAndObserve()` call pops a frame that belongs to a different view's `startRecording()`.

**Why it happens:** The thread-local design is correct for the common case (each thread has its own stack). The problem arises if:
1. A `startRecording` happens on thread A
2. The body evaluation triggers a side effect that synchronously calls into Kotlin and back via JNI on thread B
3. `stopAndObserve` is called on thread B instead of thread A

**Prevention:**
- Verify that `startRecording()` and `stopAndObserve()` are always called on the same thread -- they should bracket `body.Evaluate()` which is synchronous
- Add a debug assertion that the thread ID matches between start and stop
- Never dispatch async work between `startRecording` and `stopAndObserve`
- The current implementation looks correct (both calls happen in `Evaluate()` on the same call stack), but any future refactoring must preserve this invariant

**Detection:** `assertionFailure("ObservationRecording: replay closures recorded but no trigger")` firing (line 137). Random missing view updates after concurrent view evaluations.

**Phase relevance:** Phase 2 (TCA integration with complex view hierarchies).

**Confidence:** MEDIUM -- the design handles this correctly today, but the invariant is fragile and undocumented beyond code comments.

---

### Pitfall 7: DispatchSemaphore Deadlocks on Main Thread

**What goes wrong:** `BridgeObservationSupport` uses `DispatchSemaphore(value: 1)` (line 249 of Observation.swift) to protect JNI peer access. If `Java_update` is called from the main thread while another thread holds the semaphore, the main thread blocks. On Android, blocking the main thread for >5 seconds triggers an ANR (Application Not Responding) dialog.

**Why it happens:** `DispatchSemaphore.wait()` is a blocking call. If two threads race to call `Java_init` or `Java_update`, one blocks until the other finishes its JNI call. JNI calls can be slow (especially the first call which loads classes), and if the JVM is doing GC at the same time, the hold time extends.

**Prevention:**
- Replace `DispatchSemaphore` with a non-blocking synchronization mechanism: `os_unfair_lock`, `NSLock`, or an actor
- Alternatively, ensure all JNI bridge calls happen on a dedicated serial queue and use `async` dispatch from the main thread
- Profile JNI call duration under load -- if calls take >1ms, the semaphore approach is risky
- Do not use `DispatchSemaphore` on the main thread in production code (well-known iOS/Android anti-pattern)

**Detection:** ANR dialogs on Android. Instruments/systrace showing main thread blocked on semaphore. UI stutters during rapid state changes.

**Phase relevance:** Phase 1-2 (observation bridge fix + performance testing).

**Confidence:** HIGH -- `DispatchSemaphore` on main thread is a documented anti-pattern; whether it manifests depends on contention frequency.

---

### Pitfall 8: `try!` in JNI Calls Crashes Instead of Degrading Gracefully

**What goes wrong:** Lines 220, 233, and 245 of Observation.swift use `try!` for JNI calls (`cls.create`, `peer.call`). If the JNI call fails for any reason (class not found, method signature mismatch, JVM out of memory), the app crashes with a `fatalError` instead of gracefully handling the failure.

**Why it happens:** During development, `try!` is convenient because JNI failures indicate configuration bugs. But in production, transient JVM issues (GC pressure, class loader races during app startup) can cause intermittent failures that should not crash.

**Prevention:**
- Replace `try!` with `try?` or `do/catch` with logging for non-critical paths
- `Java_initPeer()` failures should result in `Java_peer` remaining nil (already handled by the guard on line 206) -- but the `try!` on line 220 will crash before reaching that guard
- `Java_access` and `Java_update` failures should log and skip rather than crash
- Keep `try!` only during development; replace with defensive handling before shipping

**Detection:** Crash reports with `Fatal error: 'try!' expression unexpectedly raised an error` in JNI-related functions.

**Phase relevance:** Phase 2-3 (production hardening + stable releases).

**Confidence:** HIGH -- the `try!` calls are visible in the code.

---

### Pitfall 9: SPM + Gradle + skipstone Three-Way Build Failures

**What goes wrong:** The build system involves three interacting dependency resolvers: SPM resolves Swift packages, Gradle resolves Android/Kotlin dependencies, and Skip's `skipstone` plugin bridges the two by generating Gradle projects from `Package.swift`. A version mismatch in any layer can cause cryptic build failures that point to the wrong layer.

**Why it happens:**
- SPM resolves all 12 forks + transitive dependencies into a flat graph; version conflicts surface as opaque resolution errors
- `skipstone` generates Gradle files from SPM state -- if SPM resolution changes (adding/removing a dependency), the generated Gradle may be stale
- Gradle has its own caching (`~/.gradle/caches/`) that can hold stale artifacts
- Clean builds behave differently from incremental builds because `skipstone` output is in `.build/plugins/outputs/` which persists across incremental builds
- `SKIP_BRIDGE` environment variable gates entire dependency subtrees -- forgetting it changes the dependency graph

**Prevention:**
- When builds fail inexplicably, clean all three caches: `rm -rf .build/ ~/Library/Developer/Xcode/DerivedData/ ~/.gradle/caches/`
- Document the `SKIP_BRIDGE` requirement in build docs -- it is not optional for Fuse mode
- Pin exact versions in all Package.swift files (no `.upToNextMajor`), especially for Skip framework packages
- Test clean builds in CI (not just incremental) -- many issues only appear on clean
- After changing any `Package.swift`, rebuild from clean to ensure `skipstone` regenerates correctly

**Detection:** Build errors mentioning "cannot find module" for packages that exist. Gradle errors about missing project references. Android build succeeds but app crashes at runtime because bridge code was not regenerated.

**Phase relevance:** All phases, especially Phase 3 (stable releases + CI setup).

**Confidence:** HIGH -- multi-layer build systems are a well-known source of subtle failures; the project already has 14 Package.swift files.

---

### Pitfall 10: Submodule Pointer Desync Across Team Members

**What goes wrong:** Git submodules record a specific commit SHA. When one developer updates a fork and pushes the parent repo, other developers must run `git submodule update --recursive` to sync. If they forget (or run `git pull` without `--recurse-submodules`), they build against stale fork versions. With 12+ submodules, this happens frequently.

**Why it happens:**
- `git pull` does NOT update submodules by default
- Developers habitually use `git pull` without submodule flags
- 12 submodules means 12 opportunities for desync per pull
- The Makefile provides `make pull-all` but developers must remember to use it
- Submodule status is not immediately visible in most git UIs

**Prevention:**
- Configure `git config --global submodule.recurse true` for all team members (makes `git pull` auto-update submodules)
- Add a git hook (`post-merge`) that runs `git submodule update --init --recursive` automatically
- The existing Makefile targets (`make status`, `make pull-all`) are good -- document them prominently
- Add a pre-build check (Xcode build phase or Package.swift plugin) that verifies submodule SHAs match expected values
- Consider shallow submodules (`--depth 1`) to reduce clone time from the current ~700 MB

**Detection:** Build failures that only happen for specific team members. "Works on my machine" where the fix is `git submodule update`.

**Phase relevance:** Phase 3 (stable releases + onboarding new contributors).

**Confidence:** HIGH -- this is the single most common complaint about git submodules in large projects.

---

## Minor Pitfalls

### Pitfall 11: Swift `print()` Invisible on Android

**What goes wrong:** Standard `print()` statements produce no output on Android. Developers add debug prints, see nothing in Logcat, and waste time debugging the wrong thing.

**Prevention:** Use `OSLog.Logger` exclusively (as documented in `docs/skip/debugging.md`). Establish a project convention: `let logger = Logger(subsystem: "dev.jacobcx.crossplatform", category: "ModuleName")`. Lint for bare `print()` calls in CI.

**Phase relevance:** All phases.

**Confidence:** HIGH -- documented in Skip's official debugging guide.

---

### Pitfall 12: Key Paths Not Supported Across Bridge Boundary

**What goes wrong:** Skip's bridging reference explicitly states "Key paths: NOT supported" for bridging between compiled Swift and transpiled Swift/Kotlin. TCA makes heavy use of key paths for scoping stores and accessing state. If any key path expression crosses the bridge boundary, it will fail to compile or crash at runtime.

**Prevention:**
- All TCA state scoping must happen entirely on the Swift (native) side -- never pass key paths through JNI
- The current architecture correctly keeps TCA entirely in Fuse mode (native Swift), so key paths stay in Swift-land
- If future work introduces a transpiled (Lite) layer that needs to interact with TCA state, key paths will be the blocker
- Document this constraint prominently so no one tries to bridge a `WritableKeyPath` to Kotlin

**Phase relevance:** Phase 2 (TCA on Android) and any future Lite+Fuse hybrid architecture.

**Confidence:** HIGH -- stated in Skip's bridging reference documentation.

---

### Pitfall 13: Int is 32-bit on JVM (Overflow Risk)

**What goes wrong:** Kotlin/JVM `Int` is 32-bit while Swift `Int` is 64-bit. If TCA state includes `Int` values that exceed `Int32.max` (e.g., timestamps, large IDs), they overflow silently or crash when crossing the JNI bridge. The `MutableStateBacking` index is passed as `Int32` (line 233 of Observation.swift: `Int32(index).toJavaParameter()`).

**Prevention:**
- Use `Int64` explicitly for any value that might exceed 32-bit range
- The keypath index (used in `BridgeObservationSupport`) is unlikely to exceed Int32 range, but audit any numeric values crossing the bridge
- Add compile-time or runtime assertions for Int-to-Int32 narrowing

**Phase relevance:** Phase 2 (TCA integration).

**Confidence:** HIGH -- documented in Skip's transpilation reference.

---

### Pitfall 14: Upstream PR Rejection Due to Style/Scope Mismatch

**What goes wrong:** After stabilizing fork changes, PRs to Skip or Point-Free are rejected because they include too many unrelated changes, use different code style, or introduce patterns the maintainers have explicitly decided against.

**Prevention:**
- Keep fork changes atomic: one concern per commit, clearly documented
- For Skip upstream: Marc endorsed the fork-first approach and recommended using the `SKIP_BRIDGE` section in skip-ui's Package.swift. Follow this pattern exactly.
- For Point-Free upstream: Stephen Celis requested a "public GitHub discussion when ready" -- do not open PRs without discussion first. TCA 2.0 may make some fork changes unnecessary.
- Study each upstream repo's CONTRIBUTING.md, PR template, and recent merged PRs for style guidance
- Split fork changes into "minimal upstream candidate" and "project-specific extensions"

**Phase relevance:** Phase 4+ (upstream contribution), but commit hygiene must start in Phase 1.

**Confidence:** MEDIUM -- based on stakeholder communication documented in PROJECT.md.

---

### Pitfall 15: `swiftThreadingFatal` Workaround Masking Real Crashes

**What goes wrong:** Lines 294-298 of Observation.swift define a `@_cdecl` stub for `_ZN5swift9threading5fatalEPKcz` to work around a missing symbol in `libswiftObservation.so`. This stub does nothing except print -- meaning any real threading fatal error in Swift's threading library is silently swallowed instead of crashing.

**Why it happens:** A legitimate linker fix (referenced PR swift#77890) has not yet landed in the Android Swift SDK being used. The workaround prevents the app from crashing on launch but masks genuine threading errors.

**Prevention:**
- Track the upstream fix (swift#77890) and remove the workaround when the Android Swift SDK includes it
- Add a comment with the minimum SDK version that includes the fix
- If threading issues occur, suspect this stub first -- it may be hiding the real error
- Consider adding logging with stack trace capture instead of just `print("swiftThreadingFatal")`

**Detection:** Mysterious threading corruption without crash logs. The app survives situations it should not.

**Phase relevance:** Phase 1 (observation bridge) -- this workaround is already in the codebase.

**Confidence:** HIGH -- the workaround is visible in the code with an explanatory comment.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Observation bridge fix (Phase 1) | Pitfall 2: Infinite recomposition from backwards writes | Ensure `isEnabled` gates all willSet calls during recording; test with high-frequency TCA mutations |
| Observation bridge fix (Phase 1) | Pitfall 1: onChange fires once | Verify record-replay re-registers on every Evaluate() cycle; test multi-tap sequences |
| Observation bridge fix (Phase 1) | Pitfall 7: Semaphore deadlock | Profile JNI call contention; consider replacing DispatchSemaphore with lock |
| TCA on Android (Phase 2) | Pitfall 3: JNI thread affinity | Verify jniContext handles AttachCurrentThread; test effects completing on background threads |
| TCA on Android (Phase 2) | Pitfall 6: Recording stack corruption | Assert thread identity between start/stop; test nested Fuse views |
| TCA on Android (Phase 2) | Pitfall 12: Key paths cannot bridge | Keep all TCA scoping in native Swift; never pass WritableKeyPath through JNI |
| Stable releases (Phase 3) | Pitfall 4: Fork divergence | Create FORKS.md; track upstream distance; minimize diff surface |
| Stable releases (Phase 3) | Pitfall 9: Three-way build failures | Clean-build CI; pin exact versions; document SKIP_BRIDGE requirement |
| Stable releases (Phase 3) | Pitfall 10: Submodule desync | Configure recurse=true; add post-merge hook |
| Upstream contributions (Phase 4+) | Pitfall 14: PR rejection | Discuss first per Stephen's request; match upstream style; atomic changes |
| All phases | Pitfall 11: print() invisible | Use OSLog.Logger exclusively |

## Sources

- [Apple withObservationTracking documentation](https://developer.apple.com/documentation/observation/withobservationtracking(_:onchange:))
- [Swift Evolution SE-0395: Observability](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md)
- [JNI Tips - Android Developers](https://developer.android.com/training/articles/perf-jni)
- [JNI Best Practices - Avoiding Common Pitfalls](https://moldstud.com/articles/p-jni-best-practices-avoiding-common-pitfalls-in-android-development)
- [How to Avoid Recomposition Loops in Jetpack Compose](https://medium.com/@pavelbo/how-to-avoid-recomposition-loops-in-jetpack-compose-9bc65882a15f)
- [Compose Best Practices - Android Developers](https://developer.android.com/develop/ui/compose/performance/bestpractices)
- [Skip Framework - Modes Documentation](https://skip.dev/docs/modes/)
- [Skip Framework - Bridging Reference](https://skip.dev/docs/bridging/)
- [Skip Framework - Debugging](https://skip.dev/docs/debugging/)
- [Skip Framework - Dependencies](https://skip.dev/docs/dependencies/)
- [Git Submodule Patterns - Atlassian](https://www.atlassian.com/git/tutorials/git-submodule)
- [Using withObservationTracking outside SwiftUI](https://www.polpiella.dev/observable-outside-of-a-view/)
- [Swift Observation Deep Dive - Fat Bob Man](https://fatbobman.com/en/posts/mastering-observation/)
- Codebase: `forks/skip-android-bridge/Sources/SkipAndroidBridge/Observation.swift`
- Codebase: `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/ObservationStateRegistrar.swift`
- Codebase: `forks/skip-ui/Sources/SkipUI/SkipUI/View/View.swift`

---

*Pitfalls audit: 2026-02-20*
