# Research Summary: Observation Bridge Fix + TCA Android Integration

**Domain:** Cross-platform Swift framework -- bridging Swift Observation to Jetpack Compose for TCA on Android
**Researched:** 2026-02-20
**Overall confidence:** HIGH

## Executive Summary

The observation bridge fix is the single critical-path item that unlocks TCA on Android. The fix uses a record-replay pattern: during Compose view body evaluation, Swift `access()` calls are recorded into a thread-local frame stack, then replayed inside `withObservationTracking` after body evaluation completes. When any observed property mutates, the `onChange` callback fires exactly once and triggers a single `MutableStateBacking.update(0)` JNI call, causing one Compose recomposition instead of the thousands caused by TCA's high-frequency UUID-based identity mutations.

The implementation is approximately 90% complete. The skip-android-bridge fork (`dev/observation-tracking` branch) adds 142 lines implementing `ObservationRecording` (thread-local frame stack, record-replay, JNI exports) and `BridgeObservationSupport.triggerSingleUpdate()`. The skip-ui fork adds 23 lines implementing `ViewObservation` (Kotlin JNI hook object) and wiring `startRecording`/`stopAndObserve` calls around `Evaluate()`. The TCA fork already routes Android through `SkipAndroidBridge.Observation.ObservationRegistrar` in both `ObservationStateRegistrar` and `Store`.

The remaining work is integration testing and edge case handling: verifying the end-to-end flow prevents infinite recomposition with real TCA apps, testing navigation lifecycle (subscription cleanup on disposal), validating JNI thread safety under concurrent Compose recomposition, and stress-testing high-frequency mutations. The `swiftThreadingFatal` stub is a required workaround for `libswiftObservation.so` loading until Swift 6.3 ships the upstream fix (PR #77890).

TCA 2.0 was sneak-peeked at Point-Free's Feb 2026 live event but has no release date. It will remove the Combine dependency and simplify many TCA APIs. The project correctly targets TCA 1.x now with OpenCombine 0.14.0+ providing Combine compatibility on Android. Migration to TCA 2.0 should be planned as a separate milestone when it stabilizes.

## Key Findings

**Stack:** Native Swift Observation (`libswiftObservation.so`) + custom record-replay bridge (`ObservationRecording`) + single-trigger recomposition via `MutableStateBacking.update(0)`. No Perception backport needed on Android.

**Architecture:** Three-layer fix spanning skip-android-bridge (recording/replay/JNI), skip-ui (ViewObservation hooks in Evaluate()), and TCA (registrar wiring). All changes gate behind `#if os(Android)` / `SKIP_BRIDGE` / `ObservationRecording.isEnabled` to preserve iOS behavior.

**Critical pitfall:** Infinite recomposition returns silently if `ViewObservation.nativeEnable()` fails to load the native bridge library. The Kotlin try-catch swallows the error and `isEnabled` stays false, causing all `willSet`/`withMutation` calls to increment the counter directly -- recreating the original bug with no visible error.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Observation Bridge Validation** - Test the existing fork implementation end-to-end
   - Addresses: Core observation fix (record-replay, willSet suppression, single-trigger recomposition)
   - Avoids: Infinite recomposition (Pitfall 2), onChange fire-once (Pitfall 1), bridge init failure (Pitfall 3)
   - Rationale: The implementation exists but has never been tested with a real TCA app on Android. This is the gating phase.

2. **TCA Integration Testing** - Verify TCA patterns work with the bridge fix
   - Addresses: Store scoping, effects via OpenCombine, navigation (NavigationStack, sheet, alert), bindings
   - Avoids: JNI thread affinity violations (Pitfall 3), key path bridging issues (Pitfall 12), recording stack corruption (Pitfall 6)
   - Rationale: Depends on Phase 1. Many TCA patterns are already verified in AndroidParityTests but not under the observation bridge.

3. **Stability and Hardening** - Edge cases, performance, production readiness
   - Addresses: Concurrent recomposition, semaphore contention, try! crash handling, stress tests
   - Avoids: DispatchSemaphore deadlock (Pitfall 7), try! crashes (Pitfall 8)
   - Rationale: Production quality requires handling edge cases that demo apps may not hit.

4. **Fork Releases and Documentation** - Tagged versions, FORKS.md, upstream prep
   - Addresses: Stable fork releases, fork change documentation, upstream PR candidates
   - Avoids: Fork divergence (Pitfall 4), submodule desync (Pitfall 10), upstream PR rejection (Pitfall 14)
   - Rationale: Stabilization step before any external consumption or upstream contribution.

**Phase ordering rationale:**
- Phase 1 must come first because every other phase depends on the observation bridge working correctly.
- Phase 2 before Phase 3 because you need to know what TCA patterns work before hardening edge cases.
- Phase 4 last because you should not tag releases or document changes until the implementation is stable.

**Research flags for phases:**
- Phase 1: Standard patterns (the implementation exists, this is testing/debugging). Unlikely to need additional research.
- Phase 2: Navigation may need deeper research -- the `NavigationStack.init(path:root:destination:)` extension is entirely guarded out on Android. Need to understand what skip-ui provides as a Compose equivalent.
- Phase 3: JNI thread safety and DispatchSemaphore behavior under contention may need investigation if issues surface during Phase 2.
- Phase 4: Upstream contribution process needs research into Skip and Point-Free PR conventions when the time comes.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies verified against official sources. Versions confirmed from Package.swift files and upstream docs. |
| Features | HIGH | Feature inventory based on direct codebase analysis. AndroidParityTests provide evidence for working features. |
| Architecture | HIGH | Record-replay pattern analyzed line-by-line from fork diffs. Data flow traced through all components. |
| Pitfalls | HIGH | Critical pitfalls derived from code analysis (infinite recomposition, onChange semantics). Moderate pitfalls from JNI/Compose best practices. |
| TCA 2.0 timeline | LOW | Sneak-peeked Feb 2026, no release date announced. "Very soon" from Stephen Celis could be months. |
| Swift 6.3 timeline | MEDIUM | Nightly snapshots available. Final release timing unclear but expected 2026. |

## Gaps to Address

- **Navigation on Android**: The `NavigationStack.init(path:root:destination:)` extension is fully guarded out on Android. Need to determine what skip-ui provides and whether TCA navigation patterns need adaptation.
- **`jniContext` thread attachment**: Need to verify whether `jniContext` in skip-bridge handles `AttachCurrentThread()` for non-main threads. Critical for TCA effects completing on background threads.
- **Compose disposal lifecycle**: Need to understand how `MutableStateBacking` JObject references are managed when Compose composables are disposed (navigation pop, view removal).
- **TestStore Android behavior**: `useMainSerialExecutor` is unavailable on Android. The `effectDidSubscribe` alternative in TestStore needs testing to confirm parity with iOS test semantics.
- **TCA 2.0 impact assessment**: When TCA 2.0 releases, assess which fork changes become unnecessary (Combine removal simplifies Android stack) and which need migration.

## Sources

- [Swift SDK for Android -- Getting Started (swift.org)](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html)
- [Announcing the Swift SDK for Android (swift.org)](https://www.swift.org/blog/nightly-swift-sdk-for-android/)
- [Skip Official SDK Announcement (skip.dev)](https://skip.dev/blog/official-swift-sdk-for-android/)
- [Skip Modes Documentation (skip.dev)](https://skip.dev/docs/modes/)
- [Skip Bridging Reference (skip.dev)](https://skip.dev/docs/bridging/)
- [Skip now fully open source (InfoQ)](https://www.infoq.com/news/2026/01/swift-skip-open-sourced/)
- [Point-Free 2025 Year-in-Review](https://www.pointfree.co/blog/posts/196-2025-year-in-review)
- [TCA 2.0 Sneak Peek (pointfree.co)](https://www.pointfree.co/blog/posts/200-the-point-free-way-tca-2-0-sneak-peek-a-giveaway-q-a-and-more)
- [skip-android-bridge repository (GitHub)](https://github.com/skiptools/skip-android-bridge)
- [OpenCombine (GitHub)](https://github.com/OpenCombine/OpenCombine)
- [swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890)
- [skip-model Documentation (skip.tools)](https://skip.tools/docs/modules/skip-model/)
- Project codebase: fork diffs, architecture docs, concern docs

---

*Research summary: 2026-02-20*
