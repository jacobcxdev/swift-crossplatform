import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - Model Types

struct EngineEvent: Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let detail: String

    enum Kind: String, Equatable, CaseIterable {
        case send, uiCommand, uiAck, reset, log, checkpoint, wait
    }
}

struct ScrollTestItem: Equatable, Identifiable {
    let id: String
    let label: String
}

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
        // Poll for ack (best-effort -- don't abort scenario if scroll ack times out)
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
                scenarioLog.error("[Scenario] STEP[\(i)] TIMEOUT: UI command not acknowledged after 1s -- \(String(describing: cmd)). Aborting scenario.")
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
            // Insert step delay for visual feedback (skip after .wait steps -- they already pause)
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
    /// All registered scenarios. Phase 18.1 scenarios removed; Plan 03 will add showcase scenarios.
    static let all: [Scenario] = []
}
