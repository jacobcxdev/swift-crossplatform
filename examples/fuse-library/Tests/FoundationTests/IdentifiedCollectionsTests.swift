#if !SKIP
import Foundation
import IdentifiedCollections
import Testing

struct User: Identifiable, Equatable, Codable {
    var id: Int
    var name: String
}

// IC-01: IdentifiedArrayOf initializes from array literal
@Test func initFromArrayLiteral() {
    let users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
        User(id: 3, name: "Charlie"),
    ]
    #expect(users.count == 3)
}

// IC-02: Subscript read by ID returns correct element in O(1)
@Test func subscriptReadByID() {
    let users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
    ]
    #expect(users[id: 1] == User(id: 1, name: "Alice"))
    #expect(users[id: 2]?.name == "Bob")
    #expect(users[id: 99] == nil)
}

// IC-03: Subscript write nil removes element
@Test func subscriptWriteNilRemoves() {
    var users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
    ]
    users[id: 1] = nil
    #expect(users.count == 1)
    #expect(users[id: 1] == nil)
    #expect(users[id: 2] != nil)
}

// IC-04: remove(id:) returns removed element
@Test func removeByID() {
    var users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
    ]
    let removed = users.remove(id: 1)
    #expect(removed == User(id: 1, name: "Alice"))
    #expect(users.count == 1)
}

// IC-05: ids property returns ordered set of all IDs
@Test func idsProperty() {
    let users: IdentifiedArrayOf<User> = [
        User(id: 3, name: "Charlie"),
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
    ]
    #expect(Array(users.ids) == [3, 1, 2])
}

// IC-06: Codable conformance when element is Codable
@Test func codableConformance() throws {
    let users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
        User(id: 2, name: "Bob"),
    ]
    let data = try JSONEncoder().encode(users)
    let decoded = try JSONDecoder().decode(IdentifiedArrayOf<User>.self, from: data)
    #expect(decoded == users)
}

// Additional: mutation via subscript
@Test func subscriptMutation() {
    var users: IdentifiedArrayOf<User> = [
        User(id: 1, name: "Alice"),
    ]
    users[id: 1]?.name = "Alicia"
    #expect(users[id: 1]?.name == "Alicia")
}
#endif
