# Swift Cross-Platform

Bridging [Point-Free's](https://www.pointfree.co) Swift ecosystem to Android via [Skip](https://skip.tools) Fuse mode — making TCA a viable way to build cross-platform mobile applications.

## The Problem

On iOS, SwiftUI wraps view body evaluation with `withObservationTracking`, firing a single recomposition per observation cycle. On Android via Skip Fuse mode, the generated JNI bridge functions evaluate view bodies **without** this wrapper. The only recomposition driver is `MutableStateBacking`'s integer counters, which increment on every `withMutation()` call. TCA's `@ObservableState` macro generates high-frequency UUID mutations on every state assignment, causing thousands of counter increments and an **infinite recomposition loop**.

## The Fix

A three-layer observation bridge across forked Skip and Point-Free packages:

1. **skip-android-bridge** — `ObservationRecording` records `access()` calls during body evaluation using thread-local storage, replays them inside `withObservationTracking`, and fires a single `triggerSingleUpdate()` on `onChange`
2. **skip-ui** — `ViewObservation` JNI hooks call `startRecording`/`stopAndObserve` around `Evaluate()`
3. **swift-composable-architecture** — `ObservationStateRegistrar` routes Android through `SkipAndroidBridge.Observation.ObservationRegistrar`, suppressing per-mutation counter increments when recording is active

## Repository Structure

```
forks/                          14 git submodules
├── skip-android-bridge         Skip fork: observation recording + JNI exports
├── skip-ui                     Skip fork: ViewObservation hooks in Evaluate()
├── swift-composable-architecture   TCA fork: ObservationStateRegistrar Android path
├── swift-perception            Observation backport fork
├── swift-navigation            Navigation fork
├── swift-sharing               Shared state fork
├── swift-dependencies          Dependency injection fork
├── swift-clocks                Clock abstractions fork
├── combine-schedulers          Combine scheduler fork
├── swift-custom-dump           Debug output fork
├── swift-snapshot-testing      Snapshot testing fork
├── swift-structured-queries    Type-safe SQL fork
├── GRDB.swift                  SQLite database fork
└── sqlite-data                 SQLite persistence fork

examples/                       Example projects
├── fuse-app/                   Full app using Fuse mode
├── fuse-library/               Reusable library for both platforms
├── lite-app/                   Lite mode app (not viable for TCA)
└── lite-library/               Lite mode library

docs/skip/                      Skip framework reference
.planning/                      Project planning (roadmap, requirements, research)
```

## Fork Strategy

All 12 Point-Free/GRDB forks track the `flote/service-app` branch. The 2 Skip forks track `dev/observation-tracking`. Changes are gated behind `#if os(Android)` / `#if SKIP_BRIDGE` to preserve iOS behavior and minimize upstream divergence.

| Fork | Upstream | Commits Ahead | Key Changes |
|------|----------|---------------|-------------|
| swift-composable-architecture | 1.23.1 | 38 | `ObservationStateRegistrar` Android path, `#if os(Android)` guards |
| swift-navigation | 2.6.0 | 27 | Android-compatible navigation APIs |
| swift-sharing | 2.7.4 | 25 | Shared state persistence on Android |
| sqlite-data | 1.5.1 | 16 | SQLite integration for Android |
| swift-clocks | 1.0.6 | 14 | Clock abstractions for Android |
| swift-perception | 2.0.9 | 13 | Observation bridging |
| skip-android-bridge | 0.6.1 | 4 | `ObservationRecording`, `BridgeObservationSupport.triggerSingleUpdate()` |
| swift-dependencies | 1.11.0 | 4 | Dependency resolution on Android |
| combine-schedulers | 1.1.0 | 4 | OpenCombine compatibility |
| swift-structured-queries | 0.30.0 | 4 | Query DSL for Android |
| swift-snapshot-testing | 1.18.9 | 3 | Test infrastructure |
| swift-custom-dump | 1.4.1 | 1 | Debug output |
| GRDB.swift | 7.9.0 | 1 | Database layer |
| skip-ui | 1.49.0 | — | `ViewObservation` JNI hooks |

## Technology Stack

| Technology | Purpose |
|------------|---------|
| [Skip Framework](https://skip.tools) 1.7+ | Cross-platform Swift-to-Android (Fuse mode) |
| Swift Android SDK 6.2+ | Native Swift compilation for Android via NDK |
| Native `libswiftObservation.so` | `withObservationTracking` on Android (ships with SDK) |
| [TCA](https://github.com/pointfreeco/swift-composable-architecture) 1.x | Application architecture |
| [OpenCombine](https://github.com/OpenCombine/OpenCombine) 0.14+ | Combine compatibility on Android (until TCA 2.0) |

**Not used:** swift-perception on Android (native Observation ships with SDK), Skip Lite mode for TCA (counter-based observation incompatible), app-level `Observing` wrappers (fix must be at bridge level).

## Roadmap

7 phases, 184 requirements. See [`.planning/ROADMAP.md`](.planning/ROADMAP.md) for details.

| Phase | Goal | Requirements |
|-------|------|--------------|
| 1. Observation Bridge | Record-replay pattern prevents infinite recomposition | 36 |
| 2. Foundation Libraries | CasePaths, IdentifiedCollections, CustomDump, IssueReporting | 23 |
| 3. TCA Core | Store, reducers, effects, dependency injection | 28 |
| 4. TCA State & Bindings | ObservableState, bindings, shared state persistence | 26 |
| 5. Navigation & Presentation | Stack, sheet, alert, confirmation dialog | 31 |
| 6. Database & Queries | StructuredQueries, GRDB/SQLiteData | 27 |
| 7. Integration Testing & Docs | End-to-end TCA app, fork documentation | 13 |

Phase 6 depends only on Phase 1 and can run in parallel with Phases 2–5.

## Known Issues

- `swiftThreadingFatal` stub required for `libswiftObservation.so` loading until Swift 6.3 ([swiftlang/swift#77890](https://github.com/swiftlang/swift/pull/77890))
- `NavigationStack.init(path:root:destination:)` is fully guarded out on Android — needs skip-ui Compose equivalent
- `jniContext` thread attachment for non-main threads needs verification for TCA effects

## Acknowledgements

- **Skip team** (Marc Prud'hommeaux, Dan Fabulich) — endorsed fork-first approach
- **Point-Free** (Stephen Celis) — supportive of Android effort
- **Joannis Orlandos** — prior TCA Android work
