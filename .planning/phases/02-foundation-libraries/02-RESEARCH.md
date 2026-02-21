# Phase 2: Foundation Libraries - Research

**Researched:** 2026-02-21
**Domain:** Cross-platform Swift utility libraries (CasePaths, IdentifiedCollections, CustomDump, IssueReporting) on Android via Skip Fuse
**Confidence:** MEDIUM-HIGH (upgraded after deep dives)

## Summary

Phase 2 covers making four Point-Free utility libraries compile and run correctly on Android. These are pure Swift logic libraries with no UI dependencies, but they touch several Swift runtime features that need verification on Android: Mirror reflection, enum ABI metadata pointer arithmetic, KeyPath, Foundation types, and dynamic library symbol loading for test framework detection.

**CRITICAL FINDING (IssueReporting):** IssueReporting has a **three-layer detection failure** on Android that causes `reportIssue()` to silently write to stderr instead of failing tests. This means ALL TCA test assertions (exhaustive store testing, dependency checking) and CustomDump's `expectNoDifference`/`expectDifference` become **no-ops** on Android tests. The root cause: (1) `isTesting` returns `false` because it checks Xcode-specific env vars, (2) `dlsym` symbol resolution has no `#if os(Android)` branch, (3) all fallback paths require `canImport(Darwin)`. **This must be fixed in the fork before any meaningful Android testing.**

**CasePaths has two distinct risk profiles.** The `@CasePathable` macro is **100% safe** — it expands to pure Swift `guard case` pattern matching with zero platform dependencies. However, TCA's core reducer infrastructure uses `EnumMetadata` (CasePaths' `@_spi(Reflection)` ABI pointer arithmetic) in **6 files that compile on Android** — including `Binding.swift`, `EphemeralState.swift`, `PresentationID.swift`, `NavigationID.swift`, `PresentationReducer.swift`, and `StackReducer.swift`. This **cannot be gated behind `#if !os(Android)`** without breaking TCA. The ABI layout is platform-independent by design and should work on aarch64 Android, but is unverified.

**CustomDump's Mirror usage is safe** (LOW risk). All Mirror APIs (`reflecting`, `children`, `displayStyle`, `subjectType`, `superclassMirror`) are Swift runtime, not Foundation. `_typeName()` is stdlib. `#available(... *)` wildcard correctly evaluates to `true` on Android. `ByteCountFormatter` and `DateFormatter` exist in swift-corelibs-foundation and work on Linux/Android (DateFormatter requires ICU, which Skip bundles). The only concrete fix needed is a potential `#if os(Android)` fallback for `ByteCountFormatter` in `Data.customDumpDescription` if it proves incomplete.

**IdentifiedCollections** is pure Swift data structures over OrderedCollections and is the lowest risk — expected zero changes.

**Primary recommendation:** Fork the 3 new libraries, wire all forks into fuse-library, then **fix IssueReporting's test context detection first** (this unblocks all other library testing). After that, adopt a test-first approach for the remaining libraries.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Rename all fork branches to `dev/swift-crossplatform`. Existing forks use `flote/service-app` (12 PF/GRDB forks) and `dev/observation-tracking` (2 Skip forks). All must be renamed. Update `.gitmodules` accordingly. This is the first plan (02-01).
- Create 3 new forks: swift-case-paths, swift-identified-collections, xctest-dynamic-overlay. Fork from upstream at latest release tag, create `dev/swift-crossplatform` branch. Add as submodules. **CRITICAL: IssueReporting fork directory MUST be `xctest-dynamic-overlay` (not `swift-issue-reporting`)** — SPM uses directory name as package identity, and 10+ forks depend on `package: "xctest-dynamic-overlay"`.
- Wire ALL forks into fuse-library Package.swift with `.package(path: "../../forks/<name>")` entries. Completes SPM-05.
- Update fork count references in STATE.md, ROADMAP.md, CLAUDE.md.
- Full Android runtime validation required (compile AND execute on emulator).
- Per-library test targets in fuse-library: CasePathsTests, IdentifiedCollectionsTests, CustomDumpTests, IssueReportingTests.
- Upstream tests must pass on macOS (no regressions).
- Test-first for Mirror/reflection: run upstream tests first, only add guards for specific failures.
- Inline `#if` guards only (no separate platform files).
- Gate non-essential APIs with documentation tracking.
- Same branch (`dev/swift-crossplatform`) for all work.
- CustomDump Apple conformances: gate with `#if canImport`.
- IssueReporting production: `print()` to logcat on Android.
- IssueReporting test context: Swift Testing (`#expect`/`Issue.record()`).
- Match upstream error detail level and Apple severity behavior.
- Macros are host-side only; validate expanded output compiles on Android.
- swift-syntax is upstream (no fork needed).
- swift-collections (OrderedCollections) is upstream (no fork needed).

### Claude's Discretion
- Expanded output validation approach for `@CasePathable`
- Fix location decisions (library shims vs macro plugin) if expanded output uses unavailable APIs

### Deferred Ideas (OUT OF SCOPE)
- 100% API compatibility tracking document (documentation deliverable, not Phase 2 implementation)
- Android-native log integration via JNI (`android.util.Log`)
- Macro plugin Android compilation (SPM-04) -- only validate expanded output
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CP-01 | `@CasePathable` macro generates `AllCasePaths` and `CaseKeyPath` accessors on Android | **VERIFIED SAFE (DD-2):** Macro expands to 100% pure Swift (`guard case` + closures). Zero platform deps. |
| CP-02 | `.is(\.caseName)` returns correct Bool for case checking on Android | **VERIFIED SAFE (DD-2):** Uses macro-generated closures. Pure Swift. |
| CP-03 | `.modify(\.caseName) {}` mutates associated value in-place on Android | **VERIFIED SAFE (DD-2):** Same mechanism as CP-02. |
| CP-04 | `@dynamicMemberLookup` dot-syntax returns Optional on Android | Compiler feature, not runtime. Works if code compiles. |
| CP-05 | `allCasePaths` static variable returns collection of all case key paths on Android | **VERIFIED SAFE (DD-2):** Generated `IndexingIterator` over pure Swift struct. |
| CP-06 | `root[case: caseKeyPath]` subscript extracts/embeds associated value on Android | **VERIFIED SAFE (DD-2):** Pure Swift subscript via `._$embed`. |
| CP-07 | `@Reducer enum` pattern synthesizes body and scope on Android | TCA macro, but CasePaths provides the CaseKeyPath infrastructure. Phase 3 concern. |
| CP-08 | `AnyCasePath` with custom embed/extract closures works on Android | **MEDIUM-HIGH RISK (DD-1):** TCA uses `EnumMetadata` ABI pointer arithmetic in 6 core files. ABI should be identical on aarch64 but unverified. Cannot gate out. |
| IC-01 | `IdentifiedArrayOf<T>` initializes from array literal on Android | Pure Swift over OrderedDictionary. Lowest risk library. |
| IC-02 | `array[id: id]` subscript read returns correct element in O(1) on Android | OrderedDictionary lookup. Pure Swift. |
| IC-03 | `array[id: id] = nil` subscript write removes element on Android | Pure Swift mutation. |
| IC-04 | `array.remove(id:)` returns removed element on Android | Pure Swift. |
| IC-05 | `array.ids` property returns ordered set of all IDs on Android | OrderedSet from swift-collections. Pure Swift. |
| IC-06 | `IdentifiedArrayOf` conforms to Codable when element is Codable on Android | Swift conditional conformance. Works if compiler works. |
| CD-01 | `customDump(_:)` outputs structured value representation on Android | **VERIFIED LOW RISK (DD-3):** All Mirror APIs are Swift stdlib. `_typeName()` is platform-independent. |
| CD-02 | `String(customDumping:)` creates string from value dump on Android | **VERIFIED LOW RISK (DD-3):** Same engine as CD-01. |
| CD-03 | `diff(_:_:)` computes string diff between two values on Android | **VERIFIED LOW RISK (DD-3):** `isMirrorEqual` uses only stdlib APIs. |
| CD-04 | `expectNoDifference(_:_:)` asserts equality with diff output on Android | **BLOCKED BY IR FIX (DD-5):** Uses `reportIssue()` which is no-op in Android tests until IssueReporting fork is fixed. |
| CD-05 | `expectDifference(_:_:operation:changes:)` asserts value changes on Android | **BLOCKED BY IR FIX (DD-5):** Same as CD-04. |
| IR-01 | `reportIssue(_:)` reports string message as runtime issue on Android | **CRITICAL (DD-5):** Three-layer detection failure. Silently writes to stderr instead of failing tests. Fork fix required. |
| IR-02 | `reportIssue(_:)` reports thrown Error instance on Android | **CRITICAL (DD-5):** Same mechanism as IR-01. |
| IR-03 | `withErrorReporting {}` synchronous wrapper catches and reports on Android | **CRITICAL (DD-5):** Uses reportIssue internally. Errors caught but only logged, not test failures. |
| IR-04 | `await withErrorReporting {}` async wrapper catches and reports on Android | **CRITICAL (DD-5):** Same as IR-03 but async. |
</phase_requirements>

## Standard Stack

### Core (Phase 2 Libraries)
| Library | Upstream Repo | Purpose | Fork Status |
|---------|--------------|---------|-------------|
| CasePaths | pointfreeco/swift-case-paths | Enum pattern matching, CaseKeyPath | NEW FORK needed |
| IdentifiedCollections | pointfreeco/swift-identified-collections | O(1) ID-indexed arrays | NEW FORK needed |
| CustomDump | pointfreeco/swift-custom-dump | Structured value dumping/diffing | EXISTING FORK (already in forks/) |
| IssueReporting | pointfreeco/xctest-dynamic-overlay | Runtime error surfacing | NEW FORK needed (package name is xctest-dynamic-overlay) |

### Upstream Dependencies (NO fork needed)
| Library | Purpose | Why No Fork |
|---------|---------|-------------|
| swift-collections (OrderedCollections) | Backing store for IdentifiedCollections | Apple package, pure Swift, expected to work |
| swift-syntax (509-603) | Macro expansion for CasePaths | Host-side only, never runs on Android |

### Key Dependency Chain
```
CasePaths -> IssueReporting (via xctest-dynamic-overlay package)
CustomDump -> IssueReporting (via xctest-dynamic-overlay package)
CustomDump -> XCTestDynamicOverlay (deprecated layer over IssueReporting)
IdentifiedCollections -> OrderedCollections (from swift-collections)
```

**CRITICAL: Package naming & identity.** The upstream repo is `pointfreeco/xctest-dynamic-overlay` but it provides the `IssueReporting` product. The fork directory MUST be `forks/xctest-dynamic-overlay` (not `swift-issue-reporting`) because **SPM uses the directory name as package identity** for local path dependencies. 10+ forks depend on `package: "xctest-dynamic-overlay"`. The Package.swift `name:` field must also remain `"xctest-dynamic-overlay"`. The root manifest's `.package(path:)` overrides all transitive URL references to `pointfreeco/xctest-dynamic-overlay` across the entire dependency graph.

## Architecture Patterns

### Recommended Project Structure for Phase 2

```
forks/
  swift-case-paths/           # NEW fork
  swift-identified-collections/ # NEW fork
  xctest-dynamic-overlay/     # NEW fork (directory name MUST match package identity)
  swift-custom-dump/          # EXISTING fork
  [14 existing forks...]      # Branch renamed to dev/swift-crossplatform

examples/fuse-library/
  Package.swift               # Add .package(path:) for ALL 17+ forks
  Tests/
    CasePathsTests/           # NEW test target
    IdentifiedCollectionsTests/ # NEW test target
    CustomDumpTests/           # NEW test target
    IssueReportingTests/       # NEW test target
```

### Pattern 1: Fork Creation Workflow
**What:** Create new fork from upstream, branch, add as submodule
**When:** For each of the 3 new libraries
**Steps:**
1. Fork upstream repo on GitHub to `jacobcxdev/<name>`
2. Clone and create `dev/swift-crossplatform` branch from latest release tag
3. Add as git submodule: `git submodule add -b dev/swift-crossplatform https://github.com/jacobcxdev/<name>.git forks/<name>`
4. Add `.package(path: "../../forks/<name>")` to fuse-library Package.swift

### Pattern 2: Branch Rename for Existing Forks
**What:** Rename tracking branches from `flote/service-app` / `dev/observation-tracking` to `dev/swift-crossplatform`
**Steps per fork:**
1. `cd forks/<name>`
2. `git branch -m <old-branch> dev/swift-crossplatform`
3. `git push origin dev/swift-crossplatform`
4. `git push origin --delete <old-branch>` (or keep as alias)
5. Update `.gitmodules` branch entry
6. Update parent repo submodule config

### Pattern 3: Platform Guard Strategy (Inline `#if`)
**What:** Conditional compilation for Android-incompatible code
**When:** A specific API or framework import fails on Android
**Example:**
```swift
// For Apple-only framework conformances (already present in most files):
#if canImport(CoreImage)
  import CoreImage
  // conformances...
#endif

// For APIs that exist on Apple but not Android:
#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
  // Apple-specific code
#endif

// For Android-specific fallbacks:
#if os(Android)
  // Android alternative
#else
  // Original code
#endif
```

### Pattern 4: Test Target Wiring in fuse-library
**What:** Per-library test targets that import the fork and verify Android behavior
**Example Package.swift addition:**
```swift
.testTarget(
    name: "CasePathsTests",
    dependencies: [
        .product(name: "CasePaths", package: "swift-case-paths"),
    ]
),
```

### Anti-Patterns to Avoid
- **Proactive `#if os(Android)` guards without evidence:** Do NOT add guards speculatively. Run tests first, fix what actually fails. The CONTEXT.md explicitly requires test-first for Mirror/reflection.
- **Separate platform files (e.g., `Dump+Android.swift`):** Locked decision says inline `#if` guards only.
- **Forking swift-collections or swift-syntax:** These are upstream dependencies that should work without modification.
- **Modifying macro plugin code for Android:** Macros expand on macOS host. Only the expanded output needs to compile for Android.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Enum case extraction | Custom reflection code | CasePaths' `@CasePathable` macro | ABI metadata handling is extremely delicate |
| Value diffing | String comparison | CustomDump's `diff()` | Mirror traversal with cycle detection, type-aware formatting |
| Issue reporting in tests | Direct `XCTFail` calls | IssueReporting's `reportIssue()` | Handles both XCTest and Swift Testing, test context detection |
| ID-indexed collections | Dictionary + Array combo | IdentifiedCollections | Maintains insertion order with O(1) lookup, Codable, Equatable |
| Branch rename automation | Manual per-fork commands | Shell script loop over .gitmodules | 14+ forks, error-prone to do manually |
| Package.swift fork wiring | Manual path assembly | Pattern from existing fuse-library | SPM path resolution must be exact |

**Key insight:** These libraries exist precisely because the problems they solve have subtle edge cases. The Phase 1 fork-first strategy applies: make minimal changes, verify with tests, keep diffs small for future upstream PRs.

## Common Pitfalls

### Pitfall 1: Package Name vs Repo Name vs Directory Name (IssueReporting) (UPDATED — DD-6)
**What goes wrong:** SPM uses the **directory name** as package identity for local path dependencies (SE-0292). If the fork directory is `swift-issue-reporting` but downstream forks reference `package: "xctest-dynamic-overlay"`, SPM can't resolve the dependency.
**Why it happens:** Point-Free renamed the library to IssueReporting but kept the repo name `xctest-dynamic-overlay`. SPM identity matching uses directory name, not Package.swift `name:` field.
**How to avoid:** The fork directory MUST be `forks/xctest-dynamic-overlay` (not `forks/swift-issue-reporting`). The Package.swift `name:` field must remain `"xctest-dynamic-overlay"`. **10+ forks** depend on `package: "xctest-dynamic-overlay"` — all will resolve correctly against the local path override.
**Warning signs:** SPM resolution errors mentioning "no package named xctest-dynamic-overlay" or "multiple packages with identity xctest-dynamic-overlay".

### Pitfall 2: CasePaths EnumReflection ABI Pointer Arithmetic on Android (UPGRADED — DD-1)
**What goes wrong:** `EnumReflection.swift` uses `UnsafeRawPointer` arithmetic to read Swift enum metadata (EnumMetadata, ValueWitnessTable offsets, FieldRecord). Pointer sizes or struct layouts could differ.
**Why it happens:** The code accesses Swift's internal ABI at specific byte offsets (e.g., `10 * pointerSize + 2 * 4` for getEnumTag at offset 88 on aarch64). While ABI is platform-independent by design, it has never been verified on Android aarch64.
**CRITICAL UPDATE (DD-1):** TCA uses `EnumMetadata` in **6 core files that compile on Android** — this is NOT limited to the deprecated `AnyCasePath(unsafe:)`. `Binding.swift:285` calls `AnyCasePath(unsafe:).extract()`, and `EphemeralState`, `PresentationID`, `NavigationID`, `PresentationReducer`, `StackReducer` all use `EnumMetadata().tag()/.project()/.caseName()` without `#if !os(Android)` guards. **Cannot gate EnumReflection out.**
**How to avoid:** Keep EnumReflection available on Android. Add a runtime smoke test exercising `EnumMetadata` on a known enum at app/test startup. If it crashes (SIGBUS/SIGSEGV), the 6 TCA files need CasePathable-based alternatives (significant Phase 3 rework).
**Warning signs:** Crashes in `extractHelp`, `EnumMetadata.tag()`, or `project()` on Android. SIGBUS/SIGSEGV from bad pointer reads.
**Confidence:** MEDIUM-HIGH that ABI works — same compiler source, same 64-bit layout, same VWT offsets.

### Pitfall 3: CustomDump Foundation Conformances on Android
**What goes wrong:** `Foundation.swift` has multiple Apple-only guards using `#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)`:
- `NSException` (line 114) -- not available on Linux/Android
- `NSExpression` (line 137) -- not available on Linux/Android
- `NSTimeZone` cast (line 208) -- uses different path on non-Apple
These guards already exclude Android correctly. But other conformances use `#if !os(WASI)` (Data, Date, NSNotification, URLRequest) which INCLUDE Android -- these need runtime verification.
**Why it happens:** Foundation on Android (swift-corelibs-foundation) has `ByteCountFormatter`, `DateFormatter`, etc. but some methods may be stubs.
**How to avoid:** Run CustomDump's upstream tests on Android. The `#if !os(WASI)` guards should be fine since Android has full Foundation. The `#if os(iOS) || os(macOS) || ...` guards correctly exclude Android already.
**Warning signs:** Runtime crashes in `ByteCountFormatter.string(fromByteCount:)` or `DateFormatter.string(from:)`.

### Pitfall 4: Duration.formatted() Not Available on Android
**What goes wrong:** `Swift.swift` has `Duration: CustomDumpStringConvertible` guarded by `#if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)`. This already excludes Android. BUT if someone tries to remove this guard thinking "Duration is in Swift stdlib", the `.formatted(.units(...))` method requires FoundationInternationalization which may not be available.
**Why it happens:** `Duration` is a Swift stdlib type, but `.formatted()` is a Foundation extension.
**How to avoid:** Leave the existing `#if os(iOS) || ...` guard in place. It correctly excludes Android.

### Pitfall 5: IssueReporting BreakpointReporter is Darwin-Only
**What goes wrong:** `BreakpointReporter` uses `sysctl` and `SIGTRAP` to detect/trigger debugger breakpoints. This is wrapped in `#if canImport(Darwin)`. On Android, this reporter simply won't be available.
**Why it happens:** Debugger attachment detection is OS-specific.
**How to avoid:** This is already handled upstream -- the `#if canImport(Darwin)` guard means it compiles away on Android. The `DefaultReporter` falls back to stderr logging on non-Darwin platforms. No changes needed.

### Pitfall 6: IssueReporting DefaultReporter SwiftUI Runtime Warning Scanning
**What goes wrong:** `DefaultReporter` scans loaded dylibs to find SwiftUI's runtime warning mechanism for purple Xcode warnings. This dylib scanning won't work on Android.
**Why it happens:** The `runtimeWarn()` function iterates `_dyld_image_count()` which is Darwin-specific.
**How to avoid:** The code already has fallback paths. On non-Darwin platforms, it falls back to `printError()` which writes to stderr. On Android, `print()` routes to logcat. This should work without changes, but verify at runtime.

### Pitfall 7: IssueReporting Test Context Detection on Android (CRITICAL — DD-5)
**What goes wrong:** On Android, `reportIssue()` silently writes to stderr instead of failing tests. ALL TCA test assertions and CustomDump's `expectNoDifference`/`expectDifference` become no-ops.
**Why it happens:** Three-layer cascading failure: (1) `isTesting` returns `false` — checks Xcode-specific env vars (`XCTestBundlePath`, etc.) that Skip doesn't set; (2) `dlsym` symbol resolution in `SwiftTesting.swift:606-628` has no `#if os(Android)` branch — Android is NOT `os(Linux)` in Swift 6.2, falls through to `return nil`; (3) `#if DEBUG && canImport(Darwin)` fallback paths are false on Android.
**How to avoid:** Fix in xctest-dynamic-overlay fork: (A) Add `#if os(Android)` to `isTesting` with Skip-compatible process detection, (B) Add `#if os(Android)` to `unsafeBitCast(symbol:in:)` with same `dlopen`/`dlsym` as Linux branch, or (C) Register custom `IssueReporter` at test launch that calls `XCTFail` directly.
**Warning signs:** Tests appearing to pass even when `reportIssue()` is called. No test failures from `expectNoDifference`. `stderr`/logcat shows issue messages but test suite reports 0 failures.
**This is the #1 priority fix for Phase 2.** Without it, no meaningful Android test validation is possible.

### Pitfall 8: Submodule Wiring Order Matters
**What goes wrong:** Adding all forks to Package.swift at once without respecting the dependency chain causes SPM resolution failures.
**Why it happens:** `swift-custom-dump` depends on `xctest-dynamic-overlay` (IssueReporting). `swift-case-paths` also depends on `xctest-dynamic-overlay`. If the IssueReporting fork isn't wired first, the other packages can't resolve their dependency.
**How to avoid:** Wire forks in dependency order: (1) swift-issue-reporting (xctest-dynamic-overlay), (2) swift-case-paths and swift-custom-dump (both depend on IssueReporting), (3) swift-identified-collections (independent, but wire together). Verify `swift build` after each addition.

### Pitfall 9: SwiftUI Conformance Already Guarded with !os(Android)
**What goes wrong:** Accidentally removing the `!os(Android)` guard from `SwiftUI.swift` conformance file in CustomDump.
**Why it happens:** The existing fork already has `#if canImport(SwiftUI) && !os(Android)` (visible in grep results). This was likely added in a previous fork change.
**How to avoid:** Preserve this guard. SwiftUI types (Color, etc.) don't exist on Android even though `canImport(SwiftUI)` might pass through Skip's SkipUI.

## Code Examples

### Fork Wiring in Package.swift
```swift
// examples/fuse-library/Package.swift
// Add these dependencies (dependency order matters for resolution):
.package(path: "../../forks/xctest-dynamic-overlay"),  // Provides IssueReporting (directory = package identity)
.package(path: "../../forks/swift-case-paths"),
.package(path: "../../forks/swift-identified-collections"),
.package(path: "../../forks/swift-custom-dump"),
// ... existing forks ...

// NOTE: swift-case-paths and swift-custom-dump reference
// package: "xctest-dynamic-overlay" in their Package.swift.
// SPM resolves this via the fork's Package.swift name field,
// which must remain "xctest-dynamic-overlay".
```

### Per-Library Test Target
```swift
// In fuse-library Package.swift targets array:
.testTarget(
    name: "CasePathsTests",
    dependencies: [
        .product(name: "CasePaths", package: "swift-case-paths"),
    ]
),
.testTarget(
    name: "IdentifiedCollectionsTests",
    dependencies: [
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
    ]
),
.testTarget(
    name: "CustomDumpTests",
    dependencies: [
        .product(name: "CustomDump", package: "swift-custom-dump"),
    ]
),
.testTarget(
    name: "IssueReportingTests",
    dependencies: [
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
    ]
),
```

### CasePaths Test Example (Verify @CasePathable on Android)
```swift
import CasePaths
import Testing

@CasePathable
enum Action {
    case increment
    case setText(String)
    case child(ChildAction)
}

@CasePathable
enum ChildAction {
    case tap
}

@Test func casePathableIsCheck() {
    let action = Action.setText("hello")
    #expect(action.is(\.setText))
    #expect(!action.is(\.increment))
}

@Test func casePathableExtract() {
    let action = Action.setText("hello")
    #expect(action[case: \.setText] == "hello")
    #expect(action[case: \.increment] == nil)
}

@Test func casePathableModify() {
    var action = Action.setText("hello")
    action.modify(\.setText) { $0 = "world" }
    #expect(action[case: \.setText] == "world")
}
```

### CustomDump Test Example (Verify Mirror on Android)
```swift
import CustomDump
import Testing

struct User: Equatable {
    var id: Int
    var name: String
}

@Test func customDumpProducesOutput() {
    let user = User(id: 1, name: "Blob")
    var output = ""
    customDump(user, to: &output)
    #expect(output.contains("User("))
    #expect(output.contains("id: 1"))
    #expect(output.contains("name: \"Blob\""))
}

@Test func diffDetectsChanges() {
    let user1 = User(id: 1, name: "Blob")
    let user2 = User(id: 1, name: "Blob Jr.")
    let result = diff(user1, user2)
    #expect(result != nil)
    #expect(result!.contains("name"))
}
```

### IssueReporting Test Example
```swift
import IssueReporting
import Testing

@Test func reportIssueStringMessage() {
    withKnownIssue {
        reportIssue("Something went wrong")
    }
}

@Test func withErrorReportingCatchesErrors() {
    struct TestError: Error {}
    let result: Int? = withErrorReporting {
        throw TestError()
    }
    #expect(result == nil)
}
```

### Branch Rename Script Pattern
```bash
#!/bin/bash
# Rename all fork branches to dev/swift-crossplatform
for fork in forks/*/; do
    name=$(basename "$fork")
    cd "$fork"
    old_branch=$(git rev-parse --abbrev-ref HEAD)
    if [ "$old_branch" != "dev/swift-crossplatform" ]; then
        git branch -m "$old_branch" dev/swift-crossplatform
        git push origin dev/swift-crossplatform
        echo "Renamed $name: $old_branch -> dev/swift-crossplatform"
    fi
    cd ../..
done
# Then update .gitmodules branch entries
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| XCTestDynamicOverlay (XCTFail) | IssueReporting (reportIssue) | 2024 | IssueReporting supports both XCTest and Swift Testing |
| AnyCasePath(unsafe:) reflection | @CasePathable macro | 2023 | Macro avoids runtime ABI metadata probing entirely |
| xctest-dynamic-overlay repo name | Still xctest-dynamic-overlay | Never changed | Package.swift name must stay xctest-dynamic-overlay |
| Manual enum case matching | CaseKeyPath with @dynamicMemberLookup | 2023 | Type-safe, compiler-checked enum access |

**Deprecated/outdated:**
- `XCTAssertNoDifference`: Deprecated in favor of `expectNoDifference` (uses IssueReporting instead of XCTest directly)
- `XCTAssertDifference`: Deprecated in favor of `expectDifference`
- `AnyCasePath.init(unsafe embed:)`: Deprecated, directs users to `@CasePathable` macro. Still functional but uses risky ABI reflection.
- `XCTestDynamicOverlay` product: Thin re-export of IssueReporting. Deprecated but still shipped for backward compat.

## Deep Dive Findings

### DD-1: CasePaths EnumReflection — TCA Cannot Avoid It

**Confidence: HIGH** (direct source code inspection of TCA fork)

**Finding:** TCA uses `EnumMetadata` (CasePaths' `@_spi(Reflection)` API) in **6 core files that compile on Android**. Gating EnumReflection behind `#if !os(Android)` would break TCA.

| File | Lines | Usage | Android-gated? |
|------|-------|-------|----------------|
| `Binding.swift` | 285 | `AnyCasePath(unsafe: { .binding($0) }).extract(from: self)` | NO — inside `#if canImport(SwiftUI)` but before `#if !os(Android)` |
| `EphemeralState.swift` | 29, 44 | `EnumMetadata().tag()`, `.associatedValueType()` | NO |
| `PresentationID.swift` | 15-16 | `EnumMetadata().tag()`, `.project()` | NO |
| `NavigationID.swift` | 79-80, 111 | `EnumMetadata().tag()`, `.project()` | NO |
| `PresentationReducer.swift` | 164-165 | `EnumMetadata().caseName()` | NO |
| `StackReducer.swift` | 137-138 | `EnumMetadata().caseName()` | NO |

**ABI safety assessment (MEDIUM-HIGH confidence):** Swift's ABI metadata layout (EnumMetadata, ValueWitnessTable, FieldRecord offsets) is defined in platform-independent C++ headers (`Metadata.h`, `ValueWitness.def`). `pointerSize` is computed dynamically. Heap object headers are 2×pointerSize on both Darwin and non-ObjC platforms (Android). The offsets used (e.g., `10 * pointerSize + 2 * 4` for `getEnumTag`) should be identical. `swift_getTypeByMangledNameInContext` is a stable runtime entry point present in `libswiftCore.so`.

**Recommendation:** Keep EnumReflection available on Android (Strategy A — lowest risk). Add a runtime smoke test early in app startup that exercises `EnumMetadata` on a known enum to detect ABI incompatibilities immediately.

**No other PF libraries** use EnumReflection — only TCA imports `@_spi(Reflection)`.

### DD-2: @CasePathable Macro Expansion Is 100% Pure Swift

**Confidence: HIGH** (verified via macro expansion tests in CasePathableMacroTests.swift)

The `@CasePathable` macro generates:
- An `AllCasePaths` struct with subscript, per-case properties, and iterator
- Each property uses `._$embed({ Enum.caseName($0) }) { guard case .caseName(let v) = $0 else { return nil }; return v }`
- Uses ONLY: `guard case` (language feature), closures, `Optional`, `Sendable`, `IndexingIterator`
- **Zero** Foundation/Darwin/UIKit imports in expanded code
- **Zero** EnumMetadata/EnumReflection references in expanded code

The deprecated `AnyCasePath(unsafe:)` is the only path that uses EnumReflection. The `@CasePathable` macro completely bypasses it.

### DD-3: CustomDump Mirror APIs Are Safe on Android

**Confidence: HIGH** (direct source inspection)

| API | Risk | Reasoning |
|-----|------|-----------|
| `Mirror(reflecting:)` | NONE | Swift stdlib, in `libswiftCore.so` |
| `mirror.children` | NONE | Swift stdlib |
| `mirror.displayStyle` | NONE | Swift stdlib, all 8 cases handled |
| `mirror.superclassMirror` | LOW | Recursive traversal, but standard API |
| `mirror.subjectType` | NONE | Swift stdlib |
| `_typeName()` | NONE | Swift stdlib, platform-independent demangling |
| `isMirrorEqual` | LOW | Fallback to `String(describing:)` for childless non-Equatable values |
| `#available(... *)` wildcard | NONE | Correctly evaluates to `true` on Android — `AnyKeyPath.debugDescription` primary path taken |

**Enum display style handling** uses `mirror.children.first?.label` for case names (from compiled type metadata) and `typeName(mirror.subjectType)` for type prefix. Both are platform-independent.

### DD-4: CustomDump Foundation Conformances — ByteCountFormatter Exists

**Confidence: MEDIUM-HIGH** (swift-corelibs-foundation source inspection + web research)

Both formatters exist in swift-corelibs-foundation:
- **ByteCountFormatter**: Fully implemented (~392 lines). Missing `locale` property and `copy()`. Works on Linux. Uses NumberFormatter internally (which uses ICU).
- **DateFormatter**: Fully implemented. Requires ICU (~40MB `lib_FoundationICU.so` which Skip bundles). Works on Linux/Android.

**Remaining risk areas in `Foundation.swift`:**
| Type | Guard | Risk |
|------|-------|------|
| `Data` (line 35) | `#if !os(WASI)` | LOW — ByteCountFormatter exists, but test `string(fromByteCount:)` output format |
| `Date` (line 44) | `#if !os(WASI)` | LOW — DateFormatter works, but verify `XXXXX` timezone format specifier |
| `NSPredicate` (line 189) | None | MEDIUM — may be partial stub on Android |
| `NSValue` (line 249) | None | MEDIUM — may be partial stub on Android |
| `NSAttributedString` (line 71) | None | MEDIUM — may not exist on Android Foundation |

### DD-5: IssueReporting Three-Layer Detection Failure on Android

**Confidence: HIGH** (direct source inspection of IssueReporting fork)

**This is the most critical Phase 2 finding.** On Android, `reportIssue()` silently writes to stderr instead of failing tests. The root cause is a cascading detection failure:

**Layer 1 — `isTesting` returns `false` (`IsTesting.swift:29-42`):**
Checks Xcode-specific env vars (`XCTestBundlePath`, `XCTestConfigurationFilePath`, etc.) and Darwin-specific process names (`xctest`, `.xctest`). Skip's `skip android test` sets none of these.

**Layer 2 — `dlsym` has no `os(Android)` branch (`SwiftTesting.swift:606-628`):**
```swift
#if os(Linux)
  dlopen("lib\(library).so", RTLD_LAZY)  // Android is NOT Linux in Swift 6.2
#elseif canImport(Darwin)
  dlopen(nil, RTLD_LAZY)
#else
  return nil  // ← Android falls here
#endif
```
In Swift 6.2, `os(Android)` is distinct from `os(Linux)`. All symbol lookups return `nil`.

**Layer 3 — Fallbacks require Darwin (`SwiftTesting.swift:24-33`):**
`#if DEBUG && canImport(Darwin)` guards on direct dlsym into Testing/XCTest frameworks. False on Android.

**Impact chain:**
- `reportIssue()` → `DefaultReporter` → `isTesting == false` → `runtimeWarn()` → `printError()` → stderr (logcat)
- `expectNoDifference()` (CD-04) → `reportIssue()` → **no-op in tests**
- `expectDifference()` (CD-05) → `reportIssue()` → **no-op in tests**
- ALL TCA exhaustive store assertions → `reportIssue()` → **no-op in tests**

**Required fixes in xctest-dynamic-overlay fork:**
1. Add `#if os(Android)` to `isTesting` with Skip-compatible detection (env var or process argument check)
2. Add `#if os(Android)` branch to `unsafeBitCast(symbol:in:)` using same `dlopen`/`dlsym` pattern as Linux
3. Alternatively: register a custom `IssueReporter` at test launch that calls XCTFail directly

### DD-6: SPM Package Identity Resolution — Directory Name Is Identity

**Confidence: HIGH** (SPM SE-0292 specification + empirical verification)

Since SPM 5.5+ (SE-0292):
- **Local path packages**: Identity = directory name (NOT Package.swift `name:` field)
- **URL packages**: Identity = last URL path component (minus `.git`)
- **`package:` in `.product()`** matches against package identity

**Consequence:** The fork directory MUST be `forks/xctest-dynamic-overlay` (not `forks/swift-issue-reporting`) for the identity `xctest-dynamic-overlay` to match all 10+ downstream forks that use `package: "xctest-dynamic-overlay"`.

**Verified downstream dependents:**
swift-composable-architecture, swift-custom-dump, swift-dependencies, swift-navigation, swift-sharing, swift-perception, swift-clocks, combine-schedulers, sqlite-data, swift-structured-queries — all use `package: "xctest-dynamic-overlay"`.

The root manifest's `.package(path: "../../forks/xctest-dynamic-overlay")` overrides ALL transitive URL references to `pointfreeco/xctest-dynamic-overlay` across the entire dependency graph. No changes needed in any fork's Package.swift.

## Open Questions

1. **Does `_typeName()` produce correct output on Android?**
   - **Likely RESOLVED (LOW risk):** `_typeName` is Swift stdlib (`libswiftCore.so`), not Foundation. Output format is determined by the compiler/ABI version, not the OS. The regex in `AnyType.swift` handles known mangling patterns. Include in runtime smoke test.

2. ~~**Does `AnyKeyPath.debugDescription` work on Android?**~~
   - **RESOLVED:** The `#available(macOS 13.3, iOS 16.4, ... *)` check evaluates the `*` wildcard to `true` on Android. The primary path (`self.debugDescription`) is always taken. Swift 6.2 includes this property. No risk.

3. **How does Skip's test runner set up the process environment on Android?**
   - What we know: `skip android test` copies the Swift test binary to the device and runs it. Uses swift-corelibs-xctest. Swift Testing not yet supported by Skip.
   - What's unclear: Exact process arguments, whether `XCTestBundlePath` or similar env vars are set.
   - Recommendation: Print `ProcessInfo.processInfo.environment` and `.arguments` in first Android test run to understand the exact environment. Use this to write the `isTesting` fix.

4. ~~**Will the fork name cause SPM resolution conflicts?**~~
   - **RESOLVED:** Fork directory MUST be `xctest-dynamic-overlay`. SPM uses directory name as identity. All 10+ downstream forks match on `package: "xctest-dynamic-overlay"`. Local path overrides transitive URL references.

5. **NEW: Will `EnumMetadata` ABI pointer arithmetic work on Android aarch64?**
   - What we know: ABI layout is platform-independent by design. `pointerSize = 8` on both platforms. Heap object headers are 2×pointerSize on non-ObjC platforms. VWT function pointers at documented offsets.
   - What's unclear: No one has verified this on Android. `swift_getTypeByMangledNameInContext` must be exported from `libswiftCore.so`.
   - Recommendation: Add early runtime smoke test exercising `EnumMetadata` on a known enum. If it crashes, we need to replace TCA's 6 usage sites with CasePathable-based alternatives (significant Phase 3 work).

6. **NEW: How to fix IssueReporting's test context detection for Android?**
   - Option A: Add `#if os(Android)` branch to `isTesting` + `unsafeBitCast(symbol:in:)` — most complete fix
   - Option B: Register custom `IssueReporter` at test launch that calls `XCTFail` directly — sidesteps detection entirely
   - Option C: Set custom env var in skip test command and check for it — least invasive
   - Recommendation: Option A is the right long-term fix for the fork. Option B is a good interim fallback.

## Sources

### Primary (HIGH confidence)
- Direct source code inspection of `forks/swift-custom-dump/Sources/` -- all conformance files, Internal/, Dump.swift, Diff.swift
- Direct source code inspection of TCA fork `forks/swift-composable-architecture/Sources/` -- EnumMetadata usage in 6 files
- Direct source code inspection of IssueReporting via TCA's `.build/checkouts/xctest-dynamic-overlay/Sources/` -- full call chain traced
- `pointfreeco/swift-case-paths` macro expansion tests (CasePathableMacroTests.swift) -- 16 test cases verified
- `pointfreeco/swift-identified-collections` Package.swift via GitHub raw content
- `.gitmodules` in project repo -- current fork configuration
- SPM SE-0292 package identity specification -- identity = directory name for local paths

### Secondary (MEDIUM confidence)
- [Swift ABI TypeMetadata documentation](https://github.com/apple/swift/blob/main/docs/ABI/TypeMetadata.rst) -- enum metadata layout
- [Swift ABI Stability Manifesto](https://github.com/apple/swift/blob/main/docs/ABIStabilityManifesto.md) -- platform-independent ABI design
- [How Mirror Works (swift.org)](https://www.swift.org/blog/how-mirror-works/) -- Mirror implementation details
- [Skip porting guide](https://skip.dev/docs/porting/) -- Foundation module split on Android
- [Skip native Swift packages blog](https://skip.dev/blog/android-native-swift-packages/) -- C library differences on Android
- [Skip testing documentation](https://skip.dev/docs/testing/) -- Swift Testing not yet supported on Android
- [ByteCountFormatter swift-corelibs-foundation PR #1227](https://github.com/swiftlang/swift-corelibs-foundation/pull/1227) -- full implementation verified
- [Android app size and lib_FoundationICU.so](https://forums.swift.org/t/android-app-size-and-lib-foundationicu-so/78399) -- ICU bundling for DateFormatter

### Tertiary (LOW confidence)
- swift-corelibs-foundation GitHub issues -- NSPredicate, NSValue, NSAttributedString completeness on Android unverified
- Web search results on Swift ABI on Android -- no specific Android aarch64 ABI verification sources found
- [Android NDK dynamic linker](https://github.com/android/ndk/issues/1244) -- dlsym/dlopen behavior on Android

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- direct source inspection, dependency chain verified
- Architecture: HIGH -- follows established Phase 1 fork-first pattern
- CasePaths @CasePathable macro: HIGH -- 100% pure Swift, verified via macro expansion tests
- CasePaths EnumReflection (TCA usage): MEDIUM-HIGH -- ABI platform-independent by design, 6 TCA files require it, unverified on Android aarch64
- CustomDump Mirror: HIGH -- all Mirror APIs are Swift stdlib, `_typeName()` is platform-independent, `#available` wildcard works correctly
- CustomDump Foundation conformances: MEDIUM-HIGH -- ByteCountFormatter/DateFormatter exist on Android, but edge cases need runtime verification
- IdentifiedCollections: HIGH -- pure data structures, no platform dependencies
- IssueReporting test detection: **CRITICAL** -- three-layer failure confirmed, `reportIssue()` becomes stderr-only on Android, must fix in fork
- IssueReporting production path: HIGH -- `printError()` → stderr → logcat works correctly
- SPM package identity: HIGH -- SE-0292 specification, empirically verified against 10+ forks
- Pitfalls: HIGH -- identified through direct source code analysis across all 4 libraries

**Research date:** 2026-02-21 (deep dives completed same day)
**Valid until:** 2026-03-21 (stable libraries, infrequent releases)
