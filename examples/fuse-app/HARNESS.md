# Test Harness Extension Guide

Developer reference for extending the fuse-app test harness with new settings, scenarios, tests, shared components, and UICommands.

## Architecture

```
FuseAppRootView (FuseApp.swift)
 └── TestHarnessView (TestHarnessFeature.swift)
      ├── Tab: ForEachNamespaceSettingView  (ForEachNamespaceSetting.swift)
      ├── Tab: PeerSurvivalSettingView      (PeerSurvivalSetting.swift)
      ├── Tab: ScenarioEngineSettingView    (ScenarioEngineSetting.swift)
      ├── Tab: ControlPanelView             (ControlPanelView.swift)
      │         └── ScenarioRegistry        (ScenarioEngine.swift)
      └── DebugBar (overlay when scenario running)

Tests/FuseAppIntegrationTests/
 ├── FuseAppIntegrationTests.swift   # TestHarness + ForEachNamespace tests
 ├── IdentityFeatureTests.swift      # Extended ForEachNamespace tests
 └── TabBindingTests.swift           # Tab selection binding tests
```

**TCA Composition:** `TestHarnessFeature` is the root reducer. Each setting tab is a child reducer composed via `Scope`. The harness dispatches actions, child reducers process them, and the view renders state.

**UICommand Flow:** For view-layer interactions (scrolling, gestures) that cannot be expressed as TCA actions:

```
ScenarioRunner                  TestHarnessFeature              SettingView
     │                                │                              │
     ├─ .executeUICommand(cmd) ──────►│                              │
     │                                ├─ state.pendingUICommand=cmd  │
     │                                ├─ .send(child.executeUICommand)│
     │                                │                    ──────────►│
     │                                │                              ├─ onChange(pendingUICommand)
     │                                │                              ├─ execute scroll/gesture
     │                                │                              ├─ send(.uiCommandCompleted)
     │                                │◄─ child.view.uiCommandCompleted│
     │                                ├─ state.pendingUICommand=nil  │
     │  poll: pendingUICommand==nil   │                              │
     ├────────────────────────────────►│                              │
     │  ✓ acknowledged                │                              │
```

## File Map

| File | Purpose |
|------|---------|
| `Sources/FuseApp/TestHarnessFeature.swift` | Root reducer + view: tab state, UICommand forwarding, child composition, debug bar overlay |
| `Sources/FuseApp/ForEachNamespaceSetting.swift` | Setting: ForEach namespace UUID stability (R5 Issue 1) |
| `Sources/FuseApp/PeerSurvivalSetting.swift` | Setting: peer survival across tab switches (Sections 6/7), external trigger pattern |
| `Sources/FuseApp/ScenarioEngineSetting.swift` | Setting: engine test tab with counter/flag state, scroll targets for UICommand testing |
| `Sources/FuseApp/ControlPanelView.swift` | Control panel: scenario selection, event log, status display, reset + play toolbar |
| `Sources/FuseApp/ScenarioEngine.swift` | UICommand enum, ScenarioStep primitives, Scenario struct, runner, registry |
| `Sources/FuseApp/IdentityComponents.swift` | Shared: `idLog()`, `CardItem`, `LocalCounterFeature`, `CounterCard`, `PeerRememberTestView`, `SectionHeaderView` |
| `Sources/FuseApp/FuseApp.swift` | App entry: creates root store, auto-run on launch |

## Adding a Setting

A "setting" is a tab in the harness — a TCA reducer + view pair that exercises a specific identity/rendering concern.

### Step 1: Create the reducer

Create `Sources/FuseApp/MyNewSetting.swift`:

```swift
import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - MyNewSetting Reducer

@Reducer
struct MyNewSetting {
    @ObservableState
    struct State: Equatable {
        // Your state here
        var pendingUICommand: UICommand? = nil  // Only if this setting handles UICommands
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case reset
        case executeUICommand(UICommand)  // Only if this setting handles UICommands

        @CasePathable
        enum View {
            // Your view actions here
            case uiCommandCompleted  // Only if this setting handles UICommands
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .reset:
                state = .init()
                return .none
            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                return .none
            case .view(.uiCommandCompleted):
                state.pendingUICommand = nil
                return .none
            case .view:
                return .none
            }
        }
    }
}
```

### Step 2: Create the view

In the same file:

```swift
@ViewAction(for: MyNewSetting.self)
struct MyNewSettingView: View {
    @Bindable var store: StoreOf<MyNewSetting>

    var body: some View {
        // Your view here. Use idLog() for identity-related logging:
        let _ = idLog("[MyNew] body: ...")
        Text("My New Setting")
            .navigationTitle("My New Setting")
    }
}
```

### Step 3: Add tab enum case

In `TestHarnessFeature.swift`, add to `State.Tab`:

```swift
enum Tab: String, Equatable, CaseIterable {
    case forEachNamespace, peerSurvival, engineTest, control, myNew  // ← add
}
```

### Step 4: Compose into harness reducer

In `TestHarnessFeature.swift`:

1. Add child state: `var myNew = MyNewSetting.State()`
2. Add action case: `case myNew(MyNewSetting.Action)`
3. Add `Scope` in body:
   ```swift
   Scope(state: \.myNew, action: \.myNew) { MyNewSetting() }
   ```
4. Add UICommand forwarding in `executeUICommand` switch (if applicable):
   ```swift
   case .myNew:
       return .send(.myNew(.executeUICommand(cmd)))
   ```
5. Add UICommand acknowledgment (if applicable):
   ```swift
   case .myNew(.view(.uiCommandCompleted)):
       state.pendingUICommand = nil
       return .none
   ```
6. Add wildcard passthrough: `case .myNew: return .none`
7. Reset in `resetAll`: `state.myNew = .init()`
8. Clear in `cancelUICommand` (if applicable): `state.myNew.pendingUICommand = nil`

### Step 5: Add tab to TestHarnessView

In `TestHarnessView.body`:

```swift
NavigationStack {
    MyNewSettingView(store: store.scope(state: \.myNew, action: \.myNew))
}
.tabItem { Label("My New", systemImage: "star") }
.tag(TestHarnessFeature.State.Tab.myNew)
```

## Adding a Scenario

Scenarios are sequences of `ScenarioStep` primitives that automate testing flows. They run from the Control Panel or via auto-run on launch.

### Primitives Reference

| Primitive | Purpose | Example |
|-----------|---------|---------|
| `.send(action)` | Dispatch a TCA action to the harness store | `.send(.tabSelected(.forEachNamespace))` |
| `.uiCommand(cmd)` | Execute a view-layer command (scroll, gesture, tap) | `.uiCommand(.scrollToBottom)` |
| `.wait(duration)` | Pause between steps | `.wait(.milliseconds(500))` |
| `.log(msg)` | Emit a debug log message | `.log("About to mutate")` |
| `.checkpoint(marker)` | Emit a structured checkpoint for log correlation | `.checkpoint("PRE_ADD_CARD")` |

### UICommand Reference

| Command | Purpose | Tabs that handle it |
|---------|---------|---------------------|
| `.scrollTo(itemID:)` | Scroll to a specific item by ID | ForEachNamespace, EngineTest |
| `.scrollToTop` | Scroll to the top of the list | ForEachNamespace, EngineTest |
| `.scrollToBottom` | Scroll to the bottom of the list | ForEachNamespace, EngineTest |
| `.tapButton(id:)` | Trigger a button tap via external trigger pattern | PeerSurvival (mapped IDs below) |

**tapButton IDs for PeerSurvival tab:**

| ID | Target | Effect |
|----|--------|--------|
| `"peer-tap-button"` | PeerRememberTestView | Increments `@State tapCount` |
| `"peer-card-plus"` | CounterCard | Sends `.incrementButtonTapped` to local store |

Tabs that don't handle a command acknowledge it as a no-op (send `.uiCommandCompleted` immediately) to prevent scenario timeout.

### Checkpoint Convention

Use `PRE_`/`POST_` pairs around every mutation or navigation event:

```swift
.checkpoint("PRE_ADD_CARD"),
.send(.forEachNamespace(.view(.addCard))),
.wait(.milliseconds(500)),
.checkpoint("POST_ADD_CARD"),
```

This enables an **oracle pattern** for automated log analysis:

1. Find `CHECKPOINT PRE_ADD_CARD` in logs
2. Find `CHECKPOINT POST_ADD_CARD` in logs
3. Extract all `ns=<UUID>` values between those markers
4. If the UUID set has more than one unique value → namespace instability detected

### Writing a Scenario

Add to `ScenarioEngine.swift` as a static property on `ScenarioRegistry`:

```swift
static let myNewScenario = Scenario(
    id: "my-new-scenario",           // Unique kebab-case ID
    tab: .myNew,                     // Tab this scenario targets (for grouping in Control Panel)
    name: "My New: Description",      // Human-readable name
    description: "What this tests",   // Shown in Control Panel
    resetFirst: true,                 // true = reset harness state before running
    steps: [
        .send(.tabSelected(.myNew)),  // Ensure correct tab is active
        .wait(.milliseconds(500)),    // Let Compose settle
        .checkpoint("INITIAL"),
        // ... your steps with PRE_/POST_ brackets ...
    ]
)
```

### Registering

Add to `ScenarioRegistry.all`:

```swift
static let all: [Scenario] = [
    // ... existing scenarios ...
    myNewScenario,  // ← add
]
```

### Worked Example: ForEach Namespace Add Card

```swift
static let foreachNamespaceAddCard = Scenario(
    id: "foreach-ns-add-card",
    tab: .forEachNamespace,
    name: "ForEach NS: Add Card",
    description: "Verify namespace UUID and peer identity stable after adding a card",
    resetFirst: true,
    steps: [
        .send(.tabSelected(.forEachNamespace)),
        .wait(.milliseconds(500)),
        .checkpoint("INITIAL"),
        .checkpoint("PRE_ADD_CARD"),
        .send(.forEachNamespace(.view(.addCard))),
        .wait(.milliseconds(500)),
        .checkpoint("POST_ADD_CARD"),
    ]
)
```

## Adding Tests

Tests use TCA's `TestStore` with Swift Testing (`@Test`). All test suites use `@Suite(.serialized) @MainActor`.

### Conventions

- File: `Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift` (or a new file for a new suite)
- Wrap in `#if !SKIP ... #endif` (tests run on Darwin only)
- Use `@testable import FuseApp`
- Use deterministic UUIDs via `$0.uuid = .constant(...)` or `UUIDGenerator`
- Use `store.exhaustivity = .off` only when state mutations create non-deterministic UUIDs (e.g., `.reset` re-creates default cards)

### TestStore Patterns

**Basic action → state mutation:**
```swift
@Test func myAction() async {
    let store = TestStore(initialState: MyNewSetting.State()) {
        MyNewSetting()
    }
    await store.send(.view(.someAction)) {
        $0.someProperty = expectedValue
    }
}
```

**Action that produces an effect (`.send` returns another action):**
```swift
@Test func deleteFirstCard() async {
    let store = TestStore(
        initialState: ForEachNamespaceSetting.State(
            cards: [CardItem(id: idA, title: "A"), CardItem(id: idB, title: "B")],
            nextLetter: "C"
        )
    ) { ForEachNamespaceSetting() }

    await store.send(.view(.deleteFirstCard))       // No state change on this action
    await store.receive(\.view.deleteCard) {         // Effect sends .deleteCard(idA)
        $0.cards.remove(id: idA)
    }
}
```

**UICommand forwarding (parent → child via effect):**
```swift
@Test func executeUICommandAndAcknowledge() async {
    let store = TestStore(initialState: TestHarnessFeature.State()) {
        TestHarnessFeature()
    }
    await store.send(.executeUICommand(.scrollToBottom)) {
        $0.pendingUICommand = .scrollToBottom
    }
    await store.receive(\.forEachNamespace.executeUICommand) {
        $0.forEachNamespace.pendingUICommand = .scrollToBottom
    }
    await store.send(.forEachNamespace(.view(.uiCommandCompleted))) {
        $0.forEachNamespace.pendingUICommand = nil
        $0.pendingUICommand = nil
    }
}
```

**Cancel UICommand:**
```swift
@Test func cancelUICommandClearsState() async {
    let store = TestStore(initialState: TestHarnessFeature.State()) {
        TestHarnessFeature()
    }
    await store.send(.executeUICommand(.scrollToBottom)) {
        $0.pendingUICommand = .scrollToBottom
    }
    await store.receive(\.forEachNamespace.executeUICommand) {
        $0.forEachNamespace.pendingUICommand = .scrollToBottom
    }
    await store.send(.cancelUICommand) {
        $0.pendingUICommand = nil
        $0.forEachNamespace.pendingUICommand = nil
    }
}
```

### Dependency Injection

For deterministic UUIDs:
```swift
let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
let store = TestStore(initialState: ...) {
    ForEachNamespaceSetting()
} withDependencies: {
    $0.uuid = .constant(testUUID)
}
```

For sequential UUIDs:
```swift
let uuids = [idA, idB, idC]
let counter = LockIsolated(0)
// ... withDependencies:
$0.uuid = .init {
    let i = counter.value
    counter.withValue { $0 += 1 }
    return uuids[i]
}
```

## Adding Shared Components

Shared types live in `Sources/FuseApp/IdentityComponents.swift`.

### What belongs here

- **Data models** used across settings: `CardItem`, etc.
- **Reusable views** that exercise specific transpiler patterns: `CounterCard` (mixed view), `PeerRememberTestView` (no-param view)
- **Logging utilities**: `idLog()` function
- **Section headers**: `SectionHeaderView`

### Logging Convention

Use `idLog()` (defined in `IdentityComponents.swift`) for identity-related logging:

```swift
let _ = idLog("[MyPrefix] body: key=\(value)")
```

- Logger: `subsystem: "fuse.app"`, `category: "Identity"`
- Prefix convention: `[SettingName]` e.g. `[ForEachNS]`, `[CounterCard]`
- Log at the top of `body` with current state summary
- Log inside `ForEach` closures with item identity

### Naming

| Type | Convention | Example |
|------|-----------|---------|
| Reducer | `<Name>Setting` | `ForEachNamespaceSetting` |
| View | `<Name>SettingView` | `ForEachNamespaceSettingView` |
| Shared view | Descriptive name | `CounterCard`, `PeerRememberTestView` |
| Scenario | `<setting><Operation>` | `foreachNamespaceAddCard` |
| Scenario ID | kebab-case | `"foreach-ns-add-card"` |
| Test suite | `<Name>Tests` | `ForEachNamespaceSettingTests` |

## Adding UICommands

UICommands are view-layer interactions (scroll, gesture) that cannot be expressed as TCA actions.

### Step 1: Add enum case

In `ScenarioEngine.swift`:

```swift
enum UICommand: Equatable, Sendable {
    // Scroll
    case scrollTo(itemID: String)
    case scrollToTop
    case scrollToBottom
    // Interaction
    case tapButton(id: String)
    case myNewCommand  // ← add
}
```

### Step 2: Handle in the setting view

In your setting's view, inside `onChange(of: store.pendingUICommand)`:

```swift
case .myNewCommand:
    // Execute the view-layer interaction
    proxy.scrollTo(...)
```

Always call `send(.uiCommandCompleted)` after execution.

### Step 3: Unsupported commands

If a setting's view doesn't support a command, log and acknowledge:

```swift
case .myNewCommand:
    idLog("[MyNew] myNewCommand not supported — no-op")
```

Then call `send(.uiCommandCompleted)` so the scenario runner doesn't timeout.

### Step 4: Use in scenarios

```swift
.uiCommand(.myNewCommand),
.wait(.seconds(1)),
```

The scenario runner handles the full request→poll→timeout cycle automatically. If the view doesn't acknowledge within 1 second, the runner aborts the scenario and sends `.cancelUICommand`.

## External Trigger Pattern

For testing compose-level state (view-local `@State` or local TCA stores) that is unreachable from the parent reducer, use the **external trigger pattern**:

1. Add an `externalTapTrigger: Int = 0` (or similar) parameter to the child view with a default value
2. Add `.onChange(of: externalTapTrigger) { _, _ in /* mutate local state */ }` in the child's body
3. In the parent view, add `@State var childTrigger: Int = 0` and pass it to the child
4. The parent's `onChange(of: store.pendingUICommand)` handler increments the trigger for `.tapButton` commands

**Reset triggers** follow the same pattern: add `externalResetTrigger: Int = 0` to children, wired to a `resetCount` in the parent reducer's state that increments on `.reset`.

**Timing on Android:** The parent `onChange` fires and acks before the child `onChange` processes the new trigger value (Compose recomposition is async). For `tapButton` commands, delay the ack by ~300ms to allow child recomposition:

```swift
case .tapButton(let id):
    switch id {
    case "my-button": childTrigger += 1
    default: break
    }
    Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(300))
        send(.uiCommandCompleted)
    }
```

Existing call sites are unaffected — default parameter values mean `onChange` never fires when triggers aren't passed.

## Event Log

The scenario engine captures events to an in-memory log displayed in the Control Panel's collapsible "Event Log" section.

**Event kinds:** `send`, `uiCommand`, `uiAck`, `reset`, `log`, `checkpoint`, `wait`

Events are appended by the scenario runner via `.eventLogAppend(EngineEvent(...))`. The log captures events from all tabs — it lives on `TestHarnessFeature.State.eventLog`, not on individual settings.

Clear the log via the "Clear Log" button or `.clearEventLog` action.

## Debugger Controls

When a scenario is running, a debug bar overlay appears at the bottom of the screen with transport controls:

| Button | Action | When available |
|--------|--------|----------------|
| Stop | Abort scenario | Always |
| Pause | Pause execution | When playing |
| Step | Execute one step then pause | When paused |
| Skip | Execute one step (skip waits) then pause | When paused |
| Play | Resume continuous playback | When paused/stepping |

**Breakpoints:** Toggle "Pause on all checkpoints" in the Control Panel Status section. When enabled, execution pauses before each `.checkpoint` step and at the start of the scenario.

## Android Verification Loop

### Build and Deploy

```bash
just android-run fuse-app
```

This builds, exports APK, installs on emulator, launches, and streams logs.

### Log Tags

| Tag | Source | Content |
|-----|--------|---------|
| `fuse.app/Identity` | `idLog()` + scenario checkpoints | App-level identity logging + scenario markers |
| `ComposeIdentity` | skip-ui framework | Framework-level identity logging (very verbose) |
| `skip.ui.SkipUI` | SkipUI runtime | View lifecycle, navigation |

### Filtering

```bash
# Scenario checkpoints + app-level identity logs
adb logcat -s fuse.app/Identity:D

# Framework identity logs (very verbose)
adb logcat -s ComposeIdentity:D

# Both combined
adb logcat -s fuse.app/Identity:D ComposeIdentity:D
```

### Checkpoint-Based Oracle Analysis

Checkpoint markers come from `fuse.app/Identity` (scenario engine). The `ns=<UUID>` values that indicate namespace stability/instability come from `ComposeIdentity` (skip-ui framework). Both must be captured.

**Important:** Clear the logcat buffer before each run to avoid mixing results from previous runs.

```bash
# Clear logcat buffer before running the scenario
adb logcat -c

# Run the scenario (via Control Panel or auto-run), then dump
adb logcat -d -s fuse.app/Identity:D ComposeIdentity:D > /tmp/identity-logs.txt

# Extract logs between two checkpoints
sed -n '/CHECKPOINT PRE_ADD_CARD/,/CHECKPOINT POST_ADD_CARD/p' /tmp/identity-logs.txt

# Check for namespace instability (multiple unique ns= UUIDs from ComposeIdentity)
sed -n '/CHECKPOINT PRE_ADD_CARD/,/CHECKPOINT POST_ADD_CARD/p' /tmp/identity-logs.txt \
    | grep -oP 'ns=\K[0-9a-f-]+' | sort -u | wc -l
# Result: 1 = stable, >1 = namespace instability detected
```

### Auto-Run on Launch

Set `LaunchConfig.autoRunScenario` in `ScenarioEngine.swift` to a scenario ID:

```swift
static let autoRunScenario: String? = "foreach-ns-add-card"
```

The scenario runs automatically after `autoRunDelay` (default 2 seconds) to let Compose fully initialise.
