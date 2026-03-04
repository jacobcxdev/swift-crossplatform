import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - TestHarnessFeature Reducer

@Reducer
struct TestHarnessFeature {
    @ObservableState
    struct State: Equatable {
        var selectedTab: Tab = .forEachNamespace
        var forEachNamespace = ForEachNamespaceSetting.State()
        var peerSurvival = PeerSurvivalSetting.State()
        var engineTest = ScenarioEngineSetting.State()
        var pendingUICommand: UICommand? = nil
        var selectedScenarioIDs: Set<String> = []
        var runningScenarioID: String? = nil
        var currentStepDescription: String? = nil
        var executionMode: ExecutionMode = .playing
        var currentStepIndex: Int = 0
        var totalStepCount: Int = 0
        var breakOnAllCheckpoints: Bool = true
        var eventLog: [EngineEvent] = []

        var isScenarioRunning: Bool { runningScenarioID != nil }

        enum ExecutionMode: String, Equatable {
            case playing      // Normal playback with stepDelay
            case paused       // Waiting for user input
            case stepping     // Execute one step then pause
            case steppingOver // Execute one step, skip waits, then pause
        }

        enum Tab: String, Equatable, CaseIterable {
            case forEachNamespace, peerSurvival, engineTest, control

            var displayName: String {
                switch self {
                case .forEachNamespace: "ForEach Namespace"
                case .peerSurvival: "Peer Survival"
                case .engineTest: "Engine Test"
                case .control: "Control"
                }
            }
        }
    }

    @CasePathable
    enum Action {
        case tabSelected(State.Tab)
        case forEachNamespace(ForEachNamespaceSetting.Action)
        case peerSurvival(PeerSurvivalSetting.Action)
        case engineTest(ScenarioEngineSetting.Action)
        case resetAll
        case executeUICommand(UICommand)
        case uiCommandCompleted
        case cancelUICommand
        case scenarioToggled(id: String)
        case scenarioSetSelected(ids: [String], selected: Bool)
        case scenarioStarted(id: String)
        case scenarioStepChanged(description: String)
        case scenarioEnded
        case debugPlay
        case debugPause
        case debugStep
        case debugStepOver
        case debugStop
        case toggleBreakOnAllCheckpoints
        case scenarioStepIndexChanged(index: Int, total: Int)
        case eventLogAppend(EngineEvent)
        case clearEventLog
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.forEachNamespace, action: \.forEachNamespace) {
            ForEachNamespaceSetting()
        }
        Scope(state: \.peerSurvival, action: \.peerSurvival) {
            PeerSurvivalSetting()
        }
        Scope(state: \.engineTest, action: \.engineTest) {
            ScenarioEngineSetting()
        }
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none
            case .scenarioToggled(let id):
                if state.selectedScenarioIDs.contains(id) {
                    state.selectedScenarioIDs.remove(id)
                } else {
                    state.selectedScenarioIDs.insert(id)
                }
                return .none
            case .scenarioSetSelected(let ids, let selected):
                for id in ids {
                    if selected {
                        state.selectedScenarioIDs.insert(id)
                    } else {
                        state.selectedScenarioIDs.remove(id)
                    }
                }
                return .none
            case .resetAll:
                state.forEachNamespace = .init()
                state.engineTest = .init()
                state.pendingUICommand = nil
                return .merge(
                    .send(.forEachNamespace(.seedInitialCards)),
                    .send(.peerSurvival(.reset))
                )
            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                // Forward to active tab's child via action
                switch state.selectedTab {
                case .forEachNamespace:
                    return .send(.forEachNamespace(.executeUICommand(cmd)))
                case .engineTest:
                    return .send(.engineTest(.executeUICommand(cmd)))
                case .peerSurvival:
                    return .send(.peerSurvival(.executeUICommand(cmd)))
                case .control:
                    return .none
                }
            case .uiCommandCompleted:
                state.pendingUICommand = nil
                return .none
            case .cancelUICommand:
                state.pendingUICommand = nil
                state.forEachNamespace.pendingUICommand = nil
                state.engineTest.pendingUICommand = nil
                state.peerSurvival.pendingUICommand = nil
                return .none
            case .scenarioStarted(let id):
                state.runningScenarioID = id
                state.currentStepDescription = nil
                return .none
            case .scenarioStepChanged(let description):
                state.currentStepDescription = description
                return .none
            case .scenarioEnded:
                state.runningScenarioID = nil
                state.currentStepDescription = nil
                state.executionMode = .playing
                state.currentStepIndex = 0
                state.totalStepCount = 0
                return .none
            case .debugPlay:
                state.executionMode = .playing
                return .none
            case .debugPause:
                state.executionMode = .paused
                return .none
            case .debugStep:
                state.executionMode = .stepping
                return .none
            case .debugStepOver:
                state.executionMode = .steppingOver
                return .none
            case .debugStop:
                state.runningScenarioID = nil
                state.currentStepDescription = nil
                state.executionMode = .playing
                state.currentStepIndex = 0
                state.totalStepCount = 0
                return .none
            case .toggleBreakOnAllCheckpoints:
                state.breakOnAllCheckpoints.toggle()
                return .none
            case .scenarioStepIndexChanged(let index, let total):
                state.currentStepIndex = index
                state.totalStepCount = total
                return .none
            case .eventLogAppend(let event):
                state.eventLog.append(event)
                return .none
            case .clearEventLog:
                state.eventLog = []
                return .none
            case .forEachNamespace(.view(.uiCommandCompleted)):
                state.pendingUICommand = nil
                return .none
            case .engineTest(.view(.uiCommandCompleted)):
                state.pendingUICommand = nil
                return .none
            case .peerSurvival(.view(.uiCommandCompleted)):
                state.pendingUICommand = nil
                return .none
            case .forEachNamespace, .peerSurvival, .engineTest:
                return .none
            }
        }
    }
}

// MARK: - TestHarnessView

struct TestHarnessView: View {
    @Bindable var store: StoreOf<TestHarnessFeature>
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
                NavigationStack {
                    ForEachNamespaceSettingView(
                        store: store.scope(state: \.forEachNamespace, action: \.forEachNamespace)
                    )
                }
                .tabItem { Label("ForEach NS", systemImage: "list.bullet") }
                .tag(TestHarnessFeature.State.Tab.forEachNamespace)

                NavigationStack {
                    PeerSurvivalSettingView(
                        store: store.scope(state: \.peerSurvival, action: \.peerSurvival)
                    )
                }
                .tabItem { Label("Peer", systemImage: "person.crop.square") }
                .tag(TestHarnessFeature.State.Tab.peerSurvival)

                NavigationStack {
                    ScenarioEngineSettingView(
                        store: store.scope(state: \.engineTest, action: \.engineTest)
                    )
                }
                .tabItem { Label("Engine", systemImage: "wrench") }
                .tag(TestHarnessFeature.State.Tab.engineTest)

                NavigationStack {
                    ControlPanelView(store: store)
                }
                .tabItem { Label("Control", systemImage: "gearshape") }
                .tag(TestHarnessFeature.State.Tab.control)
            }


            if store.isScenarioRunning {
                let isPaused = store.executionMode == .paused
                VStack(spacing: 6) {
                    // Step info row
                    HStack(spacing: 6) {
                        if isPaused {
                            Text("PAUSED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(store.currentStepDescription ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if store.totalStepCount > 0 {
                            Text("\(store.currentStepIndex + 1)/\(store.totalStepCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Progress bar
                    if store.totalStepCount > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isPaused ? Color.orange : Color.blue)
                                    .frame(
                                        width: geo.size.width * Double(store.currentStepIndex + 1) / Double(max(store.totalStepCount, 1)),
                                        height: 3
                                    )
                            }
                        }
                        .frame(height: 3)
                    }

                    // Transport controls
                    HStack(spacing: 0) {
                        DebugButton(icon: "stop.fill", label: "Stop", tint: .red, enabled: true) {
                            store.send(.debugStop)
                        }
                        Spacer()
                        DebugButton(icon: "pause.fill", label: "Pause", tint: isPaused ? .orange : .primary, enabled: !isPaused) {
                            store.send(.debugPause)
                        }
                        Spacer()
                        DebugButton(icon: "chevron.right", label: "Step", tint: .blue, enabled: isPaused) {
                            store.send(.debugStep)
                        }
                        Spacer()
                        DebugButton(icon: "arrow.forward", label: "Skip", tint: .blue, enabled: isPaused) {
                            store.send(.debugStepOver)
                        }
                        Spacer()
                        DebugButton(icon: "play.fill", label: "Play", tint: .green, enabled: store.executionMode != .playing) {
                            store.send(.debugPlay)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 54)
            }
        }
    }
}

// MARK: - DebugButton

struct DebugButton: View {
    let icon: String
    var label: String? = nil
    var tint: Color = .primary
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                if let label {
                    Text(label)
                        .font(.caption2)
                }
            }
            .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.3))
            .frame(minWidth: 44, minHeight: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
