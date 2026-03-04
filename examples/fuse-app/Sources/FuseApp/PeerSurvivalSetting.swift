import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - PeerSurvivalSetting Reducer

@Reducer
struct PeerSurvivalSetting {
    @ObservableState
    struct State: Equatable { }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case reset

        @CasePathable
        enum View { }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .reset:
                state = .init()
                return .none
            case .view:
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
                    description: "Android-only test. @State + let-with-default (no constructor params). Tap count should survive tab switch."
                )

                #if SKIP
                let peerRememberItemKey: String = "peer-remember-test-view"
                // SKIP INSERT: val providedPeerItemKey = LocalPeerStoreItemKey provides peerRememberItemKey
                CompositionLocalProvider(providedPeerItemKey) {
                    PeerRememberTestView()
                }
                #else
                PeerRememberTestView()
                #endif

                Text("Switch tabs and return — tap count should be preserved on Android.")
                    .font(.caption2).foregroundStyle(.secondary)

                Divider()

                SectionHeaderView(
                    number: 2,
                    title: "CounterCard (mixed view)",
                    description: "Constructor params + let-with-default. Counter state should survive tab switch."
                )

                #if SKIP
                let peerTestCardItemKey: String = "peer-test-counter-card"
                // SKIP INSERT: val providedPeerTestCardKey = LocalPeerStoreItemKey provides peerTestCardItemKey
                CompositionLocalProvider(providedPeerTestCardKey) {
                    CounterCard(title: "Peer Test Card")
                }
                #else
                CounterCard(title: "Peer Test Card")
                #endif

                Text("Switch tabs and return — counter value should be preserved on Android.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Peer Survival")
    }
}
