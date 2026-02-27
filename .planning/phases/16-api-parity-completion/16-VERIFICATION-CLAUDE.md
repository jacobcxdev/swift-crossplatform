---
phase: 16-api-parity-completion
verified: 2026-02-24T15:45:00Z
status: gaps_found
score: 9/12 must-haves verified
gaps:
  - truth: "TextState modifiers (.bold(), .italic(), .kerning(), .font(), .foregroundColor()) compile on Android"
    status: partial
    reason: "TextState guard removal was confirmed in swift-navigation fork (0 !os(Android) guards). However testTextStateModifiersCompileAndExecute is gated #if !os(Android) — the test explicitly does not run on Android, consistent with Phase 14 CGFloat ambiguity decision. The modifiers compile on Darwin but Android execution is untested."
    artifacts:
      - path: "examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift"
        issue: "testTextStateModifiersCompileAndExecute wrapped in #if !os(Android) — does not execute on Android"
    missing:
      - "Either document that TextState modifiers are Darwin-only (CGFloat ambiguity) as an explicit known limitation in REQUIREMENTS.md, or provide an Android-safe subset test"
  - truth: "Each enablement validated by a dedicated test [that runs on Android]"
    status: partial
    reason: "All 6 enablement tests exist on disk. However: (1) testIfLetStoreAlternativePattern in BindingTests.swift is in a #if !SKIP file — does not transpile to Kotlin; (2) testSendWithAnimation and testEffectAnimation in StoreReducerTests.swift are also in a #if !SKIP file; (3) testButtonStateAnimatedAction and testButtonStateAnimatedNilAction in TextStateButtonStateTests.swift are in a #if !SKIP file. Only TextStateButtonStateTests provides ButtonState tests that could reach Android — but the entire file is #if !SKIP. All enablement tests are Darwin-only."
    artifacts:
      - path: "examples/fuse-library/Tests/TCATests/BindingTests.swift"
        issue: "File gated #if !SKIP at line 1 — testIfLetStoreAlternativePattern does not run on Android"
      - path: "examples/fuse-library/Tests/TCATests/StoreReducerTests.swift"
        issue: "File gated #if !SKIP at line 1 — testSendWithAnimation and testEffectAnimation do not run on Android"
      - path: "examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift"
        issue: "File gated #if !SKIP at line 1 — testButtonStateAnimatedAction and testButtonStateAnimatedNilAction do not run on Android"
    missing:
      - "Assess whether enablement tests need Android coverage or Darwin-only is acceptable given these are guard-removal verifications (the guards block compilation, which is a Darwin build check)"
      - "If Android coverage is required: move ButtonState/animation tests to a non-SKIP-gated file, or add equivalent tests to a file without #if !SKIP"
human_verification:
  - test: "Run skip android test from examples/fuse-library to confirm animation APIs (withTransaction chain) do not crash at runtime on Android"
    expected: "TCA Store.send with animation parameter completes without crash or fatalError on Android"
    why_human: "withTransaction delegates to withAnimation — runtime Compose bridge behavior cannot be verified by grep/static analysis"
---

# Phase 16: TCA API Parity Completion Verification Report

**Phase Goal:** Enable all P3 gated TCA extensions on Android and resolve TextState CGFloat ambiguity — with test coverage for each enablement
**Verified:** 2026-02-24T15:45:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | withTransaction delegates to withAnimation on Android instead of fatalError | VERIFIED | Transaction.swift lines 105-121: two `withTransaction` functions delegate to `withAnimation(animation, body)` when `transaction.animation` is non-nil; no `@available(*, unavailable)` |
| 2 | ButtonState.animatedSend enum case compiles on Android | VERIFIED | `grep '&& !os(Android)' ButtonState.swift` returns 0 matches — all 10 guards removed |
| 3 | TextState rich text modifiers compile on Android | PARTIAL | TextState.swift guards removed (0 matches for `&& !os(Android)`). However test is `#if !os(Android)` gated — documented CGFloat ambiguity means modifiers compile on Darwin, Android runtime untested |
| 4 | Alert and ConfirmationDialog deprecated APIs compile on Android | VERIFIED | `Alert+Observation.swift` has 0 `!os(Android)` guards. SUMMARY notes `Alert.swift`/`ConfirmationDialog.swift` at original plan paths had no guards to begin with (pure data types) |
| 5 | Binding+Observation extensions compile on Android without #if !os(Android) guard | VERIFIED | Remaining 4 `#if !os(Android)` guards in `Binding+Observation.swift` are all `ObservedObject.Wrapper` deprecated blocks (confirmed by context grep) — not Binding+Observation core extensions |
| 6 | Alert+Observation and ConfirmationDialog observation extensions work on Android | VERIFIED | Zero `!os(Android)` guards in `Alert+Observation.swift` and TCA `ConfirmationDialog.swift` |
| 7 | IfLetStore compiles on Android (guards removed) | VERIFIED | Zero `!os(Android)` guards in `IfLetStore.swift` |
| 8 | BindingLocal is defined once per platform (no duplicate) | VERIFIED | Core.swift: defined under `#if !canImport(SwiftUI)` (non-SwiftUI platforms). ViewStore.swift: defined under `#if canImport(SwiftUI)` — mutually exclusive, no duplication |
| 9 | Store.send(_:animation:) compiles on Android (withTransaction chain functional) | VERIFIED | Store.swift animation guard changed from `canImport(SwiftUI) && !os(Android)` to `canImport(SwiftUI)`. Store.swift line 119 `!os(visionOS) && !os(Android)` is a pre-existing Perception/PerceptionRegistrar guard (Android uses BridgeObservationRegistrar on the `#elseif os(Android)` branch — correct architecture) |
| 10 | @Observable alternative to IfLetStore is tested and working | PARTIAL | `testIfLetStoreAlternativePattern` exists in BindingTests.swift line 231 but file is `#if !SKIP` gated — Darwin-only |
| 11 | TextState modifiers test compiles and executes | PARTIAL | Test exists (line 177) but gated `#if !os(Android)` — Darwin-only by documented design |
| 12 | ButtonState.animatedSend is tested end-to-end | PARTIAL | `testButtonStateAnimatedAction` and `testButtonStateAnimatedNilAction` exist but TextStateButtonStateTests.swift is `#if !SKIP` gated — Darwin-only |

**Score:** 9/12 truths verified (3 partial)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `forks/skip-fuse-ui/Sources/SkipSwiftUI/Animation/Transaction.swift` | withTransaction delegates to withAnimation | VERIFIED | Lines 105-121: functional implementation, no `@available(*, unavailable)` on the two `withTransaction` functions |
| `forks/swift-navigation/Sources/SwiftNavigation/ButtonState.swift` | Unguarded animatedSend enum case | VERIFIED | 0 occurrences of `&& !os(Android)` |
| `forks/swift-navigation/Sources/SwiftNavigation/TextState.swift` | Rich text modifiers enabled on Android | VERIFIED | 0 occurrences of `&& !os(Android)` |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/Alert+Observation.swift` | animatedSend guards removed | VERIFIED | 0 `!os(Android)` guards |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/Observation/Binding+Observation.swift` | Core extensions unguarded | VERIFIED | 4 remaining guards are all `ObservedObject.Wrapper` deprecated blocks (confirmed) |
| `forks/swift-composable-architecture/Sources/ComposableArchitecture/SwiftUI/IfLetStore.swift` | Guards removed | VERIFIED | 0 `!os(Android)` guards |
| `examples/fuse-library/Tests/TCATests/BindingTests.swift` | testIfLetStoreAlternativePattern | PARTIAL | Test exists at line 231; file is `#if !SKIP` gated (Darwin-only) |
| `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift` | testSendWithAnimation, testEffectAnimation | PARTIAL | Tests exist at lines 352 and 370; file is `#if !SKIP` gated (Darwin-only) |
| `examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift` | testTextStateModifiersCompileAndExecute, testButtonStateAnimatedAction | PARTIAL | Tests exist at lines 177, 206, 224; file is `#if !SKIP` gated; TextState test additionally `#if !os(Android)` gated |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Transaction.swift` (skip-fuse-ui) | `Animation.swift` (skip-fuse-ui) | withTransaction calls withAnimation | VERIFIED | Line 107: `return try withAnimation(animation, body)` |
| `Alert+Observation.swift` (TCA) | `ButtonState.swift` (swift-navigation) | `.animatedSend` case reference | VERIFIED | 0 `!os(Android)` guards in Alert+Observation.swift; ButtonState.animatedSend unguarded |
| `Animation.swift` (TCA Effects) | `Transaction.swift` (skip-fuse-ui) | Effect.animation calls Transaction(animation:) -> withTransaction | VERIFIED | TCA Animation.swift guard changed from `canImport(SwiftUI) && !os(Android)` to `canImport(SwiftUI)` |
| `Core.swift` BindingLocal | `ViewStore.swift` BindingLocal | Mutually exclusive via canImport(SwiftUI) | VERIFIED | Core.swift: `#if !canImport(SwiftUI)` block. ViewStore.swift: `#if canImport(SwiftUI)` block. No overlap. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| TCA-19 | 16-02-PLAN | `BindableAction` protocol + `case binding(BindingAction<State>)` compiles and routes correctly on Android | SATISFIED | Pre-existing from Phase 4. Phase 16 strengthened it by removing Binding+Observation guards. REQUIREMENTS.md marks Complete with direct test evidence. |
| TCA-20 | 16-02-PLAN | `BindingReducer()` applies binding mutations to state on Android | SATISFIED | Pre-existing from Phase 4. Phase 16 removed BindingLocal duplication. REQUIREMENTS.md marks Complete with direct test evidence. |
| NAV-05 | 16-01-PLAN, 16-02-PLAN | `.sheet(item: $store.scope(...))` presents modal content on Android | SATISFIED | Pre-existing from Phase 13. Phase 16 removed Alert/ConfirmationDialog observation guards. REQUIREMENTS.md marks Complete. |
| NAV-07 | 16-01-PLAN, 16-02-PLAN | `.popover(item: $store.scope(...))` displays popover on Android | SATISFIED | Pre-existing from Phase 13. Phase 16 scope confirmed popover architectural fallback preserved. REQUIREMENTS.md marks Complete. |

**Note:** Requirements TCA-19, TCA-20, NAV-05, NAV-07 were already marked Complete in REQUIREMENTS.md from earlier phases. Phase 16's contribution was removing the Android guards that blocked compilation of associated APIs — strengthening the existing status. No orphaned requirements found.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift` | 1 | `#if !SKIP` file-level gate | Warning | All 3 enablement tests (testButtonStateAnimatedAction, testButtonStateAnimatedNilAction, testTextStateModifiersCompileAndExecute) are Darwin-only |
| `examples/fuse-library/Tests/TCATests/BindingTests.swift` | 1 | `#if !SKIP` file-level gate | Warning | testIfLetStoreAlternativePattern is Darwin-only |
| `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift` | 1 | `#if !SKIP` file-level gate | Warning | testSendWithAnimation and testEffectAnimation are Darwin-only |
| `examples/fuse-library/Tests/NavigationTests/TextStateButtonStateTests.swift` | 173 | `#if !os(Android)` inner gate on TextState test | Info | Documented design decision (CGFloat ambiguity from Phase 14) — not an oversight |

### Human Verification Required

#### 1. Animation Chain Runtime Validation

**Test:** Run `skip android test` from `examples/fuse-library/` and confirm TCA tests exercising `Store.send(_:animation:)` do not crash
**Expected:** No `fatalError` from withTransaction, animation parameter silently no-ops in test context
**Why human:** The withTransaction→withAnimation→Compose bridge path involves JNI/Kotlin runtime behavior that static analysis cannot verify

### Gaps Summary

**Source guard removals are complete and verified.** The code changes for Phase 16 (withTransaction implementation, ButtonState/TextState guard removal, TCA-wide guard removal) are all in place and confirmed.

**The gap is in test coverage reach.** The phase goal specifies "with test coverage for each enablement." All 6 enablement tests were written, but every test file used for Phase 16 tests is gated `#if !SKIP` at the file level, meaning none of the new tests execute on Android via the Skip transpiler. Additionally, `testTextStateModifiersCompileAndExecute` carries an inner `#if !os(Android)` gate consistent with the Phase 14 CGFloat ambiguity decision.

**Practical impact is low** because the enablements being tested are primarily compilation correctness (guard removals) — which is inherently a Darwin build-time check. The withTransaction runtime behavior on Android needs human emulator validation (flagged above).

**Disposition options:**
1. Accept as-is: document that enablement tests are Darwin compilation checks; Android runtime is covered by the pre-existing test suite passing after guard removal
2. Gap-close: add Android-safe subset tests (e.g., ButtonState animatedSend test) to a non-SKIP-gated file

---

_Verified: 2026-02-24T15:45:00Z_
_Verifier: Claude (gsd-verifier)_
