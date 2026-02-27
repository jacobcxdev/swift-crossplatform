import ComposableArchitecture
import Foundation
import SwiftUI

#if os(Android)
import SkipAndroidBridge
@inline(__always)
private func navLog(_ msg: @autoclosure () -> String) {
    #if FUSE_NAV_DEBUG
    _navDebugLog(msg())
    #endif
}
#endif

// MARK: - ContactsFeaturePath

@Reducer
enum ContactsFeaturePath {
    case detail(ContactDetailFeature)
}

// MARK: - ContactsFeature Reducer (NavigationStack showcase)

@Reducer
struct ContactsFeature {
    @Reducer
    enum Destination {
        case addContact(AddContactFeature)
    }

    @ObservableState
    struct State: Equatable {
        var contacts: IdentifiedArrayOf<Contact> = []
        var path = StackState<ContactsFeaturePath.State>()
        @Presents var destination: Destination.State?
    }

    @CasePathable
    enum Action {
        case addButtonTapped
        case path(StackActionOf<ContactsFeaturePath>)
        case destination(PresentationAction<Destination.Action>)
        case contactTapped(Contact)
        case viewAppeared
    }

    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.destination = .addContact(AddContactFeature.State())
                return .none

            case let .contactTapped(contact):
                #if os(Android)
                navLog("ContactsFeature: .contactTapped, pathCount before=\(state.path.count)")
                #endif
                state.path.append(.detail(ContactDetailFeature.State(contact: contact)))
                return .none

            case .path(.element(let stackID, .detail(.delegate(.deleteContact(let contactID))))):
                state.contacts.remove(id: contactID)
                // Pop before any further path actions so the stack is consistent
                state.path.pop(from: stackID)
                return .none

            case .path:
                return .none

            case .destination(.presented(.addContact(.delegate(.saveContact(let contact))))):
                state.contacts.append(contact)
                return .send(.destination(.dismiss))

            case .destination:
                return .none

            case .viewAppeared:
                guard state.contacts.isEmpty else { return .none }
                state.contacts = [
                        Contact(id: uuid(), name: "Alice", email: "alice@example.com"),
                    Contact(id: uuid(), name: "Bob", email: "bob@example.com"),
                    Contact(id: uuid(), name: "Charlie", email: "charlie@example.com"),
                ]
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - ContactDetailFeature

@Reducer
struct ContactDetailFeature {
    @Reducer
    enum Destination {
        case editSheet(EditContactFeature)
        case alert(AlertState<Alert>)
        case confirmationDialog(ConfirmationDialogState<ConfirmationDialog>)

        @CasePathable
        enum Alert {
            case confirmDeletion
        }

        @CasePathable
        enum ConfirmationDialog {
            case edit
            case delete
        }
    }

    @ObservableState
    struct State: Equatable {
        var contact: Contact
        @Presents var destination: Destination.State?
    }

    @CasePathable
    enum Action {
        case editButtonTapped
        case deleteButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate {
            case deleteContact(Contact.ID)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .editButtonTapped:
                state.destination = .editSheet(EditContactFeature.State(contact: state.contact))
                return .none

            case .deleteButtonTapped:
                state.destination = .confirmationDialog(
                    ConfirmationDialogState {
                        TextState("Contact Actions")
                    } actions: {
                        ButtonState(action: .edit) { TextState("Edit") }
                        ButtonState(role: .destructive, action: .delete) { TextState("Delete") }
                        ButtonState(role: .cancel) { TextState("Cancel") }
                    }
                )
                return .none

            case .destination(.presented(.confirmationDialog(.edit))):
                state.destination = .editSheet(EditContactFeature.State(contact: state.contact))
                return .none

            case .destination(.presented(.confirmationDialog(.delete))):
                state.destination = .alert(
                    AlertState {
                        TextState("Delete \(state.contact.name)?")
                    } actions: {
                        ButtonState(role: .destructive, action: .confirmDeletion) {
                            TextState("Delete")
                        }
                        ButtonState(role: .cancel) {
                            TextState("Cancel")
                        }
                    } message: {
                        TextState("This cannot be undone.")
                    }
                )
                return .none

            case .destination(.presented(.alert(.confirmDeletion))):
                return .send(.delegate(.deleteContact(state.contact.id)))

            case .destination(.presented(.editSheet(.delegate(.save(let contact))))):
                state.contact = contact
                return .send(.destination(.dismiss))

            case .destination:
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

// MARK: - EditContactFeature

@Reducer
struct EditContactFeature {
    @ObservableState
    struct State: Equatable {
        var contact: Contact
    }

    @CasePathable
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate {
            case save(Contact)
        }
    }

    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .saveButtonTapped:
                return .send(.delegate(.save(state.contact)))
            case .cancelButtonTapped:
                return .run { _ in await dismiss() }
            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - AddContactFeature

@Reducer
struct AddContactFeature {
    @ObservableState
    struct State: Equatable {
        var name = ""
        var email = ""
    }

    @CasePathable
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate {
            case saveContact(Contact)
        }
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.dismiss) var dismiss

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .saveButtonTapped:
                let contact = Contact(id: uuid(), name: state.name, email: state.email)
                return .send(.delegate(.saveContact(contact)))
            case .cancelButtonTapped:
                return .run { _ in await dismiss() }
            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - ContactsView

struct ContactsView: View {
    @Bindable var store: StoreOf<ContactsFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            contactsList
        } destination: { store in
            switch store.case {
            case let .detail(detailStore):
                ContactDetailView(store: detailStore)
            }
        }
        .sheet(
            item: $store.scope(state: \.destination?.addContact, action: \.destination.addContact)
        ) { addStore in
            NavigationStack {
                AddContactView(store: addStore)
            }
        }
    }

    private var contactsList: some View {
        List {
            ForEach(store.contacts) { contact in
                Button { store.send(.contactTapped(contact)) } label: {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(contact.name)
                                .font(.headline)
                            Text(contact.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.send(.addButtonTapped) } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .onAppear { store.send(.viewAppeared) }
    }
}

// MARK: - ContactDetailView

struct ContactDetailView: View {
    @Bindable var store: StoreOf<ContactDetailFeature>

    var body: some View {
        List {
            Section("Info") {
                HStack { Text("Name"); Spacer(); Text(store.contact.name).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
                HStack { Text("Email"); Spacer(); Text(store.contact.email).foregroundStyle(.secondary) }
                    .accessibilityElement(children: .combine)
            }

            Section {
                Button("Edit") { store.send(.editButtonTapped) }
                Button("Actions...") { store.send(.deleteButtonTapped) }
            }
        }
        .navigationTitle(store.contact.name)
        .alert(
            $store.scope(state: \.destination?.alert, action: \.destination.alert)
        )
        .confirmationDialog(
            $store.scope(state: \.destination?.confirmationDialog, action: \.destination.confirmationDialog)
        )
        .sheet(
            item: $store.scope(state: \.destination?.editSheet, action: \.destination.editSheet)
        ) { editStore in
            NavigationStack {
                EditContactView(store: editStore)
            }
        }
    }
}

// MARK: - EditContactView

struct EditContactView: View {
    @Bindable var store: StoreOf<EditContactFeature>

    var body: some View {
        List {
            Section("Edit Contact") {
                TextField("Name", text: $store.contact.name)
                TextField("Email", text: $store.contact.email)
            }
        }
        .navigationTitle("Edit Contact")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.send(.saveButtonTapped) }
            }
        }
    }
}

// MARK: - AddContactView

struct AddContactView: View {
    @Bindable var store: StoreOf<AddContactFeature>

    var body: some View {
        List {
            Section("New Contact") {
                TextField("Name", text: $store.name)
                TextField("Email", text: $store.email)
            }
        }
        .navigationTitle("Add Contact")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { store.send(.cancelButtonTapped) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.send(.saveButtonTapped) }
                    .disabled(store.name.isEmpty)
            }
        }
    }
}

// MARK: - Equatable conformances for @Reducer enum generated State types

extension ContactsFeature.Destination.State: Equatable {}
extension ContactsFeaturePath.State: Equatable {}
extension ContactDetailFeature.Destination.State: Equatable {}

