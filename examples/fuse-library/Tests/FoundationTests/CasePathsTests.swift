import CasePaths
import Testing

@CasePathable
enum Action: Equatable {
    case increment
    case decrement
    case setText(String)
    case child(ChildAction)
}

@CasePathable
enum ChildAction: Equatable {
    case tap
    case setCount(Int)
}

// For EnumMetadata smoke test (must be at file scope for @CasePathable macro)
@CasePathable
enum TestEnum: Equatable {
    case a(Int)
    case b(String)
    case c
}

// CP-01: @CasePathable macro generates AllCasePaths and CaseKeyPath accessors
@Test func casePathableGeneratesAccessors() {
    let _: Action.AllCasePaths = Action.allCasePaths
    // Compilation success = macro generates AllCasePaths struct
}

// CP-02: .is(\.caseName) returns correct Bool
@Test func isCheck() {
    let action = Action.setText("hello")
    #expect(action.is(\.setText))
    #expect(!action.is(\.increment))
    #expect(!action.is(\.child))
}

// CP-03: .modify(\.caseName) mutates associated value in-place
@Test func modifyInPlace() {
    var action = Action.setText("hello")
    action.modify(\.setText) { $0 = "world" }
    // Verify via AnyCasePath extraction
    let path = AnyCasePath<Action, String>(\.setText)
    #expect(path.extract(from: action) == "world")
}

// CP-04: @dynamicMemberLookup dot-syntax returns Optional via AnyCasePath
@Test func casePathExtraction() {
    let action = Action.setText("hello")
    let setTextPath = AnyCasePath<Action, String>(\.setText)
    let incrementPath = AnyCasePath<Action, Void>(\.increment)
    #expect(setTextPath.extract(from: action) == "hello")
    #expect(incrementPath.extract(from: action) == nil)
}

// CP-05: allCasePaths static variable returns collection
@Test func allCasePathsCollection() {
    var count = 0
    for _ in Action.allCasePaths {
        count += 1
    }
    #expect(count == 4)  // increment, decrement, setText, child
}

// CP-06: CaseKeyPath subscript setter modifies matching case, AnyCasePath embeds
@Test func caseSubscriptAndEmbed() {
    // Subscript setter modifies value when case matches
    var mutable = Action.setText("original")
    mutable[case: \.setText] = "modified"
    let path = AnyCasePath<Action, String>(\.setText)
    #expect(path.extract(from: mutable) == "modified")

    // AnyCasePath embed creates new enum value
    let embedded = path.embed("embedded")
    #expect(embedded == .setText("embedded"))
}

// CP-07: Nested CasePathable for reducer enum pattern
@Test func nestedCasePathable() {
    let action = Action.child(.tap)
    #expect(action.is(\.child))

    // Extract nested value via AnyCasePath
    let childPath = AnyCasePath<Action, ChildAction>(\.child)
    let childAction = childPath.extract(from: action)
    #expect(childAction == .tap)
    #expect(childAction?.is(\.tap) == true)
}

// CP-08: AnyCasePath with custom embed/extract closures
@Test func anyCasePathCustomClosures() {
    let path = AnyCasePath<Action, String>(
        embed: { Action.setText($0) },
        extract: {
            guard case .setText(let value) = $0 else { return nil }
            return value
        }
    )
    #expect(path.extract(from: .setText("test")) == "test")
    #expect(path.extract(from: .increment) == nil)
    #expect(path.embed("embedded") == .setText("embedded"))
}

// EnumMetadata smoke test -- CRITICAL for TCA on Android
// TCA uses EnumMetadata in 6 core files. If this crashes, TCA needs rework.
@Test func enumMetadataABISmokeTest() {
    // Use the deprecated AnyCasePath(unsafe:) which goes through EnumMetadata
    // This exercises the same ABI pointer arithmetic TCA relies on

    // If EnumMetadata ABI is broken, these will crash (SIGBUS/SIGSEGV)
    let pathA = AnyCasePath<TestEnum, Int>(unsafe: { .a($0) })
    #expect(pathA.extract(from: .a(42)) == 42)
    #expect(pathA.extract(from: .b("x")) == nil)
    #expect(pathA.extract(from: .c) == nil)

    let pathB = AnyCasePath<TestEnum, String>(unsafe: { .b($0) })
    #expect(pathB.extract(from: .b("hello")) == "hello")
    #expect(pathB.extract(from: .a(1)) == nil)
}
