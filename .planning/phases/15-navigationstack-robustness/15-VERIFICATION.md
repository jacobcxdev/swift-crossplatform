---
phase: 15-navigationstack-robustness
verified: 2026-02-24T14:30:00Z
status: passed
score: 4/4 must-haves verified
re_verification: true
gaps: []
human_verification: []
---

# Phase 15: NavigationStack Robustness Verification Report

**Phase Goal:** Fix all P2 NavigationStack tech debt — binding-driven push, JVM type erasure for multi-destination, and dismiss JNI timing — with full test coverage replacing existing `withKnownIssue` wrappers
**Verified:** 2026-02-24T14:30:00Z
**Status:** passed
**Re-verification:** Yes — re-verified after dismiss pipeline root cause investigation

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `NavigationLink(state:)` user-driven push dispatches `store.send(.push(...))` on Android — binding-driven push works | ✓ VERIFIED | `_TCANavigationStack` binding `set:` closure dispatches `.push(id:state:)` when `newPath.count > currentCount` (lines 251-263, `NavigationStack+Observation.swift`); 3 dedicated tests pass; commit `00009b4` |
| 2 | Multi-destination `NavigationStack` with multiple `navigationDestination(for:)` types resolves correctly on JVM without type erasure collisions | ✓ VERIFIED | `NavigationDestinationKeyProviding` protocol in skip-fuse-ui; `StackState.Component.destinationKey` uses `_typeName` for fully qualified names; both registration and lookup sides use protocol key; 3 tests pass; commit `f18bfd5` |
| 3 | `@Dependency(\.dismiss)` completes under full JNI effect pipeline timing on Android — `withKnownIssue` wrappers replaced with passing tests | ✓ VERIFIED | All 4 child-driven dismiss tests pass on Android: `testDismissFromChildReducer`, `testDismissAfterChildDelegateAction`, `testStackDismissFromElement`, `testParentDrivenDismissViaEffect`. 269/269 Android tests pass with 9 known issues (all pre-existing, none dismiss-related). Root cause was TCA's Merge polyfill (fixed in `7b175e4`), not OpenCombine Concatenate as 15-03 hypothesised. |
| 4 | All three fixes validated by dedicated Android tests (not indirect evidence) | ✓ VERIFIED | All tests are platform-agnostic (no Android gate). Truths 1-3 all validated by empirical Android test run (269/269 pass, `skip android test` on fuse-library). Stack dismiss test updated with polling for JNI latency resilience. |

**Score:** 4/4 truths fully verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/NavigationStack+Observation.swift` | Fixed `_TCANavigationStack` binding set closure + `destinationKey` on `Component` | ✓ VERIFIED | Push dispatch at lines 251-263; `destinationKey` static/instance properties at lines 613-625; `NavigationDestinationKeyProviding` conformance at line 715 |
| `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift` | Tests for binding-driven push and multi-destination type discrimination | ✓ VERIFIED | 6 new tests: `testBindingDrivenPush`, `testBindingDrivenPushAndPop`, `testMultipleSequentialPushes`, `testMultiDestinationTypeDiscrimination`, `testSingleDestinationStillWorks`, `testDestinationKeyIncludesTypeName` |
| `forks/skip-fuse-ui/Sources/SkipSwiftUI/Containers/Navigation.swift` | `NavigationDestinationKeyProviding` protocol + updated `destinationKeyTransformer` and `navigationDestination(for:)` | ✓ VERIFIED | Protocol defined lines 20-27; `destinationKeyTransformer` checks protocol at lines 82-85; `navigationDestination(for:)` checks protocol at lines 260-263 |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/PresentationReducer.swift` | Dismiss pipeline working reliably across JNI boundary | ✓ VERIFIED | `Empty(completeImmediately: false) + Just(.dismiss)` concatenation works correctly — the original timing issue was in TCA's Merge polyfill (fixed in `7b175e4`), not in the dismiss pipeline operators. All 4 dismiss tests pass on Android. |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Reducer/Reducers/StackReducer.swift` | Fixed stack dismiss pipeline | ✓ VERIFIED | Same `Empty + Just` concatenation works correctly for stack dismiss. `testStackDismissFromElement` passes on Android with polling for JNI latency. |
| `examples/fuse-library/Tests/NavigationTests/PresentationTests.swift` | Tests for dismiss timing reliability | ✓ VERIFIED | 4 dismiss timing tests pass on both Darwin and Android. Stack dismiss test uses polling (50ms intervals, up to 1s) for JNI latency resilience. |
| `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` | Integration tests without excessive timeouts | ✓ VERIFIED | `timeout: 10_000_000_000` removed from `addContactSaveAndDismiss` and `editSavesContact`; no 10-second timeouts remain in any test file |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `_TCANavigationStack` binding `set:` | `store.send(.push(id:state:))` | `newPath.count > currentCount` → `lastElement as? StackState<State>.Component` → push dispatch | ✓ WIRED | Lines 251-263; pattern `newPath.count > currentCount` → cast → `store.send(.push(id: component.id, state: component.element))` |
| `_NavigationDestinationViewModifier.body` | `skip-fuse-ui navigationDestination(destinationKey:)` | `NavigationDestinationKeyProviding.destinationKey` static key | ✓ WIRED | Registration side: `navigationDestination(for: StackState<State>.Component.self)` uses protocol key because `StackState.Component` conforms to `NavigationDestinationKeyProviding` on Android |
| `NavigationStack.Java_view` `destinationKeyTransformer` | `NavigationDestinationKeyProviding.destinationKey` | Protocol check on unwrapped `SwiftHashable.base` | ✓ WIRED | Lines 82-85 in `Navigation.swift`: `if let keyProvider = value as? NavigationDestinationKeyProviding { return keyProvider.destinationKey }` |
| `PresentationReducer.swift` dismiss pipeline | `DismissEffect` → `Task._cancel(id: PresentationDismissID())` → `Just(.dismiss)` fires | `Empty(completeImmediately: false)` cancel → concatenated `Just` emits → Merge polyfill forwards to Store | ✓ WIRED | Pipeline correct end-to-end. Merge polyfill fix (`7b175e4`) resolved synchronous emission loss. All 4 dismiss tests pass on Android. |
| `StackReducer.swift` dismiss pipeline | `DismissEffect` → `Task._cancel(id: NavigationDismissID(...))` → `Just(.popFrom)` fires | Same `Empty + Just` concatenation | ✓ WIRED | Same pipeline, confirmed working on Android via `testStackDismissFromElement` with polling. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| NAV-02 | 15-01, 15-03 | Path append pushes a new destination onto the navigation stack on Android | ✓ SATISFIED | Binding-driven push fix (plan 01) + dismiss timing confirmed working on Android (all 4 dismiss tests pass). |
| TCA-32 | 15-01, 15-02 | `StackState<Element>` initializes, appends, and indexes by `StackElementID` on Android | ✓ SATISFIED | Binding-driven push (plan 01) and type-discrimination key (plan 02) both strengthen TCA-32 coverage. All tests pass on both platforms. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift` | 196 | `withKnownIssue("Android timing: 500ms sleep insufficient for async effects to complete via JNI", isIntermittent: true)` | ⚠️ Warning | Pre-existing Android JNI timing `withKnownIssue` wrapper (different test, different root cause from dismiss). Not introduced by phase 15. |

No blocker anti-patterns (TODO/FIXME/placeholder) were found in new code introduced by phase 15.

### Root Cause Correction

Phase 15-03 concluded that OpenCombine's `Concatenate` operator was the root cause of Android dismiss failures. **This was incorrect.** The 15-03 executor never ran tests on Android — the conclusion was hypothetical based on code analysis alone.

**Actual root cause:** TCA's custom `Publishers.Merge` polyfill (Android-only, replacing Apple's Combine `Merge`) subscribed downstream to a `PassthroughSubject` AFTER sinking both upstream publishers. Synchronous emissions from `Just` (the dismiss action) were sent before any subscriber was attached and silently lost. This was fixed in commit `7b175e4` by reordering `receive(subscriber:)` to subscribe downstream first.

The OpenCombine operators (`Concatenate`, `PrefixUntilOutput`, `HandleEvents`) are all correct — verified by 8 isolation tests in `MergePolyfillTests.swift`.

### Human Verification Required

None — all truths verified empirically via Android test run.

---

_Verified: 2026-02-24T14:30:00Z_
_Verifier: Claude (dismiss pipeline root cause investigation)_
_Re-verification of initial report from 2026-02-24T14:00:00Z_
