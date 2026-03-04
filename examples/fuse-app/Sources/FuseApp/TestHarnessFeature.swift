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
        var pendingUICommand: UICommand? = nil
        var runningScenarioID: String? = nil
        var currentStepDescription: String? = nil

        var isScenarioRunning: Bool { runningScenarioID != nil }

        enum Tab: String, Equatable, CaseIterable {
            case forEachNamespace, peerSurvival, control
        }
    }

    @CasePathable
    enum Action {
        case tabSelected(State.Tab)
        case forEachNamespace(ForEachNamespaceSetting.Action)
        case peerSurvival(PeerSurvivalSetting.Action)
        case resetAll
        case executeUICommand(UICommand)
        case uiCommandCompleted
        case cancelUICommand
        case scenarioStarted(id: String)
        case scenarioStepChanged(description: String)
        case scenarioEnded
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.forEachNamespace, action: \.forEachNamespace) {
            ForEachNamespaceSetting()
        }
        Scope(state: \.peerSurvival, action: \.peerSurvival) {
            PeerSurvivalSetting()
        }
        Reduce { state, action in
            switch action {
            case .tabSelected(let tab):
                state.selectedTab = tab
                return .none
            case .resetAll:
                state.forEachNamespace = .init()
                state.peerSurvival = .init()
                state.pendingUICommand = nil
                return .none
            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                // Forward to active tab's child via action
                switch state.selectedTab {
                case .forEachNamespace:
                    return .send(.forEachNamespace(.executeUICommand(cmd)))
                case .peerSurvival, .control:
                    return .none
                }
            case .uiCommandCompleted:
                state.pendingUICommand = nil
                return .none
            case .cancelUICommand:
                state.pendingUICommand = nil
                state.forEachNamespace.pendingUICommand = nil
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
                return .none
            case .forEachNamespace(.view(.uiCommandCompleted)):
                state.pendingUICommand = nil
                return .none
            case .forEachNamespace, .peerSurvival:
                return .none
            }
        }
    }
}

// MARK: - TestHarnessView

struct TestHarnessView: View {
    @Bindable var store: StoreOf<TestHarnessFeature>

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
                    ControlPanelView(store: store)
                }
                .tabItem { Label("Control", systemImage: "gearshape") }
                .tag(TestHarnessFeature.State.Tab.control)
            }
            .disabled(store.isScenarioRunning)

            if let stepDescription = store.currentStepDescription {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(stepDescription)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.bottom, 60)
            }
        }
    }
}
