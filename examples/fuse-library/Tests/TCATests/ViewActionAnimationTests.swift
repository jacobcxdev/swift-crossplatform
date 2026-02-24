#if canImport(SwiftUI)
#if !SKIP
import ComposableArchitecture
import SwiftUI
import Testing

// MARK: - Test Reducer (file scope -- macros can't attach to local types)

@Reducer
struct AnimSendFeature {
    @ObservableState
    struct State: Equatable {
        var count: Int = 0
    }
    enum Action: ViewAction {
        case view(View)
        enum View {
            case tapped
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.tapped):
                state.count += 1
                return .none
            }
        }
    }
}

// MARK: - ViewActionSending conformance

@MainActor
struct AnimSender: ViewActionSending {
    let store: Store<AnimSendFeature.State, AnimSendFeature.Action>
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct ViewActionAnimationTests {

    // MARK: SC-1: send(_:animation:) compiles and routes action

    @Test func sendWithAnimation() {
        let store = Store(initialState: AnimSendFeature.State()) {
            AnimSendFeature()
        }
        let sender = AnimSender(store: store)

        sender.send(.tapped, animation: .default)
        #expect(store.withState(\.count) == 1)
    }

    // MARK: SC-1: send(_:transaction:) compiles and routes action

    @Test func sendWithTransaction() {
        let store = Store(initialState: AnimSendFeature.State()) {
            AnimSendFeature()
        }
        let sender = AnimSender(store: store)

        sender.send(.tapped, transaction: Transaction())
        #expect(store.withState(\.count) == 1)
    }

    // MARK: SC-1: send(_:animation:) with nil animation

    @Test func sendWithNilAnimation() {
        let store = Store(initialState: AnimSendFeature.State()) {
            AnimSendFeature()
        }
        let sender = AnimSender(store: store)

        sender.send(.tapped, animation: nil)
        #expect(store.withState(\.count) == 1)
    }

    // MARK: SC-1: plain send still works alongside animation overloads

    @Test func plainSendStillWorks() {
        let store = Store(initialState: AnimSendFeature.State()) {
            AnimSendFeature()
        }
        let sender = AnimSender(store: store)

        sender.send(.tapped)
        #expect(store.withState(\.count) == 1)

        sender.send(.tapped, animation: .default)
        #expect(store.withState(\.count) == 2)
    }
}
#endif
#endif
