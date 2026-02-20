# Swift Cross-Platform

## What This Is

A framework effort to bridge Point-Free's Swift ecosystem (TCA, swift-perception, swift-navigation, swift-sharing, swift-dependencies, GRDB, and more) to Android via the Skip framework. This repository documents, manages, and houses contributions across 14 forked submodules — making Swift + TCA a viable way to build modern cross-platform mobile applications.

## Core Value

Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- [x] 12 Point-Free/GRDB forks compile for Android via Skip Fuse mode (~149 commits across forks)
- [x] OpenCombine integration enables Combine-dependent packages on Android (combine-schedulers, swift-sharing)
- [x] `#if os(Android)` / `SKIP_BRIDGE` conditional compilation gates work correctly across all forks
- [x] Parity test targets (AndroidParityTests) established in key packages (TCA, swift-navigation, swift-sharing, swift-clocks, sqlite-data, swift-perception)
- [x] Skip documentation collected and committed (docs/skip/)
- [x] Codebase architecture mapped (.planning/codebase/)
- [x] fuse-app and fuse-library example projects created and building on both platforms

### Active

<!-- Current scope. Building toward these. -->

- [ ] **Fix Fuse-mode observation bridge** — wrap view body evaluation with `withObservationTracking` in skip-android-bridge/skip-ui so that onChange fires once per observation cycle (not once per mutation), eliminating the infinite recomposition loop
- [ ] **TCA 1.x runs on Android** — a generic TCA app (not just a specific app) renders correctly on Android with state changes propagating properly, navigation working, and no performance regressions
- [ ] **Stable fork releases** — tagged versions on jacobcxdev forks that downstream consumers can pin to via SPM
- [ ] **Fork change documentation** — FORKS.md tracking what changed in each fork, why, and candidates for upstream PRs
- [ ] **Android integration test coverage** — tests verifying observation bridge behavior, recomposition stability, and high-frequency mutation handling

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **TCA 2.0 support** — Stephen Celis says preview "very soon" but we target 1.x now; migration planned separately when 2.0 lands
- **Skip Lite mode observation fix** — Lite mode's counter-based observation is fundamentally incompatible with TCA; Fuse mode is the only viable Android path
- **Upstream PRs to Point-Free** — premature until our forks stabilize and TCA 2.0 plans are clearer; document candidates in FORKS.md
- **Upstream PRs to Skip** — wait until observation bridge fix is proven in our forks; Marc endorsed this approach
- **KMP interop** — this is a Swift-first effort; Kotlin Multiplatform integration is a different project
- **Production app development** — this repo produces framework-level tools, not end-user applications

## Context

### Technical Ecosystem

- **Skip Framework** (v1.7+): Compiles Swift natively for Android (Fuse mode) or transpiles to Kotlin (Lite mode). Maintained by Marc Prud'hommeaux and team at skip.tools.
- **Point-Free's Swift Ecosystem**: TCA (The Composable Architecture), swift-perception, swift-navigation, swift-sharing, swift-dependencies, swift-clocks, combine-schedulers, swift-custom-dump, swift-snapshot-testing, swift-case-paths, swift-structured-queries, GRDB.swift, sqlite-data.
- **Swift on Android**: Swift 6.2+ Android SDK provides native compilation via NDK toolchain. `libswiftObservation.so` ships with the SDK — native `withObservationTracking` works on Android.

### The Observation Bridge Problem

On iOS, SwiftUI internally wraps view body evaluation with `withObservationTracking { body() } onChange: { scheduleRerender() }` — this fires once per observation cycle, then auto-cancels and resubscribes on the next render.

On Android via Skip Fuse mode, the generated `Swift_composableBody` JNI function evaluates view bodies **without** this wrapper. The only recomposition driver is `MutableStateBacking`'s integer counters (from skip-model), which increment on every `withMutation()` call. TCA's `@ObservableState` macro generates high-frequency mutations (UUID-based `_$id` changes on every state assignment), causing thousands of counter increments and an infinite recomposition loop.

Skip already has the infrastructure for the fix: `Observation.swift` in skip-android-bridge implements a record-replay pattern with `ObservationRecording`, and `ViewObservation` in skip-ui provides JNI hooks (`startRecording`/`stopAndObserve`). The fix involves ensuring these hooks properly bridge `withObservationTracking`'s onChange to a single Compose MutableState increment per observation cycle.

### Existing Work (Feb 11-19, 2026)

**Phase 1 (Feb 11-13):** Initial Android porting — `#if !os(Android)` guards on SwiftUI code, SkipBridge/SkipAndroidBridge dependencies added, dependency URLs pointed to forks.

**Phase 2 (Feb 17-18):** Iterative un-guarding of SwiftUI integrations for Android parity using skip-fuse-ui as SwiftUI shim. Multiple revert/re-apply cycles as compilation issues were discovered. Parity tests added.

**Phase 3 (Feb 19):** Dependency URLs migrated from intermediate org to jacobcxdev. ObservationRegistrar bridge work in TCA.

**Phase 4 (Feb 20):** Repository reorganized into swift-crossplatform. Codebase mapped. fuse-app and fuse-library examples created. Deep analysis of observation bridge architecture in skip-android-bridge and skip-ui.

### Stakeholder Coordination

- **Skip team (Marc Prud'hommeaux, Dan Fabulich):** Endorsed fork-first approach. Marc: "I do think this will be the best first step." Recommended using SKIP_BRIDGE section in skip-ui's Package.swift for upstream path.
- **Point-Free (Stephen Celis):** Supportive of Android effort. Requested public GitHub discussion when ready. TCA 2.0 preview expected soon (no Combine dependency).
- **Joannis Orlandos:** Previously started TCA Android PR but deferred to TCA 2.0.

## Constraints

- **Tech Stack**: Swift 6.0+, Skip 1.7+, Android SDK/NDK via Swift Android SDK. All forks must remain SPM-compatible.
- **Compilation**: Fuse mode only for TCA apps (Lite mode observation is fundamentally incompatible). iOS must continue working — no regressions.
- **Dependencies**: Skip Lite layer (skip-model, skip-ui transpiled code) must remain free of compiled Swift dependencies per Marc's guidance.
- **Fork Strategy**: All forks on `flote/service-app` branch. Must track upstream divergence and minimize diff surface for eventual upstreaming.
- **Public Repository**: No confidential references. Private context in `.planning/local/` (gitignored).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Fuse mode only (no Lite) for TCA apps | Lite mode counter-based observation fundamentally incompatible with TCA mutation frequency | -- Pending |
| Fix at bridge level, not app level | App-level Observing wrapper was rejected; fix must be in skip-android-bridge/skip-ui for platform parity | -- Pending |
| Use native `withObservationTracking` (not swift-perception) | `libswiftObservation.so` ships with Android Swift SDK; no need for backport on Android | -- Pending |
| Fork-first, upstream later | Skip team endorsed this; prove the fix works before proposing upstream changes | -- Pending |
| Target TCA 1.x (not wait for 2.0) | Business urgency; 1.x is what we have now; migration to 2.0 planned separately | -- Pending |
| Monorepo with submodules | 14 forks need coordinated changes; submodules allow independent git histories while shared workspace | -- Pending |
| SKIP_BRIDGE env var for Android detection | Aligns with Skip ecosystem pattern (skip-foundation uses same); TARGET_OS_ANDROID is a compiler flag, not env var | ✓ Good |
| OpenCombine for Combine-dependent packages | Simple conditional import; avoids rewriting Combine-dependent code; will be unnecessary with TCA 2.0 | ✓ Good |

---
*Last updated: 2026-02-20 after project initialization*
