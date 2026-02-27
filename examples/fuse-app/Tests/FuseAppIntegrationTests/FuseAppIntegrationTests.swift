#if !SKIP
import ComposableArchitecture
import Foundation
import SQLiteData
import Testing
@testable import FuseApp

// MARK: - CounterFeature Integration Tests

@Suite(.serialized) @MainActor
struct CounterFeatureTests {

    @Test func increment() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        await store.send(.view(.incrementButtonTapped)) {
            $0.count = 1
            $0.fact = nil
            $0.totalChanges = 1
        }
    }

    @Test func decrement() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        }
        await store.send(.view(.decrementButtonTapped)) {
            $0.count = -1
            $0.fact = nil
            $0.totalChanges = 1
        }
    }

    @Test func delayedIncrement() async {
        let clock = TestClock()
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.continuousClock = clock
        }
        await store.send(.view(.delayedIncrementButtonTapped))
        await clock.advance(by: .seconds(1))
        await store.receive(\.incrementResponse) {
            $0.count = 1
            $0.totalChanges = 1
        }
    }

    @Test func factRequest() async {
        let store = TestStore(initialState: CounterFeature.State()) {
            CounterFeature()
        } withDependencies: {
            $0.numberFact.fetch = { _ in "Test fact" }
        }
        await store.send(.view(.factButtonTapped)) {
            $0.isLoadingFact = true
            $0.fact = nil
        }
        await store.receive(\.factResponse.success) {
            $0.isLoadingFact = false
            $0.fact = "Test fact"
            $0.totalChanges = 1
        }
    }

    @Test func reset() async {
        var state = CounterFeature.State()
        state.count = 5
        state.fact = "Some fact"
        let store = TestStore(initialState: state) {
            CounterFeature()
        }
        await store.send(.view(.resetButtonTapped)) {
            $0.count = 0
            $0.fact = nil
            $0.isLoadingFact = false
            $0.totalChanges = 1
        }
    }
}

// MARK: - TodosFeature Integration Tests

@Suite(.serialized) @MainActor
struct TodosFeatureTests {

    @Test func addTodo() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: TodosFeature.State()) {
            TodosFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
            $0.date = .constant(testDate)
        }
        await store.send(.addButtonTapped) {
            let newTodo = Todo(id: testUUID, title: "New Todo", isComplete: false, createdAt: testDate)
            $0.todos.append(newTodo)
            $0.$savedTodos.withLock { $0 = [newTodo] }
        }
        #expect(store.state.todos.count == 1)
    }

    @Test func toggleTodo() async {
        let todo = Todo(id: UUID(), title: "Test", isComplete: false, createdAt: .distantPast)
        let store = TestStore(initialState: TodosFeature.State(todos: [todo])) {
            TodosFeature()
        }
        await store.send(.toggleTodo(todo.id)) {
            $0.todos[id: todo.id]?.isComplete = true
            let expected = $0.todos
            $0.$savedTodos.withLock { $0 = expected }
        }
    }

    @Test func deleteSwiped() async {
        let todo = Todo(id: UUID(), title: "Delete me", createdAt: .distantPast)
        let store = TestStore(initialState: TodosFeature.State(todos: [todo])) {
            TodosFeature()
        }
        await store.send(.deleteSwiped(IndexSet(integer: 0))) {
            $0.todos = []
            $0.$savedTodos.withLock { $0 = [] }
        }
    }

    @Test func filter() async {
        let todo1 = Todo(id: UUID(), title: "Active", isComplete: false, createdAt: .distantPast)
        let todo2 = Todo(id: UUID(), title: "Done", isComplete: true, createdAt: .distantPast)
        let store = TestStore(initialState: TodosFeature.State(todos: [todo1, todo2])) {
            TodosFeature()
        }
        await store.send(.filterChanged(.completed)) {
            $0.filter = .completed
        }
        #expect(store.state.filteredTodos.count == 1)
        #expect(store.state.filteredTodos.first?.title == "Done")
    }

    @Test func sortConfirmationDialog() async {
        let store = TestStore(initialState: TodosFeature.State()) {
            TodosFeature()
        }
        await store.send(.sortButtonTapped) {
            $0.destination = .confirmationDialog(
                ConfirmationDialogState {
                    TextState("Sort Todos")
                } actions: {
                    ButtonState(action: .sortByTitle) { TextState("By Title") }
                    ButtonState(action: .sortByDate) { TextState("By Date") }
                    ButtonState(action: .sortByStatus) { TextState("By Status") }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                }
            )
        }
    }

    @Test func sortByTitle() async {
        let todoB = Todo(id: UUID(), title: "Banana", createdAt: .distantPast)
        let todoA = Todo(id: UUID(), title: "Apple", createdAt: .distantPast)
        let store = TestStore(initialState: TodosFeature.State(todos: [todoB, todoA])) {
            TodosFeature()
        }
        store.exhaustivity = .off
        await store.send(.sortButtonTapped)
        await store.send(.destination(.presented(.confirmationDialog(.sortByTitle)))) {
            $0.destination = nil
            $0.todos = [todoA, todoB]
            $0.$savedTodos.withLock { $0 = [todoA, todoB] }
        }
    }

    @Test func sortByDate() async {
        let older = Todo(id: UUID(), title: "Older", createdAt: Date(timeIntervalSince1970: 100))
        let newer = Todo(id: UUID(), title: "Newer", createdAt: Date(timeIntervalSince1970: 200))
        let store = TestStore(initialState: TodosFeature.State(todos: [newer, older])) {
            TodosFeature()
        }
        store.exhaustivity = .off
        await store.send(.sortButtonTapped)
        await store.send(.destination(.presented(.confirmationDialog(.sortByDate)))) {
            $0.destination = nil
            $0.todos = [older, newer]
            $0.$savedTodos.withLock { $0 = [older, newer] }
        }
    }

    @Test func sortByStatus() async {
        let done = Todo(id: UUID(), title: "Done", isComplete: true, createdAt: .distantPast)
        let active = Todo(id: UUID(), title: "Active", isComplete: false, createdAt: .distantPast)
        let store = TestStore(initialState: TodosFeature.State(todos: [done, active])) {
            TodosFeature()
        }
        store.exhaustivity = .off
        await store.send(.sortButtonTapped)
        await store.send(.destination(.presented(.confirmationDialog(.sortByStatus)))) {
            $0.destination = nil
            $0.todos = [active, done]
            $0.$savedTodos.withLock { $0 = [active, done] }
        }
    }

    @Test func savedTodosSyncOnMutation() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: TodosFeature.State()) {
            TodosFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
            $0.date = .constant(testDate)
        }
        let newTodo = Todo(id: testUUID, title: "New Todo", isComplete: false, createdAt: testDate)
        await store.send(.addButtonTapped) {
            $0.todos.append(newTodo)
            $0.$savedTodos.withLock { $0 = [newTodo] }
        }
        #expect(store.state.savedTodos.count == 1)
    }
}

// MARK: - ContactsFeature Integration Tests

@Suite(.serialized) @MainActor
struct ContactsFeatureTests {

    @Test func onAppearLoadsContacts() async {
        let testUUIDs = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        ]
        let counter = LockIsolated(0)
        let store = TestStore(initialState: ContactsFeature.State()) {
            ContactsFeature()
        } withDependencies: {
            $0.uuid = .init {
                let i = counter.value
                counter.withValue { $0 += 1 }
                return testUUIDs[i]
            }
        }
        await store.send(.viewAppeared) {
            $0.contacts = [
                Contact(id: testUUIDs[0], name: "Alice", email: "alice@example.com"),
                Contact(id: testUUIDs[1], name: "Bob", email: "bob@example.com"),
                Contact(id: testUUIDs[2], name: "Charlie", email: "charlie@example.com"),
            ]
        }
    }

    @Test func viewAppearedDoesNotReseedWhenContactsExist() async {
        let existing = Contact(id: UUID(), name: "Existing", email: "e@e.com")
        let store = TestStore(initialState: ContactsFeature.State(contacts: [existing])) {
            ContactsFeature()
        }
        await store.send(.viewAppeared)
        #expect(store.state.contacts.count == 1)
        #expect(store.state.contacts.first?.name == "Existing")
    }

    @Test func pushContactDetail() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(initialState: ContactsFeature.State(contacts: [contact])) {
            ContactsFeature()
        }
        await store.send(.contactTapped(contact)) {
            $0.path.append(.detail(ContactDetailFeature.State(contact: contact)))
        }
    }

    @Test func addContactSheet() async {
        let store = TestStore(initialState: ContactsFeature.State()) {
            ContactsFeature()
        }
        await store.send(.addButtonTapped) {
            $0.destination = .addContact(AddContactFeature.State())
        }
    }

    @Test func addContactSaveAndDismiss() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let newContact = Contact(id: testUUID, name: "Dave", email: "dave@example.com")
        let store = TestStore(
            initialState: ContactsFeature.State(
                destination: .addContact(AddContactFeature.State(name: "Dave", email: "dave@example.com"))
            )
        ) {
            ContactsFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
        }
        await store.send(.destination(.presented(.addContact(.delegate(.saveContact(newContact)))))) {
            $0.contacts.append(newContact)
        }
        await store.receive(\.destination.dismiss) {
            $0.destination = nil
        }
    }
}

// MARK: - ContactDetailFeature Integration Tests

@Suite(.serialized) @MainActor
struct ContactDetailFeatureTests {

    @Test func editButtonPresentsSheet() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(initialState: ContactDetailFeature.State(contact: contact)) {
            ContactDetailFeature()
        }
        await store.send(.editButtonTapped) {
            $0.destination = .editSheet(EditContactFeature.State(contact: contact))
        }
    }

    @Test func deleteButtonPresentsConfirmationDialog() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(initialState: ContactDetailFeature.State(contact: contact)) {
            ContactDetailFeature()
        }
        await store.send(.deleteButtonTapped) {
            $0.destination = .confirmationDialog(
                ConfirmationDialogState {
                    TextState("Contact Actions")
                } actions: {
                    ButtonState(action: .edit) { TextState("Edit") }
                    ButtonState(role: .destructive, action: .delete) { TextState("Delete") }
                    ButtonState(role: .cancel) { TextState("Cancel") }
                }
            )
        }
    }

    @Test func deleteConfirmation() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(
            initialState: ContactDetailFeature.State(
                contact: contact,
                destination: .alert(AlertState {
                    TextState("Delete Alice?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDeletion) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState("This cannot be undone.")
                })
            )
        ) {
            ContactDetailFeature()
        }
        await store.send(.destination(.presented(.alert(.confirmDeletion)))) {
            $0.destination = nil
        }
        await store.receive(\.delegate.deleteContact)
    }

    @Test func editSavesContact() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let updated = Contact(id: contact.id, name: "Alice Updated", email: "alice2@example.com")
        let store = TestStore(
            initialState: ContactDetailFeature.State(
                contact: contact,
                destination: .editSheet(EditContactFeature.State(contact: updated))
            )
        ) {
            ContactDetailFeature()
        }
        await store.send(.destination(.presented(.editSheet(.delegate(.save(updated)))))) {
            $0.contact = updated
        }
        await store.receive(\.destination.dismiss) {
            $0.destination = nil
        }
    }
}

// MARK: - AddContactFeature Integration Tests

@Suite(.serialized) @MainActor
struct AddContactFeatureTests {

    @Test func bindingChanges() async {
        let store = TestStore(initialState: AddContactFeature.State()) {
            AddContactFeature()
        }
        await store.send(.binding(.set(\.name, "Dave"))) {
            $0.name = "Dave"
        }
        await store.send(.binding(.set(\.email, "dave@example.com"))) {
            $0.email = "dave@example.com"
        }
    }

    @Test func cancelDismisses() async {
        let store = TestStore(initialState: AddContactFeature.State()) {
            AddContactFeature()
        }
        await store.send(.cancelButtonTapped)
    }

    @Test func saveCreatesContact() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let store = TestStore(initialState: AddContactFeature.State(name: "Dave", email: "dave@example.com")) {
            AddContactFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
        }
        await store.send(.saveButtonTapped)
        await store.receive(\.delegate.saveContact)
    }
}

// MARK: - EditContactFeature Integration Tests

@Suite(.serialized) @MainActor
struct EditContactFeatureTests {

    @Test func bindingChanges() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(initialState: EditContactFeature.State(contact: contact)) {
            EditContactFeature()
        }
        await store.send(.binding(.set(\.contact.name, "Bob"))) {
            $0.contact.name = "Bob"
        }
        await store.send(.binding(.set(\.contact.email, "bob@example.com"))) {
            $0.contact.email = "bob@example.com"
        }
    }

    @Test func cancelDismisses() async {
        let contact = Contact(id: UUID(), name: "Alice", email: "alice@example.com")
        let store = TestStore(initialState: EditContactFeature.State(contact: contact)) {
            EditContactFeature()
        }
        await store.send(.cancelButtonTapped)
    }

    @Test func saveEmitsDelegate() async {
        let contact = Contact(id: UUID(), name: "Updated", email: "updated@example.com")
        let store = TestStore(initialState: EditContactFeature.State(contact: contact)) {
            EditContactFeature()
        }
        await store.send(.saveButtonTapped)
        await store.receive(\.delegate.save)
    }
}

// MARK: - DatabaseFeature Integration Tests

@Suite(.serialized) @MainActor
struct DatabaseFeatureTests {

    private func createMigratedDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseFeature.registerMigrations(on: &migrator)
        try migrator.migrate(db)
        return db
    }

    @Test func addNote() async throws {
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let db = try createMigratedDatabase()
        let store = TestStore(initialState: DatabaseFeature.State()) {
            DatabaseFeature()
        } withDependencies: {
            $0.defaultDatabase = db
            $0.date = .constant(testDate)
        }
        store.exhaustivity = .off
        await store.send(.addButtonTapped)
        await store.receive(\.noteAdded) {
            $0.notes = [Note(id: 1, title: "New Note", body: "", category: "general", createdAt: testDate.timeIntervalSince1970)]
            $0.noteCount = 1
        }
    }

    @Test func deleteNote() async throws {
        let db = try createMigratedDatabase()
        try await db.write { db in
            try #sql(
                    """
                    INSERT INTO "notes" ("id", "title", "body", "category", "createdAt")
                    VALUES (\(bind: 42), \(bind: "Test"), \(bind: ""), \(bind: "general"), \(bind: 0.0))
                    """
                ).execute(db)
        }
        let note = Note(id: 42, title: "Test", body: "", category: "general", createdAt: 0)
        let store = TestStore(
            initialState: DatabaseFeature.State(notes: [note], noteCount: 1)
        ) {
            DatabaseFeature()
        } withDependencies: {
            $0.defaultDatabase = db
        }
        store.exhaustivity = .off
        await store.send(.deleteNote(42))
        await store.receive(\.noteDeleted) {
            $0.notes = []
            $0.noteCount = 0
        }
    }

    @Test func categoryFilter() async {
        let store = TestStore(initialState: DatabaseFeature.State()) {
            DatabaseFeature()
        }
        await store.send(.categoryFilterChanged("work")) {
            $0.selectedCategory = "work"
        }
    }
}

// MARK: - SettingsFeature Integration Tests

@Suite(.serialized) @MainActor
struct SettingsFeatureTests {

    @Test func userNameChange() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        await store.send(.userNameChanged("Alice")) {
            $0.$userName.withLock { $0 = "Alice" }
            $0.$settingsActionCount.withLock { $0 = 1 }
        }
    }

    @Test func appearanceChange() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        await store.send(.appearanceChanged("dark")) {
            $0.$appearance.withLock { $0 = "dark" }
            $0.$settingsActionCount.withLock { $0 = 1 }
        }
    }

    @Test func notificationsToggle() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        await store.send(.notificationsToggled(false)) {
            $0.$notificationsEnabled.withLock { $0 = false }
            $0.$settingsActionCount.withLock { $0 = 1 }
        }
    }

    @Test func resetToDefaults() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        await store.send(.userNameChanged("Alice")) {
            $0.$userName.withLock { $0 = "Alice" }
            $0.$settingsActionCount.withLock { $0 = 1 }
        }
        await store.send(.resetButtonTapped) {
            $0.$userName.withLock { $0 = "Skipper" }
            $0.$appearance.withLock { $0 = "" }
            $0.$notificationsEnabled.withLock { $0 = true }
            $0.$settingsActionCount.withLock { $0 = 2 }
        }
    }

    @Test func settingsActionCountIncrementsAcrossActions() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }
        await store.send(.userNameChanged("A")) {
            $0.$userName.withLock { $0 = "A" }
            $0.$settingsActionCount.withLock { $0 = 1 }
        }
        await store.send(.appearanceChanged("dark")) {
            $0.$appearance.withLock { $0 = "dark" }
            $0.$settingsActionCount.withLock { $0 = 2 }
        }
        await store.send(.notificationsToggled(false)) {
            $0.$notificationsEnabled.withLock { $0 = false }
            $0.$settingsActionCount.withLock { $0 = 3 }
        }
    }
}

// MARK: - AppFeature Integration Tests

@Suite(.serialized) @MainActor
struct AppFeatureTests {

    @Test func initialState() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        #expect(store.state.selectedTab == .counter)
        #expect(store.state.counter.count == 0)
        #expect(store.state.todos.todos.count == 0)
    }

    @Test func tabSwitching() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.tabSelected(.todos)) {
            $0.selectedTab = .todos
        }
        await store.send(.tabSelected(.contacts)) {
            $0.selectedTab = .contacts
        }
        await store.send(.tabSelected(.database)) {
            $0.selectedTab = .database
        }
        await store.send(.tabSelected(.settings)) {
            $0.selectedTab = .settings
        }
    }

    @Test func childStatePreservedOnTabSwitch() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.counter(.view(.incrementButtonTapped))) {
            $0.counter.count = 1
            $0.counter.totalChanges = 1
        }
        await store.send(.tabSelected(.todos)) {
            $0.selectedTab = .todos
        }
        await store.send(.tabSelected(.counter)) {
            $0.selectedTab = .counter
        }
        #expect(store.state.counter.count == 1)
    }

    @Test func childActionsRouteCorrectly() async {
        let testUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let testDate = Date(timeIntervalSince1970: 1_000_000)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.uuid = .constant(testUUID)
            $0.date = .constant(testDate)
        }
        let newTodo = Todo(id: testUUID, title: "New Todo", isComplete: false, createdAt: testDate)
        await store.send(.todos(.addButtonTapped)) {
            $0.todos.todos.append(newTodo)
            $0.todos.$savedTodos.withLock { $0 = [newTodo] }
        }
        #expect(store.state.todos.todos.count == 1)
    }
}
#endif
