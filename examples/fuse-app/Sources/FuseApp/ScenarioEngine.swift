import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - UICommand

/// A view-layer interaction that cannot be expressed as a TCA action.
/// Executed by the setting's view, acknowledged back to TCA state.
enum UICommand: Equatable, Sendable {
    // Scroll
    case scrollTo(itemID: String)
    case scrollToTop
    case scrollToBottom
    // Interaction
    case tapButton(id: String)
}

// MARK: - ScenarioStep

/// Atomic interaction primitive. Each case is one fuzzer-selectable operation.
enum ScenarioStep: Sendable {
    /// Dispatch a TCA action to the harness store.
    case send(TestHarnessFeature.Action)

    /// Execute a UI command (scroll, gesture) via the view layer.
    case uiCommand(UICommand)

    /// Wait for a duration before proceeding.
    case wait(Duration)

    /// Emit a log message.
    case log(String)

    /// Emit a structured checkpoint marker for log correlation.
    case checkpoint(String)

    var displayDescription: String {
        switch self {
        case .send(let action):
            // Flatten to single line, extract leaf action name
            let raw = String(describing: action)
                .split(whereSeparator: { $0.isNewline || $0 == " " })
                .joined()
            // Strip all trailing )
            var trimmed = raw
            while trimmed.hasSuffix(")") { trimmed = String(trimmed.dropLast()) }
            // Take text after last ( for the leaf name
            if let lastOpen = trimmed.lastIndex(of: "(") {
                trimmed = String(trimmed[trimmed.index(after: lastOpen)...])
                while trimmed.hasPrefix(".") { trimmed = String(trimmed.dropFirst()) }
            }
            return trimmed.isEmpty ? "Send action" : "Send: \(trimmed)"
        case .uiCommand(let cmd):
            switch cmd {
            case .scrollTo(let id): return "Scroll to \(id)"
            case .scrollToTop: return "Scroll to top"
            case .scrollToBottom: return "Scroll to bottom"
            case .tapButton(let id): return "Tap \(id)"
            }
        case .wait(let duration):
            return "Wait \(duration)"
        case .log(let msg):
            return "Log: \(msg)"
        case .checkpoint(let marker):
            return "Checkpoint: \(marker)"
        }
    }
}

// MARK: - Scenario

struct Scenario: Identifiable, Sendable {
    let id: String
    let tab: TestHarnessFeature.State.Tab
    let name: String
    let description: String
    let resetFirst: Bool
    let stepDelay: Duration
    let steps: [ScenarioStep]

    init(
        id: String,
        tab: TestHarnessFeature.State.Tab,
        name: String,
        description: String,
        resetFirst: Bool,
        stepDelay: Duration = LaunchConfig.defaultStepDelay,
        steps: [ScenarioStep]
    ) {
        self.id = id
        self.tab = tab
        self.name = name
        self.description = description
        self.resetFirst = resetFirst
        self.stepDelay = stepDelay
        self.steps = steps
    }
}

// MARK: - LaunchConfig

enum LaunchConfig {
    /// Set to a scenario ID to auto-run on launch. nil = manual mode.
    static let autoRunScenario: String? = nil
    /// Delay before auto-run starts (lets Compose fully initialise).
    static let autoRunDelay: Duration = .seconds(2)
    /// Default delay between scenario steps for visual feedback.
    static let defaultStepDelay: Duration = .milliseconds(300)
}

// MARK: - Scenario Runner

private let scenarioLog = Logger(subsystem: "fuse.app", category: "Identity")

@MainActor
private func awaitResume(store: StoreOf<TestHarnessFeature>) async -> Bool {
    while store.executionMode == .paused {
        if store.runningScenarioID == nil { return false }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return store.runningScenarioID != nil
}

@discardableResult
@MainActor
func runScenario(_ scenario: Scenario, store: StoreOf<TestHarnessFeature>) async -> Bool {
    scenarioLog.debug("[Scenario] START name=\(scenario.name)")
    store.send(.scenarioStarted(id: scenario.id))

    if scenario.resetFirst {
        store.send(.scenarioStepChanged(description: "Resetting state"))
        store.send(.resetAll)
        // Switch to target tab so scroll view is mounted before scrollToTop
        store.send(.tabSelected(scenario.tab))
        try? await Task.sleep(for: .milliseconds(300))
        // Reset scroll position (view-level state not covered by resetAll)
        store.send(.executeUICommand(.scrollToTop))
        try? await Task.sleep(for: .milliseconds(100))
        // Poll for ack (best-effort — don't abort scenario if scroll ack times out)
        for _ in 0..<10 {
            if store.pendingUICommand == nil { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        store.send(.cancelUICommand) // Clear in case of timeout
    }

    // Initial breakpoint pause
    if store.breakOnAllCheckpoints {
        store.send(.debugPause)
        guard await awaitResume(store: store) else {
            store.send(.scenarioEnded)
            return false
        }
    }

    for (i, step) in scenario.steps.enumerated() {
        // Abort check
        guard store.runningScenarioID != nil else { break }

        // Update step index
        store.send(.scenarioStepIndexChanged(index: i, total: scenario.steps.count))
        store.send(.scenarioStepChanged(description: step.displayDescription))

        // Breakpoint check: pause before checkpoints when enabled
        if case .checkpoint = step, store.breakOnAllCheckpoints {
            store.send(.debugPause)
        }

        // Pre-step pause wait
        if store.executionMode == .paused {
            guard await awaitResume(store: store) else { break }
        }

        switch step {
        case .send(let action):
            scenarioLog.debug("[Scenario] STEP[\(i)] SEND \(String(describing: action))")
            store.send(action)
            store.send(.eventLogAppend(EngineEvent(id: UUID(), timestamp: Date(), kind: .send, detail: String(describing: action))))
        case .uiCommand(let cmd):
            scenarioLog.debug("[Scenario] STEP[\(i)] UI_CMD \(String(describing: cmd))")
            store.send(.executeUICommand(cmd))
            store.send(.eventLogAppend(EngineEvent(id: UUID(), timestamp: Date(), kind: .uiCommand, detail: "\(cmd)")))
            // Wait for view to acknowledge
            try? await Task.sleep(for: .milliseconds(100))
            // Poll until acknowledged (with timeout)
            var acknowledged = false
            for _ in 0..<20 {
                if store.pendingUICommand == nil { acknowledged = true; break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            if !acknowledged {
                scenarioLog.error("[Scenario] STEP[\(i)] TIMEOUT: UI command not acknowledged after 1s — \(String(describing: cmd)). Aborting scenario.")
                store.send(.cancelUICommand) // Clear pending state on parent + children
                store.send(.scenarioEnded)
                return false
            }
        case .wait(let duration):
            scenarioLog.debug("[Scenario] STEP[\(i)] WAIT \(duration)")
            if store.executionMode != .steppingOver {
                try? await Task.sleep(for: duration)
            }
            store.send(.eventLogAppend(EngineEvent(id: UUID(), timestamp: Date(), kind: .wait, detail: "\(duration)")))
        case .log(let msg):
            scenarioLog.debug("[Scenario] STEP[\(i)] \(msg)")
            store.send(.eventLogAppend(EngineEvent(id: UUID(), timestamp: Date(), kind: .log, detail: msg)))
        case .checkpoint(let marker):
            scenarioLog.debug("[Scenario] CHECKPOINT \(marker)")
            store.send(.eventLogAppend(EngineEvent(id: UUID(), timestamp: Date(), kind: .checkpoint, detail: marker)))
        }

        // Post-step mode transition
        switch store.executionMode {
        case .stepping, .steppingOver:
            store.send(.debugPause)
        case .playing:
            // Insert step delay for visual feedback (skip after .wait steps — they already pause)
            switch step {
            case .wait:
                break
            default:
                try? await Task.sleep(for: scenario.stepDelay)
            }
        case .paused:
            break // Already paused from breakpoint
        }

        // Post-transition pause wait
        if store.executionMode == .paused {
            guard await awaitResume(store: store) else { break }
        }
    }

    let completed = store.runningScenarioID != nil
    scenarioLog.debug("[Scenario] END name=\(scenario.name) completed=\(completed)")
    store.send(.scenarioEnded)
    return completed
}

// MARK: - Scenario Registry

enum ScenarioRegistry {
    static let all: [Scenario] = [
        foreachNamespaceTabSwitch,
        foreachNamespaceScroll,
        foreachNamespaceAddCard,
        foreachNamespaceDeleteCard,
        foreachNamespaceCompoundMutation,
        peerSurvivalTabSwitch,
        // Engine Test scenarios
        engineSendBasic,
        engineSendOrdering,
        engineUICommandScrollBottom,
        engineUICommandScrollTop,
        engineUICommandScrollToID,
        engineUICommandTimeout,
        engineWaitBasic,
        engineWaitSkipsDelay,
        engineLogAndCheckpoint,
        engineResetDirty,
        engineResetVerify,
        engineStepDelayCustom,
        engineEmptySteps,
        engineMixedAllTypes,
        engineTapButton,
    ]

    static let foreachNamespaceTabSwitch = Scenario(
        id: "foreach-ns-tab-switch",
        tab: .forEachNamespace,
        name: "ForEach NS: Tab Switch",
        description: "Verify card IDs and counter values survive tab switch (TCA-managed state)",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Note card IDs and counter values for all 3 cards"),
            .checkpoint("INITIAL"),
            .log("Switching to Control tab and back..."),
            .send(.tabSelected(.control)),
            .wait(.seconds(1)),
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Check: card IDs and counters should match INITIAL (TCA state persists above TabView)"),
            .checkpoint("POST_TAB_SWITCH"),
        ]
    )

    static let foreachNamespaceScroll = Scenario(
        id: "foreach-ns-scroll",
        tab: .forEachNamespace,
        name: "ForEach NS: Scroll Identity (LazyVStack)",
        description: "Verify counters survive LazyVStack scroll disposal and recomposition",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("INITIAL"),
            .log("Adding 5 cards to overflow the LazyVStack..."),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .wait(.seconds(1)),
            .log("8 cards total. Note top card IDs and counters."),
            .checkpoint("ALL_CARDS_ADDED"),
            .log("WATCH: scrolling to bottom — top cards will be disposed by LazyVStack"),
            .uiCommand(.scrollToBottom),
            .wait(.seconds(1)),
            .checkpoint("AT_BOTTOM"),
            .log("WATCH: scrolling back to top — counters should be preserved (TCA state)"),
            .uiCommand(.scrollToTop),
            .wait(.seconds(1)),
            .log("Check: top card IDs and counters should match ALL_CARDS_ADDED"),
            .checkpoint("BACK_AT_TOP"),
        ]
    )

    static let foreachNamespaceAddCard = Scenario(
        id: "foreach-ns-add-card",
        tab: .forEachNamespace,
        name: "ForEach NS: Add Card",
        description: "Add a card — check existing card counters preserved and animation",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Note card IDs and counters for Cards A, B, C"),
            .checkpoint("INITIAL"),
            .log("WATCH: adding Card D — did it animate in?"),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .wait(.seconds(1)),
            .log("Check: Cards A/B/C keep same IDs and counters? Card D animated in?"),
            .checkpoint("POST_ADD"),
        ]
    )

    static let foreachNamespaceDeleteCard = Scenario(
        id: "foreach-ns-delete-card",
        tab: .forEachNamespace,
        name: "ForEach NS: Delete Card",
        description: "Delete a card — check remaining card counters preserved and animation",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Note card IDs and counters for Cards A, B, C"),
            .checkpoint("INITIAL"),
            .log("WATCH: deleting last card (C) — did it animate out?"),
            .send(.forEachNamespace(.view(.deleteLastCard))),
            .wait(.seconds(1)),
            .log("Check: Cards A/B keep same IDs and counters? Card C animated out?"),
            .checkpoint("POST_DELETE"),
        ]
    )

    static let foreachNamespaceCompoundMutation = Scenario(
        id: "foreach-ns-compound",
        tab: .forEachNamespace,
        name: "ForEach NS: Add + Delete + Tab Switch",
        description: "Compound: add, delete, tab switch — verify counters preserved throughout",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Note card IDs and counters for Cards A, B, C"),
            .checkpoint("INITIAL"),
            .log("WATCH: adding Card D — animation?"),
            .send(.forEachNamespace(.view(.addCardButtonTapped))),
            .wait(.seconds(1)),
            .log("Check: A/B/C same IDs and counters? D appeared with animation?"),
            .checkpoint("POST_ADD"),
            .log("WATCH: deleting Card D — animation?"),
            .send(.forEachNamespace(.view(.deleteLastCard))),
            .wait(.seconds(1)),
            .log("Check: A/B/C same IDs and counters? D removed with animation?"),
            .checkpoint("POST_DELETE"),
            .log("Switching tabs and back..."),
            .send(.tabSelected(.control)),
            .wait(.seconds(1)),
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .log("Check: A/B/C same IDs and counters as INITIAL?"),
            .checkpoint("POST_TAB_SWITCH"),
        ]
    )

    static let peerSurvivalTabSwitch = Scenario(
        id: "peer-survival-tab-switch",
        tab: .peerSurvival,
        name: "Peer Survival: Tab Switch",
        description: "TCA state + @State survive tab switch; CounterCard resets (needs peer remembering)",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.peerSurvival)),
            .wait(.seconds(2)),
            .checkpoint("INITIAL"),  // TCA=0, Section1=0, Section2=0
            .wait(.seconds(2)),

            // TCA state (parent-managed) — SHOULD survive
            .send(.peerSurvival(.view(.incrementTCACounter))),
            .send(.peerSurvival(.view(.incrementTCACounter))),
            .send(.peerSurvival(.view(.incrementTCACounter))),
            .wait(.seconds(2)),
            .checkpoint("POST_TCA"),  // TCA=3, Section1=0, Section2=0
            .wait(.seconds(2)),

            // Compose-level state: Section 1 (view-local @State)
            .uiCommand(.tapButton(id: "peer-tap-button")),
            .wait(.seconds(2)),
            .checkpoint("POST_TAP"),  // TCA=3, Section1=1, Section2=0
            .wait(.seconds(2)),

            // Compose-level state: Section 2 (CounterCard store)
            .uiCommand(.tapButton(id: "peer-card-plus")),
            .wait(.seconds(2)),
            .checkpoint("PRE_SWITCH"),  // TCA=3, Section1=1, Section2=1 (all incremented)
            .wait(.seconds(2)),

            // Tab switch round-trip
            .send(.tabSelected(.forEachNamespace)),
            .wait(.seconds(2)),
            .checkpoint("MID_SWITCH"),  // On different tab
            .wait(.seconds(2)),

            .send(.tabSelected(.peerSurvival)),
            .wait(.seconds(2)),
            .checkpoint("POST_SWITCH"),  // TCA=3, Section1=1(survives), Section2=1(re-triggered from persistent TCA trigger)
            .wait(.seconds(2)),
        ]
    )

    // MARK: - Group A: .send() Action Dispatch

    static let engineSendBasic = Scenario(
        id: "engine-send-basic",
        tab: .engineTest,
        name: "Engine: Basic Send",
        description: "Verify counter increments via send(). Expects counter == 3, 3 send events in log.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .checkpoint("DONE"),
        ]
    )

    static let engineSendOrdering = Scenario(
        id: "engine-send-ordering",
        tab: .engineTest,
        name: "Engine: Send Ordering",
        description: "Verify action dispatch ordering. Expects counter == 1, flag == false, 5 events in exact order.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.toggleFlag))),
            .send(.engineTest(.view(.decrementCounter))),
            .send(.engineTest(.view(.toggleFlag))),
            .checkpoint("DONE"),
        ]
    )

    // MARK: - Group B: .uiCommand() Dispatch/Ack

    static let engineUICommandScrollBottom = Scenario(
        id: "engine-uicmd-scroll-bottom",
        tab: .engineTest,
        name: "Engine: Scroll To Bottom",
        description: "Verify uiCommand dispatch and acknowledgement for scrollToBottom.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .uiCommand(.scrollToBottom),
            .checkpoint("DONE"),
        ]
    )

    static let engineUICommandScrollTop = Scenario(
        id: "engine-uicmd-scroll-top",
        tab: .engineTest,
        name: "Engine: Scroll To Top",
        description: "Scroll to bottom then top. Verify ack for scrollToTop.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .uiCommand(.scrollToBottom),
            .wait(.milliseconds(500)),
            .uiCommand(.scrollToTop),
            .checkpoint("DONE"),
        ]
    )

    static let engineUICommandScrollToID = Scenario(
        id: "engine-uicmd-scroll-to-id",
        tab: .engineTest,
        name: "Engine: Scroll To Item",
        description: "Scroll to item-25. Verify ack for scrollTo.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .uiCommand(.scrollTo(itemID: "item-25")),
            .checkpoint("DONE"),
        ]
    )

    static let engineUICommandTimeout = Scenario(
        id: "engine-uicmd-timeout",
        tab: .engineTest,
        name: "Engine: UI Command Timeout",
        description: "Send uiCommand while on wrong tab. Scenario aborts after 1s timeout.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.control)),
            .wait(.milliseconds(500)),
            .uiCommand(.scrollToTop),
            .checkpoint("SHOULD_NOT_REACH"),
        ]
    )

    // MARK: - Group C: .wait() Duration

    static let engineWaitBasic = Scenario(
        id: "engine-wait-basic",
        tab: .engineTest,
        name: "Engine: Basic Wait",
        description: "Verify wait pauses execution. ~1s gap between sends visible in timestamps.",
        resetFirst: true,
        stepDelay: .milliseconds(100),
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(200)),
            .send(.engineTest(.view(.incrementCounter))),
            .wait(.seconds(1)),
            .send(.engineTest(.view(.incrementCounter))),
            .checkpoint("DONE"),
        ]
    )

    static let engineWaitSkipsDelay = Scenario(
        id: "engine-wait-skips-delay",
        tab: .engineTest,
        name: "Engine: Wait Skips StepDelay",
        description: "Verify stepDelay is skipped after wait steps. PRE→POST gap ~200-400ms, not ~2s.",
        resetFirst: true,
        stepDelay: .seconds(1),
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(200)),
            .checkpoint("PRE"),
            .wait(.milliseconds(100)),
            .send(.engineTest(.view(.incrementCounter))),
            .checkpoint("POST"),
        ]
    )

    // MARK: - Group D: .log() and .checkpoint()

    static let engineLogAndCheckpoint = Scenario(
        id: "engine-log-and-checkpoint",
        tab: .engineTest,
        name: "Engine: Log & Checkpoint",
        description: "Verify log and checkpoint events appear in event log. 4 events (2 log + 2 checkpoint).",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .log("hello"),
            .log("world"),
            .checkpoint("A"),
            .checkpoint("B"),
        ]
    )

    // MARK: - Group E: resetFirst Configuration

    static let engineResetDirty = Scenario(
        id: "engine-reset-dirty",
        tab: .engineTest,
        name: "Engine: Dirty State (Setup)",
        description: "Leave counter=2, flag=true. Run 'Verify Reset' next to confirm reset clears state.",
        resetFirst: false,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.toggleFlag))),
            .checkpoint("DIRTY"),
        ]
    )

    static let engineResetVerify = Scenario(
        id: "engine-reset-verify",
        tab: .engineTest,
        name: "Engine: Verify Reset",
        description: "Verify resetFirst clears state. counter == 0, flag == false, resetCount == 1.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .checkpoint("POST_RESET"),
        ]
    )

    // MARK: - Group F: stepDelay Override

    static let engineStepDelayCustom = Scenario(
        id: "engine-step-delay-custom",
        tab: .engineTest,
        name: "Engine: Custom StepDelay (50ms)",
        description: "Verify ~50ms gaps between sends (not default 300ms). Visible in event timestamps.",
        resetFirst: true,
        stepDelay: .milliseconds(50),
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.incrementCounter))),
            .checkpoint("DONE"),
        ]
    )

    // MARK: - Group G: Edge Cases

    static let engineEmptySteps = Scenario(
        id: "engine-empty-steps",
        tab: .engineTest,
        name: "Engine: Empty Steps",
        description: "Empty steps array. START/END emitted with no steps.",
        resetFirst: false,
        steps: []
    )

    static let engineMixedAllTypes = Scenario(
        id: "engine-mixed-all-types",
        tab: .engineTest,
        name: "Engine: All Step Types",
        description: "All step types in one run. counter == 0, flag == true, all event kinds present.",
        resetFirst: true,
        stepDelay: .milliseconds(100),
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .log("starting mixed"),
            .checkpoint("BEGIN"),
            .send(.engineTest(.view(.incrementCounter))),
            .send(.engineTest(.view(.toggleFlag))),
            .wait(.milliseconds(200)),
            .uiCommand(.scrollToBottom),
            .checkpoint("MID"),
            .send(.engineTest(.view(.decrementCounter))),
            .uiCommand(.scrollToTop),
            .log("finishing mixed"),
            .checkpoint("END"),
        ]
    )

    // MARK: - Group H: tapButton UICommand

    static let engineTapButton = Scenario(
        id: "engine-tap-button",
        tab: .engineTest,
        name: "Engine: Tap Button (No-Op)",
        description: "Verify tapButton UICommand is acknowledged on engine tab.",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.engineTest)),
            .wait(.milliseconds(500)),
            .uiCommand(.tapButton(id: "nonexistent")),
            .checkpoint("DONE"),
        ]
    )
}
