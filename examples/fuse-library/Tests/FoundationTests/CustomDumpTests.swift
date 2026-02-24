#if !SKIP
import CustomDump
import Testing

struct DumpUser: Equatable, Sendable {
    var id: Int
    var name: String
    var email: String?
}

enum Status: Equatable {
    case active
    case inactive(reason: String)
}

// CD-01: customDump produces structured value representation
@Test func customDumpStructOutput() {
    let user = DumpUser(id: 1, name: "Blob", email: "blob@example.com")
    var output = ""
    customDump(user, to: &output)
    #expect(output.contains("DumpUser("))
    #expect(output.contains("id: 1"))
    #expect(output.contains("name: \"Blob\""))
    #expect(output.contains("blob@example.com"))
}

@Test func customDumpEnumOutput() {
    let status = Status.inactive(reason: "expired")
    var output = ""
    customDump(status, to: &output)
    #expect(output.contains("inactive"))
    #expect(output.contains("expired"))
}

@Test func customDumpCollectionOutput() {
    let numbers = [1, 2, 3]
    var output = ""
    customDump(numbers, to: &output)
    #expect(output.contains("1"))
    #expect(output.contains("2"))
    #expect(output.contains("3"))
}

@Test func customDumpOptionalNil() {
    let value: String? = nil
    var output = ""
    customDump(value, to: &output)
    #expect(output.contains("nil"))
}

// CD-02: String(customDumping:) creates string from value dump
@Test func stringCustomDumping() {
    let user = DumpUser(id: 1, name: "Blob", email: nil)
    let output = String(customDumping: user)
    #expect(output.contains("DumpUser("))
    #expect(output.contains("id: 1"))
    #expect(output.contains("name: \"Blob\""))
}

// CD-03: diff computes string diff between two values
@Test func diffDetectsChanges() {
    let user1 = DumpUser(id: 1, name: "Blob", email: nil)
    let user2 = DumpUser(id: 1, name: "Blob Jr.", email: "jr@example.com")
    let result = diff(user1, user2)
    #expect(result != nil)
    #expect(result!.contains("name"))
    #expect(result!.contains("Blob Jr."))
}

@Test func diffReturnsNilForEqualValues() {
    let user1 = DumpUser(id: 1, name: "Blob", email: nil)
    let user2 = DumpUser(id: 1, name: "Blob", email: nil)
    let result = diff(user1, user2)
    #expect(result == nil)
}

@Test func diffEnumChanges() {
    let s1 = Status.active
    let s2 = Status.inactive(reason: "expired")
    let result = diff(s1, s2)
    #expect(result != nil)
}

// CD-04: expectNoDifference asserts equality with diff output on failure
// Depends on reportIssue() working correctly (fixed in Plan 02-02)
@Test func expectNoDifferencePassesForEqualValues() {
    let user = DumpUser(id: 1, name: "Blob", email: nil)
    expectNoDifference(user, user)
    // Should pass without issue
}

@Test func expectNoDifferenceFailsForDifferentValues() {
    let user1 = DumpUser(id: 1, name: "Blob", email: nil)
    let user2 = DumpUser(id: 1, name: "Blob Jr.", email: nil)
    withKnownIssue {
        expectNoDifference(user1, user2)
    }
}

// CD-05: expectDifference asserts value changes after operation
@Test func expectDifferenceDetectsChanges() {
    var user = DumpUser(id: 1, name: "Blob", email: nil)
    expectDifference(user) {
        user.name = "Blob Jr."
    } changes: {
        $0.name = "Blob Jr."
    }
}

// Additional: Mirror-based output for nested types
@Test func customDumpNestedStruct() {
    struct Outer: Equatable {
        struct Inner: Equatable {
            var value: Int
        }
        var inner: Inner
        var label: String
    }
    let value = Outer(inner: .init(value: 42), label: "test")
    var output = ""
    customDump(value, to: &output)
    #expect(output.contains("Outer("))
    #expect(output.contains("inner:"))
    #expect(output.contains("value: 42"))
    #expect(output.contains("label: \"test\""))
}
#endif
