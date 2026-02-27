import ComposableArchitecture
import IdentifiedCollections
import Sharing
import SwiftUI

// MARK: - TodosFeature Reducer

@Reducer
struct TodosFeature {
    @Reducer
    enum Destination {
        case confirmationDialog(ConfirmationDialogState<ConfirmationDialog>)

        @CasePathable
        enum ConfirmationDialog: Equatable {
            case sortByTitle
            case sortByDate
            case sortByStatus
        }
    }

    @ObservableState
    struct State: Equatable {
        var todos: IdentifiedArrayOf<Todo> = []
        var filter: Filter = .all
        @Presents var destination: Destination.State?
        @Shared(.savedTodos) var savedTodos: IdentifiedArrayOf<Todo> = []

        var filteredTodos: IdentifiedArrayOf<Todo> {
            switch filter {
            case .all: return todos
            case .active: return todos.filter { !$0.isComplete }
            case .completed: return todos.filter { $0.isComplete }
            }
        }

        var completedCount: Int {
            todos.filter(\.isComplete).count
        }

        @CasePathable
        enum Filter: String, CaseIterable, Equatable {
            case all, active, completed
        }
    }

    @CasePathable
    enum Action {
        case addButtonTapped
        case toggleTodo(Todo.ID)
        case filterChanged(State.Filter)
        case deleteSwiped(IndexSet)
        case destination(PresentationAction<Destination.Action>)
        case sortButtonTapped
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                let newTodo = Todo(
                    id: uuid(),
                    title: "New Todo",
                    isComplete: false,
                    createdAt: date.now
                )
                state.todos.append(newTodo)
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case let .toggleTodo(id):
                state.todos[id: id]?.isComplete.toggle()
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case let .filterChanged(filter):
                state.filter = filter
                return .none

            case let .deleteSwiped(indexSet):
                for id in indexSet.map({ state.filteredTodos[$0].id }) {
                    state.todos.remove(id: id)
                }
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case .sortButtonTapped:
                state.destination = .confirmationDialog(
                    ConfirmationDialogState {
                        TextState("Sort Todos")
                    } actions: {
                        ButtonState(action: .sortByTitle) { TextState("By Title") }
                        ButtonState(action: .sortByDate) { TextState("By Date") }
                        ButtonState(action: .sortByStatus) { TextState("By Status") }
                        ButtonState(role: .cancel) { TextState("Cancel") }
                    }
                )
                return .none

            case .destination(.presented(.confirmationDialog(.sortByTitle))):
                state.todos.sort { $0.title < $1.title }
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case .destination(.presented(.confirmationDialog(.sortByDate))):
                state.todos.sort { $0.createdAt < $1.createdAt }
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case .destination(.presented(.confirmationDialog(.sortByStatus))):
                state.todos.sort { !$0.isComplete && $1.isComplete }
                state.$savedTodos.withLock { $0 = state.todos }
                return .none

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - TodosView

struct TodosView: View {
    @Bindable var store: StoreOf<TodosFeature>

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $store.filter.sending(\.filterChanged)) {
                    ForEach(TodosFeature.State.Filter.allCases, id: \.self) { filter in
                        Text(filter.rawValue.capitalized).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(store.filteredTodos) { todo in
                    TodoRowView(todo: todo) {
                        store.send(.toggleTodo(todo.id))
                    }
                }
                .onDelete { indexSet in
                    store.send(.deleteSwiped(indexSet))
                }
            }

            Section {
                HStack { Text("Completed"); Spacer(); Text("\(store.completedCount)/\(store.todos.count)").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Todos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.send(.addButtonTapped) } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { store.send(.sortButtonTapped) } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .confirmationDialog($store.scope(state: \.destination?.confirmationDialog, action: \.destination.confirmationDialog))
    }
}

// MARK: - TodoRowView

struct TodoRowView: View {
    let todo: Todo
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isComplete ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(todo.isComplete ? "Completed" : "Not completed")
            .accessibilityAddTraits(.isToggle)

            Text(todo.title)
                .strikethrough(todo.isComplete)
                .foregroundStyle(todo.isComplete ? .secondary : .primary)
        }
    }
}

extension TodosFeature.Destination.State: Equatable {}
