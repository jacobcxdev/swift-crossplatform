import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Sharing
import SQLiteData
import StructuredQueriesSQLite

// MARK: - Todo Model

struct Todo: Equatable, Identifiable, Codable, Sendable {
    var id: UUID
    var title: String
    var isComplete: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String = "", isComplete: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

// MARK: - Contact Model

struct Contact: Equatable, Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var email: String

    init(id: UUID = UUID(), name: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.email = email
    }
}

// MARK: - Database Note Model (file-scope for @Table macro expansion)

@Table
struct Note: Equatable, Identifiable, Sendable {
    @Column(primaryKey: true)
    let id: Int64
    var title: String = ""
    var body: String = ""
    var category: String = "general"
    var createdAt: Double = 0
}

// MARK: - SharedKey Extensions

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var userName: Self { Self[.appStorage("userName"), default: "Skipper"] }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var appearance: Self { Self[.appStorage("appearance"), default: ""] }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    static var notificationsEnabled: Self { Self[.appStorage("notificationsEnabled"), default: true] }
}

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<Todo>>.Default {
    static var savedTodos: Self {
        Self[.fileStorage(URL.applicationSupportDirectory.appending(component: "todos.json")), default: []]
    }
}

extension SharedKey where Self == InMemoryKey<Int>.Default {
    static var sessionActionCount: Self { Self[.inMemory("sessionActionCount"), default: 0] }
}

// MARK: - Number Fact Dependency Client

@DependencyClient
struct NumberFactClient: Sendable {
    var fetch: @Sendable (Int) async throws -> String
}

extension NumberFactClient: DependencyKey {
    static var liveValue: Self {
        Self(fetch: { number in "The number \(number) is interesting!" })
    }
    static var testValue: Self { Self() }
    static var previewValue: Self {
        Self(fetch: { number in "Preview fact for \(number)" })
    }
}

extension DependencyValues {
    var numberFact: NumberFactClient {
        get { self[NumberFactClient.self] }
        set { self[NumberFactClient.self] = newValue }
    }
}
