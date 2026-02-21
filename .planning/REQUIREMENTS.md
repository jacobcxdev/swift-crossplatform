# Requirements: Swift Cross-Platform

**Defined:** 2026-02-21
**Core Value:** Any TCA app built with Point-Free's tools must run correctly on both iOS and Android via Skip's Fuse mode, with identical observation semantics and no infinite recomposition loops.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Observation/Reactivity

- [ ] **OBS-01**: View body evaluation on Android is wrapped with `withObservationTracking`, firing `onChange` exactly once per observation cycle (not once per mutation)
- [ ] **OBS-02**: `willSet` calls are suppressed during observation recording — no per-mutation `MutableStateBacking` counter increments while `isEnabled` is true
- [ ] **OBS-03**: A single `MutableStateBacking.update(0)` JNI call triggers exactly one Compose recomposition per observation cycle
- [ ] **OBS-04**: Bridge initialization failure is detected and logged — if `ViewObservation.nativeEnable()` fails, a visible error is produced instead of silent fallback to broken counter path
- [ ] **OBS-05**: Nested view hierarchies observe correctly — parent and child views each maintain their own frame on the `ObservationRecording` stack
- [ ] **OBS-06**: ViewModifier bodies participate in observation tracking (not just View bodies)
- [ ] **OBS-07**: All Swift Observation APIs (`access(keyPath:)`, `withMutation(keyPath:_:)`, `withObservationTracking`, `ObservationRegistrar`) function correctly on Android in Fuse mode
- [ ] **OBS-08**: `@Observable` classes trigger correct view updates on Android when properties are read in view bodies and mutated externally

### TCA Core

- [ ] **TCA-01**: `Store` initializes correctly on Android with initial state and reducer
- [ ] **TCA-02**: Reducer composition and scoping (`Scope`, `ifLet`, `forEach`) work on Android
- [ ] **TCA-03**: Effects execute correctly — `merge`, `concatenate`, `run`, `cancel` operators all function on Android
- [ ] **TCA-04**: `@ObservableState` macro generates correct observation hooks on Android (no infinite recomposition)
- [ ] **TCA-05**: `BindingReducer` and `@BindingState` work correctly for two-way bindings on Android
- [ ] **TCA-06**: `ForEachStore`, `IfLetStore`, and `SwitchStore` view helpers render correctly on Android
- [ ] **TCA-07**: `DismissEffect` and presentation lifecycle work on Android
- [ ] **TCA-08**: `@Dependency` injection resolves correctly on Android, including `@DependencyClient` macro-generated clients
- [ ] **TCA-09**: `@Shared` state (including `.appStorage` and `.fileStorage`) works on Android
- [ ] **TCA-10**: `TestStore` runs on Android with a working alternative to `useMainSerialExecutor`

### Navigation

- [ ] **NAV-01**: `NavigationStack` with path-based routing renders and navigates correctly on Android
- [ ] **NAV-02**: `.sheet` presentation works on Android with TCA `@Presents` / `PresentationAction`
- [ ] **NAV-03**: `.alert` and `.confirmationDialog` render correctly on Android via TCA's `AlertState`/`ConfirmationDialogState`
- [ ] **NAV-04**: Navigation patterns are compatible with iOS 26+ APIs (excluding past deprecations)

### Testing & Developer Experience

- [ ] **TEST-01**: Integration tests verify the observation bridge prevents infinite recomposition on Android emulator
- [ ] **TEST-02**: Stress tests confirm stability under high-frequency TCA state mutations (>1000 mutations/second)
- [ ] **TEST-03**: A fuse-app example demonstrates a full TCA app (store, reducer, effects, navigation, persistence) running on both iOS and Android
- [ ] **TEST-04**: FORKS.md documents every fork: original upstream version, commits ahead, key changes, rationale, and upstream PR candidates

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Fork Releases

- **REL-01**: Tagged stable releases on all jacobcxdev forks with semantic versioning
- **REL-02**: Automated upstream tracking (GitHub Actions monitoring upstream releases)
- **REL-03**: CI pipeline running tests on both iOS simulator and Android emulator

### Upstream Contributions

- **UPS-01**: PR to skip-tools demonstrating observation bridge fix (gated behind SKIP_BRIDGE)
- **UPS-02**: GitHub Discussion on Point-Free org documenting Android support strategy
- **UPS-03**: PR to swift-composable-architecture for Android platform support

### TCA 2.0

- **TCA2-01**: Migration path from TCA 1.x forks to TCA 2.0 when released
- **TCA2-02**: Remove OpenCombine dependency (TCA 2.0 eliminates Combine)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Skip Lite mode TCA support | Counter-based observation fundamentally incompatible with TCA mutation frequency |
| App-level observation wrappers | Fix must be at bridge level (skip-android-bridge/skip-ui), not in TCA or app code |
| KMP interop | This is a Swift-first effort; Kotlin Multiplatform is a separate ecosystem |
| Production applications | This repo produces framework tools, not end-user apps |
| UIKit navigation patterns | SwiftUI-only; UIKit bridging is not in scope |
| Animation parity | Focus on correctness first; animation fidelity is a polish concern |
| Swift Perception backport on Android | Native `libswiftObservation.so` ships with Android Swift SDK; no backport needed |
| Automated fork rebasing | Manual upstream sync is sufficient for v1; automation is v2 |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| OBS-01 | TBD | Pending |
| OBS-02 | TBD | Pending |
| OBS-03 | TBD | Pending |
| OBS-04 | TBD | Pending |
| OBS-05 | TBD | Pending |
| OBS-06 | TBD | Pending |
| OBS-07 | TBD | Pending |
| OBS-08 | TBD | Pending |
| TCA-01 | TBD | Pending |
| TCA-02 | TBD | Pending |
| TCA-03 | TBD | Pending |
| TCA-04 | TBD | Pending |
| TCA-05 | TBD | Pending |
| TCA-06 | TBD | Pending |
| TCA-07 | TBD | Pending |
| TCA-08 | TBD | Pending |
| TCA-09 | TBD | Pending |
| TCA-10 | TBD | Pending |
| NAV-01 | TBD | Pending |
| NAV-02 | TBD | Pending |
| NAV-03 | TBD | Pending |
| NAV-04 | TBD | Pending |
| TEST-01 | TBD | Pending |
| TEST-02 | TBD | Pending |
| TEST-03 | TBD | Pending |
| TEST-04 | TBD | Pending |

**Coverage:**
- v1 requirements: 26 total
- Mapped to phases: 0
- Unmapped: 26 (awaiting roadmap)

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 after initial definition*
