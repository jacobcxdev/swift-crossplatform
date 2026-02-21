# Phase 1: Observation Bridge - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Swift Observation semantics work correctly on Android via the record-replay bridge pattern. View body evaluation triggers exactly one Compose recomposition per observation cycle (not one per mutation). All 14 fork packages compile for Android via Skip Fuse mode. This phase delivers the foundational observation infrastructure that every subsequent phase depends on.

**In scope:** ObservationRecording record-replay, JNI exports, bridge registrar changes, PerceptionRegistrar passthrough, SPM configuration for all forks, Android instrumented tests, diagnostics API.

**Out of scope:** TCA Store/reducer/effect behavior (Phase 3), navigation patterns (Phase 5), database observation (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Error & Fallback Behavior

- **Bridge initialization failure is fatal.** If `ViewObservation.nativeEnable()` fails or JNI exports don't resolve, `fatalError()` with a clear message. The bridge is load-bearing infrastructure — silent degradation is worse than crashing.
- **Runtime JNI failures are fatal per call.** If `nativeStartRecording()` or `nativeStopAndObserve()` fails mid-session, `fatalError()` immediately. Any JNI failure is a programming error that must surface during development.
- **Opt-in diagnostics API.** `ObservationBridge.diagnosticsEnabled = true` logs every record/replay cycle with timing. Mechanism lives in skip-android-bridge (internal notification hooks). A pretty-printing diagnostic helper in the example project consumes the hooks.

### Threading & Reentrancy

- **Multi-thread TLS isolation.** Each thread gets its own TLS recording stack. Not restricted to main thread. Handles edge cases where Compose's recomposition scheduler or background mutations interact with recording.
- **Independent frame per ViewModifier.** Each `ViewModifier.body()` pushes/pops its own frame on the TLS stack, enabling independent tracking per modifier. More granular than sharing the parent's frame.
- **Natural stack reentrancy.** Reentrant recordings (e.g., computed property triggers nested view evaluation) are handled naturally by the TLS frame stack — push new frame, inner completes and pops, outer continues. No special handling or assertions needed.
- **onChange dispatches to main immediately.** When `withObservationTracking`'s onChange fires from an arbitrary thread, dispatch to main via `MainActor`/`DispatchQueue.main.async` to update `MutableState`. Simple, deterministic, small latency for off-main mutations.

### Perception vs Native Boundary

- **Disable counter path when bridge is active.** When `nativeEnable()` has been called (`isEnabled=true`), the bridge registrar's `willSet`/`didSet` skip `MutableStateBacking` JNI calls entirely. Native Observation handles everything. Counter path only fires if bridge is disabled (fallback for non-Fuse or non-observation-aware Skip users). This prevents double-updates.
- **Counter path gated on nativeEnable().** Apps that never call `nativeEnable()` retain counter-based behavior. Zero impact on existing Skip users. Only observation-bridge-aware apps opt in.
- **PerceptionRegistrar is a thin passthrough on Android.** `PerceptionRegistrar` delegates 1:1 to native `ObservationRegistrar`. `withPerceptionTracking` calls `withObservationTracking`. Maintains full API compatibility — code using Perception works unchanged with zero overhead.

### SPM Configuration Strategy

- **Hybrid pattern.** Skip forks (skip-android-bridge, skip-ui) use `Context.environment["SKIP_BRIDGE"]` conditionals, matching upstream's existing pattern. These changes are directly PR-able to skip-tools. Point-Free forks use simple `#if os(Android)` conditionals — pragmatic, and TCA's upstream strategy differs from Skip's anyway.
- **All 14 forks must compile for Android.** Phase 1 validates that every fork package resolves and compiles for Android, not just the ones being modified. Catches dependency graph issues early before Phases 2-6 assume compilation works.

### Kotlin-Side Investigation

- **Research the Kotlin rendering path in Phase 1.** The Kotlin `@Composable` function that calls `Swift_composableBody` has not been examined yet. Phase 1 planning must include a research task to trace this path. This determines whether the fix is Swift-only or requires Kotlin changes too.

### swiftThreadingFatal Stub

- **Version-gated removal.** Implement the `swiftThreadingFatal()` symbol export with a compile-time check: `#if swift(<6.3)` provide stub, `#else` remove it. Automatically cleans up when Swift 6.3 ships the upstream fix (swiftlang/swift#77890). Self-documenting.

### Testing Strategy

- **Full Android instrumented tests.** Write tests that run on Android emulator via `skip test`. Validate observation cycles end-to-end including JNI calls and Compose recomposition counts. Not just macOS unit tests.
- **Extend existing tests with bridge-specific cases.** Add new test cases to the existing fuse-library test targets that exercise the record-replay mechanism: nested views, modifier tracking, multi-property coalescing. Keep existing tests as regression suite.

</decisions>

<specifics>
## Specific Ideas

- The working observation pattern already exists in `Sources/ServiceApp/Observing.swift.bak` — it wraps body evaluation with `withPerceptionTracking` + `@State` token. This pattern needs to be elevated to the bridge level (skip-android-bridge/skip-ui), not kept in app code.
- The `SKIP_BRIDGE` conditional in skip-ui's `Package.swift` (lines 20-30) is the exact upstream integration point for Fuse-mode-only dependencies.
- Skip maintainers (Marc Prud'hommeaux, Dan Fabulich) endorsed the fork approach in Slack (2026-02-19). Coordinate with them for upstream strategy.
- The bridge registrar in skip-android-bridge currently fires BOTH native Observation AND MutableStateBacking counters. The fix disables the counter side when `isEnabled=true`, not removes it — keeping backward compatibility for non-observation-aware Skip apps.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-observation-bridge*
*Context gathered: 2026-02-21*
