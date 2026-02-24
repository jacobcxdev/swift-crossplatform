#if !SKIP
import ComposableArchitecture
import SwiftUI
import Testing

// MARK: - Reducers

@Reducer
enum StackFeaturePath {
    case detail(DetailRow)
}

@Reducer
struct StackFeature {
    @ObservableState
    struct State {
        var path = StackState<StackFeaturePath.State>()
    }
    enum Action {
        case path(StackActionOf<StackFeaturePath>)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in .none }
            .forEach(\.path, action: \.path)
    }
}

@Reducer
struct DetailRow {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var title: String
    }
    enum Action {
        case titleChanged(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .titleChanged(title):
                state.title = title
                return .none
            }
        }
    }
}

@Reducer
struct PresentFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var child: ChildSheet.State?
    }
    enum Action {
        case child(PresentationAction<ChildSheet.Action>)
        case showChild
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showChild:
                state.child = ChildSheet.State(text: "")
                return .none
            case .child:
                return .none
            }
        }
        .ifLet(\.$child, action: \.child) {
            ChildSheet()
        }
    }
}

@Reducer
struct ChildSheet {
    @ObservableState
    struct State: Equatable {
        var text: String
    }
    enum Action {
        case setText(String)
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .setText(text):
                state.text = text
                return .none
            }
        }
    }
}

@Reducer
struct AlertFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var dialog: ConfirmationDialogState<Action.Dialog>?
    }
    enum Action {
        case alert(PresentationAction<Alert>)
        case dialog(PresentationAction<Dialog>)
        case showAlert
        case showDialog

        enum Alert: Equatable {
            case confirmDelete
        }
        enum Dialog: Equatable {
            case optionA, optionB
        }
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .showAlert:
                state.alert = AlertState {
                    TextState("Alert")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                }
                return .none
            case .showDialog:
                state.dialog = ConfirmationDialogState {
                    TextState("Dialog")
                } actions: {
                    ButtonState(action: .optionA) { TextState("A") }
                    ButtonState(action: .optionB) { TextState("B") }
                }
                return .none
            case .alert, .dialog:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$dialog, action: \.dialog)
    }
}

@Reducer
struct DismissChild {
    @ObservableState
    struct State: Equatable {}
    @Dependency(\.dismiss) var dismiss
    enum Action {
        case doneTapped
    }
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .doneTapped:
                return .run { _ in await self.dismiss() }
            }
        }
    }
}

@Reducer
struct EphemeralParent {
    @ObservableState
    struct State {
        @Presents var destination: Destination.State?
    }
    enum Action {
        case destination(PresentationAction<Destination.Action>)
        case presentChild
        case presentAlert
    }
    @Reducer
    enum Destination {
        @ReducerCaseEphemeral
        case alert(AlertState<AlertAction>)
        @ReducerCaseIgnored
        case ignored
        case child(DismissChild)
    }
    enum AlertAction: Equatable { case ok }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .presentChild:
                state.destination = .child(DismissChild.State())
                return .none
            case .presentAlert:
                state.destination = .alert(AlertState { TextState("Hi") })
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - Tests

@MainActor
struct NavigationTests {

    // MARK: - StackState / StackAction (TCA-32, TCA-33)

    @Test
    func testStackStateInitAndAppend() {
        var stack = StackState<DetailRow.State>()
        stack.append(DetailRow.State(id: UUID(0), title: "First"))

        #expect(stack.count == 1)
        #expect(stack.first?.title == "First")
    }

    @Test
    func testStackStateRemoveLast() {
        var stack = StackState<DetailRow.State>()
        stack.append(DetailRow.State(id: UUID(0), title: "1"))
        stack.append(DetailRow.State(id: UUID(1), title: "2"))
        stack.append(DetailRow.State(id: UUID(2), title: "3"))

        #expect(stack.count == 3)
        stack.removeLast()
        #expect(stack.count == 2)
        #expect(stack.last?.title == "2")
    }

    @Test
    func testStackActionForEachRouting() async {
        // Use Store (not TestStore) — StackFeature.State is not Equatable due to @Reducer enum Path
        let store = Store(initialState: StackFeature.State()) { StackFeature() }

        store.send(.path(.push(id: 0, state: .detail(DetailRow.State(id: UUID(0), title: "Init")))))
        #expect(store.state.path.count == 1)

        store.send(.path(.element(id: 0, action: .detail(.titleChanged("Updated")))))
        #expect(store.state.path[id: 0, case: \.detail]?.title == "Updated")

        store.send(.path(.popFrom(id: 0)))
        #expect(store.state.path.count == 0)
    }

    // MARK: - PresentationReducer (TCA-27, TCA-28, NAV-14)

    @Test
    func testPresentsOptionalLifecycle() async {
        let store = TestStore(initialState: PresentFeature.State()) {
            PresentFeature()
        }

        await store.send(.showChild) {
            $0.child = ChildSheet.State(text: "")
        }

        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    @Test
    func testPresentationActionDismissNilsState() async {
        let store = TestStore(initialState: PresentFeature.State(child: ChildSheet.State(text: "Initial"))) {
            PresentFeature()
        }

        await store.send(.child(.dismiss)) {
            $0.child = nil
        }
    }

    @Test
    func testChildMutationThroughPresentation() async {
        let store = TestStore(initialState: PresentFeature.State(child: ChildSheet.State(text: "Initial"))) {
            PresentFeature()
        }

        await store.send(.child(.presented(.setText("Updated")))) {
            $0.child?.text = "Updated"
        }
    }

    // MARK: - AlertState / ConfirmationDialogState (NAV-09, NAV-10, NAV-11)

    @Test
    func testAlertStateCreation() {
        let alert = AlertState<AlertFeature.Action.Alert>(
            title: TextState("Title"),
            message: TextState("Message"),
            buttons: [
                ButtonState(role: .destructive, action: .confirmDelete) {
                    TextState("Delete")
                },
                ButtonState(role: .cancel) {
                    TextState("Cancel")
                },
            ]
        )

        #expect(String(customDumping: alert).contains("Title"))
        #expect(String(customDumping: alert).contains("Message"))
        #expect(String(customDumping: alert).contains("Delete"))
    }

    @Test
    func testAlertAutoDismissal() async {
        let store = TestStore(initialState: AlertFeature.State()) {
            AlertFeature()
        }

        await store.send(.showAlert) {
            $0.alert = AlertState {
                TextState("Alert")
            } actions: {
                ButtonState(role: .destructive, action: .confirmDelete) { TextState("Delete") }
                ButtonState(role: .cancel) { TextState("Cancel") }
            }
        }

        // Confirms _EphemeralState conformance — auto-dismiss after button tap
        await store.send(.alert(.presented(.confirmDelete))) {
            $0.alert = nil
        }
    }

    @Test
    func testDialogAutoDismissal() async {
        let store = TestStore(initialState: AlertFeature.State()) {
            AlertFeature()
        }

        await store.send(.showDialog) {
            $0.dialog = ConfirmationDialogState {
                TextState("Dialog")
            } actions: {
                ButtonState(action: .optionA) { TextState("A") }
                ButtonState(action: .optionB) { TextState("B") }
            }
        }

        await store.send(.dialog(.presented(.optionA))) {
            $0.dialog = nil
        }
    }

    // MARK: - AlertState.map / ConfirmationDialogState.map (NAV-12, NAV-13)

    @Test
    func testAlertStateMap() {
        let alertInt = AlertState<Int> {
            TextState("MapTest")
        } actions: {
            ButtonState(action: 1) { TextState("One") }
        }

        let alertString: AlertState<String> = alertInt.map { "\($0)" }

        #expect(String(customDumping: alertString).contains("MapTest"))
    }

    @Test
    func testConfirmationDialogStateMap() {
        let dialogInt = ConfirmationDialogState<Int> {
            TextState("DialogMap")
        } actions: {
            ButtonState(action: 1) { TextState("One") }
            ButtonState(action: 2) { TextState("Two") }
        }

        let dialogString: ConfirmationDialogState<String> = dialogInt.map { "\($0)" }

        #expect(String(customDumping: dialogString).contains("DialogMap"))
    }

    // MARK: - Dismiss Dependency (TCA-26)

    @Test
    func testDismissDependencyResolvesAndExecutes() async {
        let dismissed = LockIsolated(false)

        let store = TestStore(initialState: DismissChild.State()) {
            DismissChild()
        } withDependencies: {
            $0.dismiss = DismissEffect { dismissed.setValue(true) }
        }

        await store.send(.doneTapped)
        #expect(dismissed.value == true)
    }

    @Test
    func testDismissDependencyWithPresentation() async {
        // Use Store (not TestStore) — EphemeralParent.State not Equatable
        let store = Store(initialState: EphemeralParent.State()) { EphemeralParent() }

        store.send(.presentChild)
        #expect(store.state.destination != nil)

        #expect(store.state.destination?.is(\.child) == true)
    }

    // MARK: - CaseKeyPath (NAV-15)

    @Test
    func testCaseKeyPathExtraction() {
        let path: StackFeaturePath.State = .detail(DetailRow.State(id: UUID(0), title: "Initial"))

        #expect(path.is(\.detail))

        var mutablePath = path
        mutablePath.modify(\.detail) { $0.title = "Updated" }
        #expect(mutablePath[case: \.detail]?.title == "Updated")
    }

    @Test
    func testCaseKeyPathSetterSubscript() {
        var path: StackFeaturePath.State = .detail(DetailRow.State(id: UUID(0), title: "Init"))

        path[case: \.detail] = DetailRow.State(id: UUID(0), title: "Set")
        #expect(path[case: \.detail]?.title == "Set")
    }

    // MARK: - @ReducerCaseEphemeral / @ReducerCaseIgnored (TCA-34, TCA-35)

    @Test
    func testReducerCaseEphemeral() async {
        // Use Store — EphemeralParent.State not Equatable
        let store = Store(initialState: EphemeralParent.State()) { EphemeralParent() }

        store.send(.presentAlert)
        #expect(store.state.destination != nil)

        store.send(.destination(.presented(.alert(.ok))))
        // _EphemeralState conformance auto-nils after button action
        #expect(store.state.destination == nil)
    }

    @Test
    func testReducerCaseIgnored() {
        // @ReducerCaseIgnored compiles and the case is excluded from body synthesis
        let state: EphemeralParent.Destination.State = .ignored
        #expect(state.is(\.ignored))
    }
}
#endif
