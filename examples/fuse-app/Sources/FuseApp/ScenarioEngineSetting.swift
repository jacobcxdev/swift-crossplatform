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

// MARK: - ScenarioEngineSetting Reducer

@Reducer
struct ScenarioEngineSetting {
    @ObservableState
    struct State: Equatable {
        // Engine-observable state
        var counter: Int = 0
        var flag: Bool = false
        var resetCount: Int = 0

        // UI command handling
        var lastAcknowledgedCommand: String? = nil
        var pendingUICommand: UICommand? = nil

        // Scroll targets for UICommand testing
        var scrollItems: [ScrollTestItem] = (0..<30).map {
            ScrollTestItem(id: "item-\($0)", label: "Item \($0)")
        }
    }

    @CasePathable
    enum Action: ViewAction {
        // View-initiated actions (from user taps or engine dispatch)
        case view(View)
        // System actions (from parent reducer)
        case executeUICommand(UICommand)
        case reset

        @CasePathable
        enum View {
            case decrementCounter
            case incrementCounter
            case toggleFlag
            case uiCommandCompleted
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            // View actions
            case .view(.decrementCounter):
                state.counter -= 1
                return .none
            case .view(.incrementCounter):
                state.counter += 1
                return .none
            case .view(.toggleFlag):
                state.flag.toggle()
                return .none
            case .view(.uiCommandCompleted):
                let cmdDesc = state.pendingUICommand.map { "\($0)" } ?? "unknown"
                state.lastAcknowledgedCommand = cmdDesc
                state.pendingUICommand = nil
                return .none
            // System actions
            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                return .none
            case .reset:
                let newResetCount = state.resetCount + 1
                state = .init()
                state.resetCount = newResetCount
                return .none
            }
        }
    }
}

// MARK: - ScenarioEngineSettingView

@ViewAction(for: ScenarioEngineSetting.self)
struct ScenarioEngineSettingView: View {
    @Bindable var store: StoreOf<ScenarioEngineSetting>

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Status section
                Section("Status") {
                    HStack {
                        Text("Counter")
                        Spacer()
                        Text("\(store.counter)")
                    }
                    .id("__top__")
                    HStack {
                        Text("Flag")
                        Spacer()
                        Image(systemName: store.flag ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    HStack {
                        Text("Resets")
                        Spacer()
                        Text("\(store.resetCount)")
                                                }
                    if let lastCmd = store.lastAcknowledgedCommand {
                        HStack {
                            Text("Last Ack")
                            Spacer()
                            Text(lastCmd)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if store.pendingUICommand != nil {
                        HStack {
                            ProgressView()
                            Text("Pending UI command…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Scroll Targets section
                Section("Scroll Targets") {
                    ForEach(store.scrollItems) { item in
                        Text(item.label)
                            .id(item.id)
                    }
                }
            }
            .onChange(of: store.pendingUICommand) {
                guard let cmd = store.pendingUICommand else { return }
                switch cmd {
                case .scrollToTop:
                    proxy.scrollTo("__top__", anchor: .top)
                    send(.uiCommandCompleted)
                case .scrollToBottom:
                    if let lastID = store.scrollItems.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    send(.uiCommandCompleted)
                case .scrollTo(let itemID):
                    proxy.scrollTo(itemID, anchor: .center)
                    send(.uiCommandCompleted)
                case .tapButton:
                    send(.uiCommandCompleted) // Engine tab has no compose-level buttons to tap
                }
            }
        }
        .navigationTitle("Engine Test")
    }
}
