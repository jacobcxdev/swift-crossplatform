# Phase 19: Reimplement skipapp-showcase-fuse showcases in fuse-app with TCA and SkipUI API validation - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Port all ~80 playgrounds from `skipapp-showcase-fuse` into `fuse-app`, wrapped in TCA architecture, to validate SkipUI's full API surface when running through the TCA observation bridge on Android. Remove the existing ForEachNS, Peer, and Engine test tabs (Phase 18.1 validation complete). Provide ScenarioEngine infrastructure for on-demand debugging of broken playgrounds.

</domain>

<decisions>
## Implementation Decisions

### Showcase scope and prioritisation
- Port **all ~80 playgrounds** from skipapp-showcase-fuse — match upstream exactly
- Platform-specific playgrounds (Map, Lottie, VideoPlayer, Keychain, Haptic, Compose, DocumentPicker, Pasteboard, ShareLink, WebView) get **stub implementations** with a "Not yet ported" placeholder message — keeps the list complete, easy to fill in later
- Playground content: **Claude's discretion per playground** — faithful port for simple ones, TCA-enhanced versions for complex ones that benefit from exercising TCA patterns
- **Remove completely**: ForEachNamespaceSetting, PeerSurvivalSetting, IdentityComponents, ScenarioEngineSetting, and all associated tests/scenarios. Phase 18.1 is verified — this code served its purpose

### Tab structure and navigation
- **Two tabs**: Showcase + Control
- Showcase tab uses a **flat searchable list** (matching upstream's `PlaygroundNavigationView` layout) with alphabetical ordering
- Navigation is **TCA NavigationStack** — full path-driven navigation via `StackState<ShowcasePath.State>` / `StackAction` / `.forEach`. Validates NAV requirements with ~80 destinations
- **ScenarioEngine and debug toolbar infrastructure stay as-is** — proven infrastructure, scenarios written on-demand

### TCA wrapping depth
- **Claude's discretion per playground**: interactive playgrounds with state get a `@Reducer`, purely visual ones (Divider, Spacer, Border, Shadow, etc.) stay as plain Views
- View pattern: **Claude's discretion** — `@ViewAction` for complex playgrounds, direct `store.send` for simple ones
- Reducer composition: **scoped from root** via navigation StackState — proper TCA composition through `.forEach` on the path
- File layout: **one file per playground** (matching upstream), all in Sources/FuseApp/

### Scenario coverage strategy
- **On-demand scenarios only** — write ScenarioEngine scenarios when something is found broken during manual testing. Scenarios are debug tools, not upfront test suites
- **Delete all existing scenarios** (ForEachNS, peer survival) — clean slate. Git history preserves them
- Broken playgrounds tracked via **UAT document** (consistent with `/gsd:verify-work` pattern)
- TCA TestStore unit tests: **Claude's discretion** based on reducer complexity — complex reducers with effects/scoping get tests, simple ones don't

### Claude's Discretion
- Per-playground decision: faithful port vs TCA-enhanced content
- Per-playground decision: full @Reducer vs plain View (based on interactivity)
- Per-playground decision: @ViewAction vs direct store.send
- Per-playground decision: whether to write TestStore unit tests
- File organisation within Sources/FuseApp/ (though one-file-per-playground is the constraint)
- Exact playground grouping within the alphabetical list (if any visual sectioning is helpful)

</decisions>

<specifics>
## Specific Ideas

- Showcase tab should look and feel like upstream skipapp-showcase-fuse's PlaygroundNavigationView — searchable NavigationStack list
- The ~80-destination TCA NavigationStack is itself a valuable stress test of our NAV requirements on Android
- Each playground file should contain both the reducer (if any) and view, named consistently (e.g. `ButtonPlayground.swift`)
- The root reducer is `TestHarnessFeature` (or renamed), composing the showcase navigation path and ScenarioEngine

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- **ScenarioEngine** (`ScenarioEngine.swift`): Full checkpoint-based automation framework with `adb`-driven step execution, debug toolbar, and event logging — stays as-is for on-demand scenario creation
- **ControlPanelView** (`ControlPanelView.swift`): Scenario selection UI, debug controls — stays as Control tab
- **TestHarnessFeature** (`TestHarnessFeature.swift`): Root TCA reducer with tab management, scenario state, debug toolbar state — restructured to support Showcase + Control tabs instead of 4 test tabs
- **DebugButton**: Reusable debug toolbar button component

### Established Patterns
- TCA reducer composition via `Scope(state:action:)` and `.forEach` — used extensively across Phase 18.1
- `@ViewAction(for:)` macro pattern — used in ForEachNamespaceSetting, PeerSurvivalSetting
- `@CasePathable` enum actions — standard across all TCA features
- `UICommand` system for ScenarioEngine → view communication
- `idLog()` identity logging — can be removed with ForEachNS/Peer cleanup

### Integration Points
- `FuseApp.swift`: App entry point — currently creates TestHarnessView with store
- `Package.swift`: No changes needed — fuse-app already depends on ComposableArchitecture and SkipFuse
- Test targets: `FuseAppIntegrationTests` — existing tests for ForEachNamespaceSetting to be removed, new tests for showcase reducers added selectively

### Source Reference
- **skipapp-showcase-fuse** (`examples/skipapp-showcase-fuse/Sources/ShowcaseFuse/`): 89 Swift files, ~80 playgrounds organised via `PlaygroundType` CaseIterable enum with `NavigationStack` + `.searchable` list
- Key upstream files: `PlaygroundListView.swift` (enum + navigation), `ContentView.swift` (TabView shell), individual `*Playground.swift` files

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 19-reimplement-skipapp-showcase-fuse-showcases-in-fuse-app-with-tca-and-skipui-api-validation*
*Context gathered: 2026-03-04*
