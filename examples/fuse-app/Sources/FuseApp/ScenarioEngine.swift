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
    case scrollByOffset(Double)
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
            return "Action: \(String(describing: action))"
        case .uiCommand(let cmd):
            switch cmd {
            case .scrollTo(let id): return "Scroll to \(id)"
            case .scrollToTop: return "Scroll to top"
            case .scrollToBottom: return "Scroll to bottom"
            case .scrollByOffset(let offset): return "Scroll by \(offset)"
            }
        case .wait(let duration):
            return "Waiting \(duration)"
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
    let name: String
    let description: String
    let resetFirst: Bool
    let stepDelay: Duration
    let steps: [ScenarioStep]

    init(
        id: String,
        name: String,
        description: String,
        resetFirst: Bool,
        stepDelay: Duration = LaunchConfig.defaultStepDelay,
        steps: [ScenarioStep]
    ) {
        self.id = id
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
func runScenario(_ scenario: Scenario, store: StoreOf<TestHarnessFeature>) async {
    scenarioLog.debug("[Scenario] START name=\(scenario.name)")
    store.send(.scenarioStarted(id: scenario.id))

    if scenario.resetFirst {
        store.send(.scenarioStepChanged(description: "Resetting state"))
        store.send(.resetAll)
        try? await Task.sleep(for: .milliseconds(500))
    }

    for (i, step) in scenario.steps.enumerated() {
        store.send(.scenarioStepChanged(description: step.displayDescription))

        switch step {
        case .send(let action):
            scenarioLog.debug("[Scenario] STEP[\(i)] SEND \(String(describing: action))")
            store.send(action)
        case .uiCommand(let cmd):
            scenarioLog.debug("[Scenario] STEP[\(i)] UI_CMD \(String(describing: cmd))")
            store.send(.executeUICommand(cmd))
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
                return
            }
        case .wait(let duration):
            scenarioLog.debug("[Scenario] STEP[\(i)] WAIT \(duration)")
            try? await Task.sleep(for: duration)
        case .log(let msg):
            scenarioLog.debug("[Scenario] STEP[\(i)] \(msg)")
        case .checkpoint(let marker):
            scenarioLog.debug("[Scenario] CHECKPOINT \(marker)")
        }

        // Insert step delay for visual feedback (skip after .wait steps — they already pause)
        switch step {
        case .wait:
            break
        default:
            try? await Task.sleep(for: scenario.stepDelay)
        }
    }

    scenarioLog.debug("[Scenario] END name=\(scenario.name)")
    store.send(.scenarioEnded)
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
    ]

    static let foreachNamespaceTabSwitch = Scenario(
        id: "foreach-ns-tab-switch",
        name: "ForEach NS: Tab Switch",
        description: "Verify namespace UUID stable across tab switch",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("INITIAL"),
            .checkpoint("PRE_TAB_SWITCH"),
            .send(.tabSelected(.control)),
            .wait(.seconds(1)),
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("POST_TAB_SWITCH"),
        ]
    )

    static let foreachNamespaceScroll = Scenario(
        id: "foreach-ns-scroll",
        name: "ForEach NS: Scroll Identity",
        description: "Verify peer survives scroll off-screen and back",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("INITIAL"),
            // Add enough cards to overflow the List
            .send(.forEachNamespace(.view(.addCard))),
            .send(.forEachNamespace(.view(.addCard))),
            .send(.forEachNamespace(.view(.addCard))),
            .send(.forEachNamespace(.view(.addCard))),
            .send(.forEachNamespace(.view(.addCard))),
            .wait(.seconds(1)),
            .checkpoint("ALL_CARDS_ADDED"),
            .checkpoint("PRE_SCROLL_BOTTOM"),
            .uiCommand(.scrollToBottom),
            .wait(.seconds(1)),
            .checkpoint("POST_SCROLL_BOTTOM"),
            .checkpoint("PRE_SCROLL_TOP"),
            .uiCommand(.scrollToTop),
            .wait(.seconds(1)),
            .checkpoint("POST_SCROLL_TOP"),
        ]
    )

    static let foreachNamespaceAddCard = Scenario(
        id: "foreach-ns-add-card",
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

    static let foreachNamespaceDeleteCard = Scenario(
        id: "foreach-ns-delete-card",
        name: "ForEach NS: Delete Card",
        description: "Verify namespace UUID and peer identity stable after deleting a card",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("INITIAL"),
            .checkpoint("PRE_DELETE_CARD"),
            .send(.forEachNamespace(.view(.deleteLastCard))),
            .wait(.milliseconds(500)),
            .checkpoint("POST_DELETE_CARD"),
        ]
    )

    static let foreachNamespaceCompoundMutation = Scenario(
        id: "foreach-ns-compound",
        name: "ForEach NS: Add + Delete + Tab Switch",
        description: "Compound mutation: add card, delete card, tab switch — verify namespace stability throughout",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("INITIAL"),
            .checkpoint("PRE_ADD"),
            .send(.forEachNamespace(.view(.addCard))),
            .wait(.milliseconds(500)),
            .checkpoint("POST_ADD"),
            .checkpoint("PRE_DELETE"),
            .send(.forEachNamespace(.view(.deleteLastCard))),
            .wait(.milliseconds(500)),
            .checkpoint("POST_DELETE"),
            .checkpoint("PRE_TAB_SWITCH"),
            .send(.tabSelected(.control)),
            .wait(.seconds(1)),
            .send(.tabSelected(.forEachNamespace)),
            .wait(.milliseconds(500)),
            .checkpoint("POST_TAB_SWITCH"),
        ]
    )

    static let peerSurvivalTabSwitch = Scenario(
        id: "peer-survival-tab-switch",
        name: "Peer Survival: Tab Switch",
        description: "Verify itemKey non-null and peer survives tab switch",
        resetFirst: true,
        steps: [
            .send(.tabSelected(.peerSurvival)),
            .wait(.seconds(1)),
            .checkpoint("ON_PEER_TAB"),
            .send(.tabSelected(.forEachNamespace)),
            .wait(.seconds(1)),
            .send(.tabSelected(.peerSurvival)),
            .wait(.seconds(1)),
            .checkpoint("RETURNED_TO_PEER"),
        ]
    )
}
