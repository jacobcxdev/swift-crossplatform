import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - PeerSurvivalSetting Reducer

@Reducer
struct PeerSurvivalSetting {
    @ObservableState
    struct State: Equatable {
        var tcaCounter: Int = 0
        var pendingUICommand: UICommand? = nil
        var resetCount: Int = 0
        var peerRememberTrigger: Int = 0
        var counterCardTrigger: Int = 0
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case executeUICommand(UICommand)
        case reset

        @CasePathable
        enum View {
            case incrementTCACounter
            case uiCommandCompleted
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.incrementTCACounter):
                state.tcaCounter += 1
                return .none
            case .view(.uiCommandCompleted):
                state.pendingUICommand = nil
                return .none
            case .executeUICommand(let cmd):
                state.pendingUICommand = cmd
                switch cmd {
                case .tapButton(let id):
                    switch id {
                    case "peer-tap-button": state.peerRememberTrigger += 1
                    case "peer-card-plus": state.counterCardTrigger += 1
                    default: break
                    }
                default: break
                }
                return .run { send in
                    try? await Task.sleep(for: .milliseconds(200))
                    await send(.view(.uiCommandCompleted))
                }
            case .reset:
                let newResetCount = state.resetCount + 1
                // Preserve trigger values so their onChange handlers don't fire
                // spuriously (which would undo the reset).
                let savedPeerTrigger = state.peerRememberTrigger
                let savedCardTrigger = state.counterCardTrigger
                state = .init()
                state.resetCount = newResetCount
                state.peerRememberTrigger = savedPeerTrigger
                state.counterCardTrigger = savedCardTrigger
                return .none
            }
        }
    }
}

// MARK: - PeerSurvivalSettingView

@ViewAction(for: PeerSurvivalSetting.self)
struct PeerSurvivalSettingView: View {
    @Bindable var store: StoreOf<PeerSurvivalSetting>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeaderView(
                    number: 1,
                    title: "PeerRememberTestView",
                    description: "Android-only test. @State + let-with-default. Tap count survives tab switch via rememberSaveable."
                )

                #if SKIP
                let peerRememberItemKey: String = "peer-remember-test-view"
                // SKIP INSERT: val providedPeerItemKey = LocalPeerStoreItemKey provides peerRememberItemKey
                CompositionLocalProvider(providedPeerItemKey) {
                    PeerRememberTestView(externalTapTrigger: store.peerRememberTrigger, externalResetTrigger: store.resetCount)
                }
                #else
                PeerRememberTestView(externalTapTrigger: store.peerRememberTrigger, externalResetTrigger: store.resetCount)
                #endif

                Text("Switch tabs and return — tap count resets on Android (known gap, Plans 16-17).")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                SectionHeaderView(
                    number: 2,
                    title: "CounterCard (mixed view)",
                    description: "Constructor params + let-with-default. Counter resets on tab switch (needs peer remembering, Plans 16-17)."
                )

                #if SKIP
                let peerTestCardItemKey: String = "peer-test-counter-card"
                // SKIP INSERT: val providedPeerTestCardKey = LocalPeerStoreItemKey provides peerTestCardItemKey
                CompositionLocalProvider(providedPeerTestCardKey) {
                    CounterCard(title: "Peer Test Card", externalIncrementTrigger: store.counterCardTrigger, externalResetTrigger: store.resetCount)
                }
                #else
                CounterCard(title: "Peer Test Card", externalIncrementTrigger: store.counterCardTrigger, externalResetTrigger: store.resetCount)
                #endif

                Text("Switch tabs and return — counter resets on Android (known gap, Plans 16-17).")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                SectionHeaderView(
                    number: 3,
                    title: "TCA Counter (parent-managed)",
                    description: "State managed by parent reducer. Always survives tab switch (TCA baseline)."
                )

                HStack {
                    Text("TCA Counter: \(store.tcaCounter)")
                        .font(.title3)
                    Spacer()
                    Button("Increment") { send(.incrementTCACounter) }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Peer Survival")
    }
}
