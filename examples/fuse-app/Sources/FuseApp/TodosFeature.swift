import ComposableArchitecture
import IdentifiedCollections
import SwiftUI

// MARK: - TodosFeature Reducer

@Reducer
struct TodosFeature {
    @ObservableState
    struct State: Equatable {
        var todos: IdentifiedArrayOf<Todo> = []
        var filter: Filter = .all
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var confirmationDialog: ConfirmationDialogState<Action.ConfirmationDialog>?
        var todoToDelete: Todo.ID?

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

    enum Action {
        case addButtonTapped
        case toggleTodo(Todo.ID)
        case filterChanged(State.Filter)
        case deleteTapped(Todo.ID)
        case alert(PresentationAction<Alert>)
        case confirmationDialog(PresentationAction<ConfirmationDialog>)
        case sortButtonTapped

        @CasePathable
        enum Alert {
            case confirmDeletion
        }

        @CasePathable
        enum ConfirmationDialog {
            case sortByTitle
            case sortByDate
            case sortByStatus
        }
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
                return .none

            case let .toggleTodo(id):
                state.todos[id: id]?.isComplete.toggle()
                return .none

            case let .filterChanged(filter):
                state.filter = filter
                return .none

            case let .deleteTapped(id):
                state.todoToDelete = id
                state.alert = AlertState {
                    TextState("Delete Todo?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeletion) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("This action cannot be undone.")
                }
                return .none

            case .alert(.presented(.confirmDeletion)):
                if let id = state.todoToDelete {
                    state.todos.remove(id: id)
                }
                state.todoToDelete = nil
                return .none

            case .alert(.dismiss):
                state.todoToDelete = nil
                return .none

            case .sortButtonTapped:
                state.confirmationDialog = ConfirmationDialogState {
                    TextState("Sort Todos")
                } actions: {
                    ButtonState(action: .sortByTitle) { TextState("By Title") }
                    ButtonState(action: .sortByDate) { TextState("By Date") }
                    ButtonState(action: .sortByStatus) { TextState("By Status") }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                }
                return .none

            case .confirmationDialog(.presented(.sortByTitle)):
                state.todos.sort { $0.title < $1.title }
                return .none

            case .confirmationDialog(.presented(.sortByDate)):
                state.todos.sort { $0.createdAt < $1.createdAt }
                return .none

            case .confirmationDialog(.presented(.sortByStatus)):
                state.todos.sort { !$0.isComplete && $1.isComplete }
                return .none

            case .confirmationDialog(.dismiss):
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
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
                    .swipeActions {
                        Button(role: .destructive) {
                            store.send(.deleteTapped(todo.id))
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Section {
                LabeledContent("Completed", value: "\(store.completedCount)/\(store.todos.count)")
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
        .alert($store.scope(state: \.alert, action: \.alert))
        .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
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

            Text(todo.title)
                .strikethrough(todo.isComplete)
                .foregroundStyle(todo.isComplete ? .secondary : .primary)
        }
    }
}
