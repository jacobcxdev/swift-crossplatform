#if !SKIP
import ComposableArchitecture
import Testing

// MARK: - Sheet Child Reducer

@Reducer
struct SheetChildFeature {
    @ObservableState
    struct State: Equatable {
        var count: Int = 0
    }
    enum Action {
        case increment
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}

// MARK: - Sheet Parent Reducer (NAV-05)

@Reducer
struct SheetParityFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var child: SheetChildFeature.State?
    }
    enum Action {
        case child(PresentationAction<SheetChildFeature.Action>)
        case presentSheet
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .presentSheet:
                state.child = SheetChildFeature.State()
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            SheetChildFeature()
        }
    }
}

// MARK: - FullScreenCover Parent Reducer (NAV-08)

@Reducer
struct FullScreenCoverParityFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var child: SheetChildFeature.State?
    }
    enum Action {
        case child(PresentationAction<SheetChildFeature.Action>)
        case presentCover
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .presentCover:
                state.child = SheetChildFeature.State()
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            SheetChildFeature()
        }
    }
}

// MARK: - Popover Parent Reducer (NAV-07)

@Reducer
struct PopoverParityFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var child: SheetChildFeature.State?
    }
    enum Action {
        case child(PresentationAction<SheetChildFeature.Action>)
        case presentPopover
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .presentPopover:
                state.child = SheetChildFeature.State()
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            SheetChildFeature()
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("Presentation Parity Tests")
struct PresentationParityTests {

    // MARK: - Sheet (NAV-05)

    @Test("Sheet: present -> child action -> dismiss lifecycle")
    func sheetPresentationLifecycle() async {
        let store = TestStore(initialState: SheetParityFeature.State()) {
            SheetParityFeature()
        }

        // Present sheet
        await store.send(.presentSheet) {
            $0.child = SheetChildFeature.State()
        }

        // Send child action through presentation
        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 1
        }

        // Dismiss sheet
        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    @Test("Sheet: multiple child interactions before dismiss")
    func sheetMultipleChildInteractions() async {
        let store = TestStore(initialState: SheetParityFeature.State()) {
            SheetParityFeature()
        }

        await store.send(.presentSheet) {
            $0.child = SheetChildFeature.State()
        }

        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 1
        }

        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 2
        }

        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    // MARK: - FullScreenCover (NAV-08)

    @Test("FullScreenCover: present -> child action -> dismiss lifecycle")
    func fullScreenCoverPresentationLifecycle() async {
        let store = TestStore(initialState: FullScreenCoverParityFeature.State()) {
            FullScreenCoverParityFeature()
        }

        // Present full screen cover
        await store.send(.presentCover) {
            $0.child = SheetChildFeature.State()
        }

        // Send child action through presentation
        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 1
        }

        // Dismiss full screen cover
        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    @Test("FullScreenCover: present and immediately dismiss")
    func fullScreenCoverPresentDismiss() async {
        let store = TestStore(initialState: FullScreenCoverParityFeature.State()) {
            FullScreenCoverParityFeature()
        }

        await store.send(.presentCover) {
            $0.child = SheetChildFeature.State()
        }

        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    // MARK: - Popover (NAV-07)

    @Test("Popover: present -> child action -> dismiss lifecycle (falls back to sheet on Android)")
    func popoverPresentationLifecycle() async {
        let store = TestStore(initialState: PopoverParityFeature.State()) {
            PopoverParityFeature()
        }

        // Present popover (sheet on Android)
        await store.send(.presentPopover) {
            $0.child = SheetChildFeature.State()
        }

        // Send child action through presentation
        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 1
        }

        // Dismiss popover
        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    @Test("Popover: multiple interactions then dismiss")
    func popoverMultipleInteractions() async {
        let store = TestStore(initialState: PopoverParityFeature.State()) {
            PopoverParityFeature()
        }

        await store.send(.presentPopover) {
            $0.child = SheetChildFeature.State()
        }

        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 1
        }

        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 2
        }

        await store.send(.child(.presented(.increment))) {
            $0.child?.count = 3
        }

        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }
}
#endif
