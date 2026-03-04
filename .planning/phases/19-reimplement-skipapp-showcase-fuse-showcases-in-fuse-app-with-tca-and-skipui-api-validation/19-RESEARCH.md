# Phase 19: Reimplement skipapp-showcase-fuse showcases in fuse-app with TCA and SkipUI API validation - Research

**Researched:** 2026-03-04
**Domain:** TCA state management + SkipUI API surface validation
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Port **all ~80 playgrounds** from skipapp-showcase-fuse -- match upstream exactly (actual count: 84 active playgrounds)
- Platform-specific playgrounds (Map, Lottie, VideoPlayer, Keychain, Haptic, Compose, DocumentPicker, Pasteboard, ShareLink, WebView) get **stub implementations** with a "Not yet ported" placeholder message
- **Remove completely**: ForEachNamespaceSetting, PeerSurvivalSetting, IdentityComponents, ScenarioEngineSetting, and all associated tests/scenarios. Phase 18.1 is verified
- **Two tabs**: Showcase + Control
- Showcase tab uses a **flat searchable list** (matching upstream's `PlaygroundNavigationView` layout) with alphabetical ordering
- Navigation is **TCA NavigationStack** -- full path-driven navigation via `StackState<ShowcasePath.State>` / `StackAction` / `.forEach`
- **ScenarioEngine and debug toolbar infrastructure stay as-is**
- **On-demand scenarios only** -- write ScenarioEngine scenarios when something is found broken during manual testing
- **Delete all existing scenarios** (ForEachNS, peer survival) -- clean slate
- Broken playgrounds tracked via **UAT document**
- File layout: **one file per playground** (matching upstream), all in Sources/FuseApp/
- Reducer composition: **scoped from root** via navigation StackState

### Claude's Discretion
- Per-playground decision: faithful port vs TCA-enhanced content
- Per-playground decision: full @Reducer vs plain View (based on interactivity)
- Per-playground decision: @ViewAction vs direct store.send
- Per-playground decision: whether to write TestStore unit tests
- File organisation within Sources/FuseApp/ (though one-file-per-playground is the constraint)
- Exact playground grouping within the alphabetical list (if any visual sectioning is helpful)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

## Summary

Phase 19 replaces the Phase 18.1 test harness (ForEachNS/PeerSurvival/EngineTest tabs) with a full SkipUI API validation surface by porting all 84 playgrounds from `skipapp-showcase-fuse` into `fuse-app`, wrapped in TCA architecture. The upstream showcase uses a `PlaygroundType` CaseIterable enum with a searchable `NavigationStack` list -- this translates directly to a TCA `StackState<ShowcasePath.State>` with `.forEach` navigation composition.

The work is primarily mechanical: each playground file from upstream becomes a file in `Sources/FuseApp/`, with interactive playgrounds gaining `@Reducer` wrappers and purely visual ones remaining as plain Views. The root `TestHarnessFeature` reducer is restructured from 4 tabs (ForEachNS, Peer, Engine, Control) to 2 tabs (Showcase, Control), with the showcase tab housing the TCA NavigationStack. The 84-destination NavigationStack is itself a valuable stress test of the NAV requirements on Android.

**Primary recommendation:** Execute in batches of ~15-20 playgrounds per plan, grouped by complexity (simple visual playgrounds first, then interactive ones, then platform-stub ones). Infrastructure changes (TestHarnessFeature restructuring, cleanup of Phase 18.1 files) should be a separate initial plan.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ComposableArchitecture | Fork (dev/swift-crossplatform) | State management, navigation, reducer composition | Already in fuse-app; `.forEach` on StackState is the established navigation pattern |
| SkipFuse | Fork | Cross-platform SwiftUI bridge | Already in fuse-app; provides SwiftUI compatibility layer on Android |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SkipFuse (SwiftUI) | Fork | UI framework | All playground views use SwiftUI APIs |
| Observation | stdlib | @Observable classes | Some playgrounds use @Observable (e.g., ObservablePlayground, StatePlayground) |

### Alternatives Considered
None -- the stack is fixed by project architecture. No new dependencies needed.

## Architecture Patterns

### Recommended Project Structure
```
examples/fuse-app/Sources/FuseApp/
├── FuseApp.swift                    # App entry point (existing, minor changes)
├── TestHarnessFeature.swift         # Root reducer: Showcase + Control tabs
├── ShowcaseFeature.swift            # Showcase tab: NavigationStack + searchable list
├── ControlPanelView.swift           # Control tab (existing, updated for new tabs)
├── ScenarioEngine.swift             # Engine infrastructure (existing, kept as-is)
├── AccessibilityPlayground.swift    # Individual playground files
├── AlertPlayground.swift
├── ...                              # ~84 playground files total
├── StatePlaygroundModel.swift       # Supporting model files (from upstream)
├── PlatformHelper.swift             # Platform detection helpers (from upstream)
└── Resources/                       # Existing resources
```

### Pattern 1: TCA NavigationStack with Path-Driven Navigation
**What:** Root showcase reducer uses `StackState<ShowcasePath.State>` with a `@Reducer(state: .equatable) enum ShowcasePath` containing one case per interactive playground (or a common wrapper for plain views).
**When to use:** This is the single navigation pattern for the entire showcase tab.
**Example:**
```swift
@Reducer
struct ShowcaseFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<ShowcasePath.State>()
        var searchText: String = ""
    }

    @CasePathable
    enum Action {
        case path(StackActionOf<ShowcasePath>)
        case searchTextChanged(String)
        case playgroundTapped(PlaygroundType)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .playgroundTapped(let type):
                state.path.append(ShowcasePath.State(type))
                return .none
            case .searchTextChanged(let text):
                state.searchText = text
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```

### Pattern 2: Plain View Playground (No Reducer)
**What:** Purely visual playgrounds (Divider, Spacer, Border, Shadow, etc.) with no interactive state.
**When to use:** Playgrounds that only display static UI elements.
**Example:**
```swift
// DividerPlayground.swift -- no reducer needed, used as-is from upstream
struct DividerPlayground: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ... static content
            }
        }
    }
}
```

### Pattern 3: Reducer-Backed Playground (Interactive)
**What:** Playgrounds with state (counters, toggles, text fields) get a `@Reducer` wrapping.
**When to use:** Playgrounds that manage state via `@State` in upstream become `@ObservableState` in TCA.
**Example:**
```swift
@Reducer
struct ButtonPlaygroundFeature {
    @ObservableState
    struct State: Equatable {
        var tapCount: Int = 0
    }

    @CasePathable
    enum Action {
        case tapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .tapped:
                state.tapCount += 1
                return .none
            }
        }
    }
}
```

### Pattern 4: Platform Stub Playground
**What:** Playgrounds requiring platform-specific APIs (MapKit, AVKit, Keychain, etc.) show a placeholder.
**When to use:** The 10 identified platform-specific playgrounds.
**Example:**
```swift
struct MapPlayground: View {
    var body: some View {
        ContentUnavailableView(
            "Not Yet Ported",
            systemImage: "map",
            description: Text("Map playground requires platform-specific APIs.")
        )
    }
}
```

### Pattern 5: ShowcasePath Enum for Navigation Destinations
**What:** A `@Reducer enum` where each case corresponds to a playground type. Plain view playgrounds share a single `.playground(PlaygroundType)` case; interactive ones with reducers get dedicated cases.
**When to use:** This is the single pattern for navigation destinations.
**Example:**
```swift
@Reducer(state: .equatable)
enum ShowcasePath {
    // Interactive playgrounds with reducers
    case button(ButtonPlaygroundFeature)
    case alert(AlertPlaygroundFeature)
    // ... other interactive playgrounds

    // Plain view playgrounds (no reducer)
    case plainPlayground(PlainPlaygroundFeature)
}
```

### Anti-Patterns to Avoid
- **Over-TCA-ifying visual playgrounds:** Divider, Spacer, Border, etc. have no state to manage. Wrapping them in a reducer adds ceremony with zero benefit. Keep them as plain Views.
- **Duplicating upstream code instead of referencing it:** The showcase files are in the same repo. Copy the file content but adapt imports (use `SkipFuse` not `SwiftUI` directly where needed).
- **Breaking PlaygroundSourceLink URLs:** The upstream `PlaygroundSourceLink` references `source.skip.tools/skipapp-showcase-fuse`. For fuse-app, either remove these toolbar items or point them to the fuse-app source.
- **Using `@State` in TCA-wrapped playgrounds:** TCA uses `@ObservableState` on the reducer's State struct, not SwiftUI's `@State`. Any playground state that gets TCA-ified must move from `@State var x` to `state.x` on the reducer.
- **Putting all 84 playground reducers in ShowcasePath:** Most playgrounds are plain views. Only interactive ones (estimated 25-30) need their own reducer case. Plain ones can share a common case that simply renders the view by `PlaygroundType`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Navigation path management | Manual array tracking | `StackState<ShowcasePath.State>` + `.forEach` | TCA's built-in stack navigation handles identity, deallocation, scoping |
| Search filtering | Custom filter logic | `PlaygroundType.allCases.filter { ... }` pattern from upstream | Already battle-tested, simple string prefix matching |
| Debug toolbar | New debug UI | Existing `DebugButton` + overlay from TestHarnessView | Already works, proven on both platforms |
| Scenario infrastructure | New test automation | Existing `ScenarioEngine` + `ScenarioRegistry` | Full checkpoint-based automation, stays as-is |

**Key insight:** The upstream showcase already has well-structured navigation and search. The TCA wrapping adds observation bridge validation but should not reinvent the UI structure.

## Common Pitfalls

### Pitfall 1: NavigationStack Destination Registration Explosion
**What goes wrong:** With 84 destinations, a naive `.navigationDestination(for:)` per type creates excessive registrations.
**Why it happens:** TCA's `NavigationStack(path:)` with `.navigationDestination(store:)` scopes by StackState element.
**How to avoid:** Use a single `.forEach(\.path, action: \.path)` on the reducer, and a single `switch store.case` in the navigation destination closure. TCA handles the routing via `ShowcasePath`.
**Warning signs:** Multiple `navigationDestination` calls in the view, or manual path array management.

### Pitfall 2: @State vs @ObservableState Confusion
**What goes wrong:** Copying upstream playground code verbatim includes `@State var tapCount = 0` which conflicts with TCA's observation model.
**Why it happens:** Upstream playgrounds use SwiftUI's native `@State`. TCA wraps state in `@ObservableState` on the reducer.
**How to avoid:** For TCA-ified playgrounds, move all `@State` to the reducer's State struct. For plain view playgrounds kept without a reducer, `@State` is fine.
**Warning signs:** Playground has both `@State` and `store.send()` calls -- pick one pattern.

### Pitfall 3: Logger Name Collision
**What goes wrong:** Both fuse-app and upstream showcase define a top-level `logger` constant.
**Why it happens:** `ShowcaseFuseApp.swift` defines `let logger = Logger(...)` and `FuseApp.swift` also defines one.
**How to avoid:** fuse-app already has its own `logger`. Playgrounds that reference `logger` (16 of them use it) should use fuse-app's logger. No name collision since these are separate compilation units.
**Warning signs:** Compiler errors about ambiguous `logger` references.

### Pitfall 4: PlaygroundSourceLink and Constants Dependencies
**What goes wrong:** Upstream playgrounds use `PlaygroundSourceLink(file:)` in toolbar items, which depends on `Constants.swift` URL strings pointing to `source.skip.tools/skipapp-showcase-fuse`.
**Why it happens:** These are upstream-specific helpers.
**How to avoid:** Either remove the `PlaygroundSourceLink` toolbar items entirely, or create a fuse-app version pointing to the fuse-app repo. Simplest: remove them since they're not relevant to API validation.
**Warning signs:** Missing `PlaygroundSourceLink` or `showcaseSourceURLString` compilation errors.

### Pitfall 5: Platform-Specific Imports
**What goes wrong:** Some playgrounds import platform-specific modules (`MapKit`, `AVKit`, `CoreHaptics`).
**Why it happens:** The 10 identified platform-specific playgrounds use native APIs.
**How to avoid:** Stub these playgrounds entirely. Don't conditionally import -- just replace with `ContentUnavailableView` placeholder.
**Warning signs:** Import errors on Android for `MapKit`, `AVKit`, etc.

### Pitfall 6: @Observable vs @ObservableState Model Types
**What goes wrong:** `StatePlayground` uses `@Observable class TapCountObservable` and `StatePlaygroundModel.swift`. These are plain `@Observable` classes, not TCA `@ObservableState`.
**Why it happens:** Upstream tests SwiftUI's native observation. In fuse-app context, these exercise the bridge observation on Android.
**How to avoid:** Keep the `@Observable` model types as-is (they test the observation bridge). The playground view wrapping them can be a plain View (no TCA reducer) since the purpose is validating `@Observable` specifically.
**Warning signs:** Trying to put `@Observable` classes into TCA's `@ObservableState` -- they are different mechanisms.

### Pitfall 7: Nested View Types in Upstream Playgrounds
**What goes wrong:** Many playgrounds define helper views nested or alongside the main view (e.g., `SheetContentView`, `PathElementView`, `AlertCancelButton`). These must be included in the ported file.
**Why it happens:** Upstream keeps everything in one file per playground.
**How to avoid:** Copy the full file content including helper views. The one-file-per-playground constraint aligns with upstream.
**Warning signs:** Missing helper types compilation errors.

## Code Examples

### Root TestHarnessFeature Restructured (2 tabs)
```swift
// TestHarnessFeature.swift -- restructured from 4 tabs to 2
@Reducer
struct TestHarnessFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .showcase
        var showcase = ShowcaseFeature.State()
        // ScenarioEngine state stays
        var pendingUICommand: UICommand? = nil
        var selectedScenarioIDs: Set<String> = []
        var runningScenarioID: String? = nil
        // ... debug toolbar state unchanged

        enum Tab: String, Equatable, CaseIterable {
            case showcase, control
        }
    }

    @CasePathable
    enum Action {
        case tabSelected(State.Tab)
        case showcase(ShowcaseFeature.Action)
        // ScenarioEngine actions stay
        case resetAll
        // ... debug actions unchanged
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.showcase, action: \.showcase) {
            ShowcaseFeature()
        }
        Reduce { state, action in
            // ... tab switching, scenario management, debug controls
        }
    }
}
```

### ShowcaseFeature with NavigationStack
```swift
@Reducer
struct ShowcaseFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<ShowcasePath.State>()
        var searchText: String = ""

        var filteredPlaygrounds: [PlaygroundType] {
            let prefix = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prefix.isEmpty else { return PlaygroundType.allCases }
            return PlaygroundType.allCases.filter { playground in
                let words = playground.title.split(separator: " ")
                return words.contains { $0.lowercased().starts(with: prefix) }
            }
        }
    }

    @CasePathable
    enum Action {
        case path(StackActionOf<ShowcasePath>)
        case searchTextChanged(String)
        case playgroundTapped(PlaygroundType)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .playgroundTapped(let type):
                state.path.append(type.initialPathState)
                return .none
            case .searchTextChanged(let text):
                state.searchText = text
                return .none
            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
```

### PlaygroundType Enum (Matching Upstream)
```swift
enum PlaygroundType: String, CaseIterable, Identifiable {
    case accessibility, alert, animation, background, blendMode, blur, border, button
    case color, colorEffects, colorScheme, compose, confirmationDialog
    case datePicker, disclosureGroup, divider, documentPicker
    case environment
    case focusState, form, frame
    case gesture, geometryReader, gradient, graphics, grid
    case hapticFeedback
    case icon, image
    case keyboard, keychain
    case label, lineSpacing, link, list, localization, lottie
    case map, mask, minimumScaleFactor, menu, modifier
    case navigationStack, notification
    case observable, offsetPosition, onSubmit, overlay
    case pasteboard, picker, preference, progressView
    case redacted
    case safeArea, scenePhase, scrollView, searchable, secureField, shadow, shape, shareLink, sheet, slider, spacer, sql, stack, state, stepper, storage, symbol
    case tabView, text, textEditor, textField, timer, toggle, toolbar, tracking, transform, transition
    case videoPlayer, viewThatFits
    case webView
    case zIndex

    var id: String { rawValue }

    var title: String {
        // Match upstream titles exactly
        switch self {
        case .accessibility: "Accessibility"
        // ... (match upstream PlaygroundType.title exactly)
        }
    }
}
```

## Playground Classification

### Platform-Specific (Stub with placeholder) -- 10 playgrounds
| Playground | Platform Dependency | Stub Reason |
|-----------|-------------------|-------------|
| Compose | Android-only ComposeView | Uses `#if SKIP` Kotlin code |
| DocumentPicker | UIDocumentPickerViewController | iOS-only API |
| HapticFeedback | CoreHaptics / UIFeedbackGenerator | iOS-only API |
| Keychain | Security framework | iOS-only KeychainAccess |
| Lottie | Lottie framework dependency | External dependency |
| Map | MapKit | iOS MapKit / Android Google Maps |
| Pasteboard | UIPasteboard | Platform-specific clipboard |
| ShareLink | ShareLink (limited Android) | Platform differences |
| VideoPlayer | AVKit / AVFoundation | iOS-only media player |
| WebView | WKWebView / Android WebView | Platform-specific webview |

### Purely Visual (Plain View, no reducer) -- ~30 playgrounds
Background, BlendMode, Blur, Border, Color, ColorEffects, ColorScheme, Divider, Frame, Gradient, Graphics, Icon, Image, Label, LineSpacing, Link, Mask, MinimumScaleFactor, Modifier, OffsetPosition, Overlay, Redacted, SafeArea, Shadow, Shape, Spacer, Stack, Symbol, Transform, ZIndex

### Interactive (Needs @Reducer or uses @State) -- ~30 playgrounds
Accessibility, Alert, Animation, Button, ConfirmationDialog, DatePicker, DisclosureGroup, Environment, FocusState, Form, Gesture, GeometryReader, Grid, Keyboard, List, Localization, Menu, NavigationStack, Notification, Observable, OnSubmit, Picker, Preference, ProgressView, ScenePhase, ScrollView, Searchable, SecureField, Sheet, Slider, SQL, State, Stepper, Storage, TabView, Text, TextEditor, TextField, Timer, Toggle, Toolbar, Tracking, Transition, ViewThatFits

### Files to Remove (Phase 18.1 cleanup)
| File | Reason |
|------|--------|
| ForEachNamespaceSetting.swift | Phase 18.1 complete |
| PeerSurvivalSetting.swift | Phase 18.1 complete |
| IdentityComponents.swift | Phase 18.1 complete |
| ScenarioEngineSetting.swift | Phase 18.1 complete |
| IdentityFeatureTests.swift | Phase 18.1 complete |
| TabBindingTests.swift | Phase 18.1 complete (if only for identity) |

### Files to Keep
| File | Reason |
|------|--------|
| ScenarioEngine.swift | On-demand scenario infrastructure |
| ControlPanelView.swift | Updated for 2-tab structure |
| FuseApp.swift | App entry point (minor updates) |
| TestHarnessFeature.swift | Root reducer (major restructuring) |
| FuseAppIntegrationTests.swift | Updated tests |

## Upstream File Dependencies

Several playgrounds depend on supporting files from upstream:

| Supporting File | Used By | Action |
|----------------|---------|--------|
| StatePlaygroundModel.swift | StatePlayground | Port to fuse-app |
| PlatformHelper.swift | Multiple playgrounds | Port to fuse-app (provides `isAndroid`, `appName`, etc.) |
| Constants.swift | PlaygroundSourceLink | Skip -- not needed for fuse-app |
| PlaygroundSourceLink.swift | All playgrounds (toolbar) | Skip or replace -- toolbar source links are upstream-specific |
| AboutView.swift | ContentView only | Skip -- not a playground |
| SettingsView.swift | ContentView only | Skip -- not a playground |

## Complexity Estimate

| Category | Count | Lines (approx) | Effort |
|----------|-------|-----------------|--------|
| Infrastructure (cleanup + restructure) | 1 plan | ~300 | Medium |
| Platform stubs | 10 files | ~150 | Low |
| Plain view ports | ~30 files | ~3000 | Low-Medium (mostly copy) |
| Interactive ports (simple) | ~20 files | ~3000 | Medium |
| Interactive ports (complex) | ~14 files | ~5000 | Medium-High |
| Supporting files | 2 files | ~50 | Low |
| Test updates | 1-2 files | ~200 | Medium |
| **Total** | **~84 files** | **~11,700** | **~5-7 plans** |

Large playgrounds by line count that need extra attention:
- ListPlayground.swift (755 lines)
- ToolbarPlayground.swift (701 lines)
- AnimationPlayground.swift (602 lines)
- ShapePlayground.swift (551 lines)
- ScrollViewPlayground.swift (426 lines)
- ImagePlayground.swift (390 lines)

## Open Questions

1. **TCA wrapping depth for ObservablePlayground**
   - What we know: Upstream uses `@Observable` classes and `@Environment` for testing native observation. TCA uses `@ObservableState`.
   - What's unclear: Should ObservablePlayground keep `@Observable` classes (testing bridge observation) or convert to TCA patterns?
   - Recommendation: Keep as plain View with `@Observable` classes -- it specifically tests the observation bridge, which is valuable API validation.

2. **NavigationStack playground within NavigationStack**
   - What we know: NavigationStackPlayground itself creates nested NavigationStacks and presents sheets with NavigationStacks.
   - What's unclear: Whether nested TCA NavigationStack inside the showcase's NavigationStack causes issues.
   - Recommendation: Keep NavigationStackPlayground as a plain View (not TCA-wrapped) since it tests SwiftUI navigation directly. The outer TCA NavigationStack handles routing to it.

3. **SQLPlayground database dependency**
   - What we know: SQLPlayground uses GRDB/SQLite directly. fuse-app already has database dependencies.
   - What's unclear: Whether SQLPlayground needs its own database setup or can reuse fuse-app's.
   - Recommendation: Port as-is -- SQLPlayground creates its own in-memory database. No shared state needed.

4. **ScenarioRegistry cleanup scope**
   - What we know: Existing scenarios reference ForEachNS, PeerSurvival, EngineTest tabs and their actions.
   - What's unclear: Whether ScenarioRegistry.swift needs full rewrite or just emptying.
   - Recommendation: Empty the registry (remove all scenario definitions). The infrastructure (ScenarioStep, runScenario, etc.) stays. New scenarios added on-demand when broken playgrounds are found.

## Sources

### Primary (HIGH confidence)
- Direct inspection of upstream source: `examples/skipapp-showcase-fuse/Sources/ShowcaseFuse/` (89 files, 84 active playgrounds)
- Direct inspection of current fuse-app: `examples/fuse-app/Sources/FuseApp/` (8 source files)
- Project CLAUDE.md and CONTEXT.md -- locked decisions and architecture constraints
- Existing TCA patterns from Phase 18.1 (TestHarnessFeature, ForEachNamespaceSetting, etc.)

### Secondary (MEDIUM confidence)
- Playground complexity classification based on line count and `@State` usage analysis
- Estimate of ~25-30 playgrounds needing TCA reducers based on `@State` presence in upstream files

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, all existing project dependencies
- Architecture: HIGH -- TCA NavigationStack `.forEach` pattern is well-established in this project (Phase 18.1)
- Pitfalls: HIGH -- based on direct code inspection of upstream and fuse-app
- Complexity estimate: MEDIUM -- line counts are exact but effort estimates are approximate

**Research date:** 2026-03-04
**Valid until:** 2026-04-04 (stable -- no external dependencies changing)
