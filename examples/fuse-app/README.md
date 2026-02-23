# Fuse App: Cross-Platform TCA Showcase

A comprehensive reference application demonstrating [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) running on both iOS and Android via [Skip](https://skip.tools) Fuse mode. Built with 17 forked Point-Free and Skip dependencies to prove end-to-end cross-platform viability.

## Evaluator Overview

### What Works on Both Platforms

| Category | APIs Demonstrated | Status |
|----------|-------------------|--------|
| **TCA Core** | Store, @Reducer, @ObservableState, Effect.run, Effect.none | Fully working |
| **Composition** | Scope, CombineReducers, .forEach, .ifLet, parent/child | Fully working |
| **Bindings** | BindableAction, BindingReducer, @Bindable store, $store.sending | Fully working |
| **Navigation** | NavigationStack, StackState/StackAction, push/pop | Fully working |
| **Presentation** | .sheet, .alert, .confirmationDialog, @Presents, PresentationAction | Fully working |
| **Dependencies** | @Dependency, DependencyKey, @DependencyClient, withDependencies | Fully working |
| **Shared State** | @Shared(.appStorage), @Shared(.inMemory), $shared.withLock | Fully working |
| **Database** | @Table, DatabaseMigrator, CRUD transactions, DatabaseQueue | Fully working |
| **Testing** | TestStore, send/receive, exhaustivity, TestClock | macOS only |

### Known Limitations

| ID | Issue | Impact | Workaround |
|----|-------|--------|------------|
| B2 | @Shared(.fileStorage) subscription notifications are no-op on Android | External file changes invisible; in-app writes work fine | Write-then-read pattern only |
| B3 | @Shared(.appStorage) subscription notifications are no-op on Android | Same as B2 for UserDefaults-backed storage | In-app mutations work; no cross-process sync |
| B5 | TestStore non-determinism on Android | Tests run macOS-only via FuseAppIntegrationTests target | Dedicated test target without skipstone plugin |
| P1-7 | @Shared(.appStorage) with [String] type crashes | Array-typed appStorage unavailable | Use scalar types (String, Bool, Int, Double) |
| P8 | Perception bypass on Android: `PerceptionRegistrar` delegates to native `ObservationRegistrar`, bypassing the bridge's `recordAccess` hooks | Raw `@Perceptible` views (without TCA) will not trigger Compose recomposition. Safe for all TCA usage (TCA uses `ObservationStateRegistrar` which routes through the bridge directly) | Only affects code using `swift-perception`'s `@Perceptible` macro directly for view driving outside TCA. Use `@Observable` or TCA's `@ObservableState` instead |

### Platform Differences

- **Observation pipeline**: iOS uses native SwiftUI observation; Android uses the custom observation bridge (skip-android-bridge) with JNI record-replay semantics. Both produce identical state update behavior.
- **Navigation rendering**: NavigationStack, sheets, and alerts use native UIKit on iOS and Compose navigation on Android. Data flow is identical; visual rendering follows platform conventions.
- **Database**: SQLite is bundled via GRDB's amalgamation on Android (not from system sysroot). All CRUD operations work identically.
- **Macros**: @Reducer, @ObservableState, @Table, @DependencyClient expand at compile time on the host. Only expanded code runs on Android.

### Adoption Decision Criteria

**Use this stack when:**
- You need shared business logic (reducers, effects, dependencies) across iOS and Android
- Your app follows unidirectional data flow patterns
- You want type-safe navigation and presentation
- You need testable state management with TestStore

**Consider alternatives when:**
- You need real-time cross-process @Shared subscription notifications on Android
- Your app is primarily UI-heavy with minimal business logic
- You need Lite mode (counter-based observation is incompatible with TCA)

## Developer Guide

### Project Structure

All features live as files within the single `FuseApp` target (avoids Skip/Gradle module explosion):

```
Sources/FuseApp/
  FuseApp.swift          -- App entry point with Store and bridge annotations
  AppFeature.swift       -- Tab-based root coordinator composing all features
  CounterFeature.swift   -- Effects, bindings, @ViewAction, @Dependency
  TodosFeature.swift     -- IdentifiedArray, alert, confirmationDialog, filter
  ContactsFeature.swift  -- NavigationStack, sheet, @Reducer enum, delegate actions
  DatabaseFeature.swift  -- @Table, DatabaseMigrator, CRUD, DatabaseQueue
  SettingsFeature.swift  -- @Shared persistence, $shared.withLock mutations
  SharedModels.swift     -- Domain models, SharedKey extensions, dependency clients
```

### Pattern Reference: Which File Demonstrates What

**CounterFeature.swift** -- Start here for TCA basics:
- `@Reducer struct` with `@ObservableState`
- `@ViewAction(for:)` with nested `View` action enum
- `Effect.run` with `@Dependency(\.continuousClock)` for async work
- `.onChange(of:)` for derived state tracking

**TodosFeature.swift** -- Collection management:
- `IdentifiedArrayOf<Todo>` with add/remove/toggle
- `AlertState` for delete confirmation with `.destructive` role
- `ConfirmationDialogState` for sort options
- `@Dependency(\.uuid)` and `@Dependency(\.date)` for deterministic testing

**ContactsFeature.swift** -- Full navigation showcase:
- `NavigationStack(path:root:destination:)` with `StackState`/`StackAction`
- `@Reducer enum Path` for type-safe destinations
- `switch store.case { }` for enum store switching
- `@Reducer enum Destination` with `@ReducerCaseEphemeral` for alerts
- `.sheet(item:)` for modal presentation
- `@Dependency(\.dismiss)` for programmatic child dismissal
- Delegate actions for child-to-parent communication

**DatabaseFeature.swift** -- SQLite database:
- `@Table struct Note` with `@Column(primaryKey:)`
- `DatabaseMigrator` with versioned migrations
- `DatabaseQueue` read/write transactions via GRDB
- Custom `DependencyKey` for database injection

**SettingsFeature.swift** -- Shared persistence:
- `@Shared(.appStorage("key"))` for UserDefaults-backed state
- `@Shared(.inMemory("key"))` for session-scoped state
- `$shared.withLock { $0 = newValue }` for thread-safe mutations
- `@ObservationStateIgnored` for debug-only fields
- `SharedKey` extensions with default values

### Copy-This-Pattern Guide

**Basic feature reducer:**
```swift
@Reducer
struct MyFeature {
    @ObservableState
    struct State: Equatable { var value = 0 }
    enum Action { case increment }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment: state.value += 1; return .none
            }
        }
    }
}
```

**Shared state mutation (direct setter unavailable):**
```swift
// In reducer:
state.$userName.withLock { $0 = "New Name" }
// In test assertion:
$0.$userName.withLock { $0 = "New Name" }
```

**Navigation with @Reducer enum:**
```swift
@Reducer enum Path { case detail(DetailFeature) }
// Must add Equatable extension for generated State:
extension MyFeature.Path.State: Equatable {}
```

### Running on Both Platforms

```bash
# macOS build and test
cd examples/fuse-app
swift build                    # Build app
swift test                     # Run all tests (integration + SkipTest)
swift test --filter FuseAppIntegrationTests  # Integration tests only

# Android build (requires Skip toolchain + Android SDK)
skip android build --configuration debug --arch aarch64

# Android test
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 skip android test

# Environment verification
skip doctor --native           # Check Skip + SDK setup
```

### Android-Specific Gotchas

1. **No `$store.scope` binding syntax on Android** -- use `store.scope(state:action:)` instead
2. **`@Shared(.appStorage)` with `[String]` type crashes** -- use scalar types only
3. **File/appStorage subscription notifications don't fire on Android** -- write-then-read works
4. **All fork changes gated behind `#if os(Android)` or `#if SKIP_BRIDGE`** -- no iOS regressions
5. **Macros expand host-side** -- only the expanded Swift code crosses to Android
6. **`swiftThreadingFatal` stub required** until Swift 6.3 ships upstream fix

## Building

This project is both a stand-alone Swift Package Manager module,
as well as an Xcode project that builds and translates the project
into a Kotlin Gradle project for Android using the skipstone plugin.

Building the module requires that Skip be installed using
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.

## License

This software is licensed under the [GNU General Public License v3.0 or later](https://spdx.org/licenses/GPL-3.0-or-later.html).
