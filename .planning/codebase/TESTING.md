# Testing Patterns

**Analysis Date:** 2026-02-20

## Test Framework

**Runner:**
- XCTest (Apple's native testing framework)
- Version: Swift 6.1 (from Package.swift declarations)
- Config: Implicit via Xcode/SPM; no separate config file

**Assertion Library:**
- XCTest assertions: `XCTAssertEqual()`, `XCTAssertTrue()`, `XCTAssertFalse()`, `XCTUnwrap()`

**Run Commands:**
```bash
swift test                    # Run all tests
swift test --filter "TestName"  # Run specific test
xcodebuild test               # Run via Xcode
```

**Skip-Specific Testing:**
- `SkipTest` framework for cross-platform tests (transpiled to JUnit/Robolectric on Android)
- `XCGradleHarness` protocol for Gradle integration tests
- Robolectric runner for local Android test execution

## Test File Organization

**Location:**
- Co-located by module: `Tests/{ModuleName}Tests/`
- Example: `examples/lite-app/Tests/LiteAppTests/`, `examples/fuse-app/Tests/FuseAppViewModelTests/`

**Naming:**
- Test classes: `{ModuleName}Tests` with `final` keyword
- Test functions: `test{Description}` in camelCase
- Skip-specific harness: `XCSkipTests` for Gradle integration
- Observation test: `ObservationTests` for @Observable tracking

**Structure:**
```
examples/{module-name}/
├── Tests/
│   ├── {ModuleName}Tests/
│   │   ├── {ModuleName}Tests.swift
│   │   ├── XCSkipTests.swift
│   │   └── Resources/
│   │       └── TestData.json
│   └── {ModuleName}ViewModelTests/
│       └── {ModuleName}ViewModelTests.swift
└── Sources/
```

## Test Structure

**Suite Organization:**
```swift
@available(macOS 13, *)
final class LiteAppTests: XCTestCase {
    func testLiteApp() throws {
        logger.log("running testLiteApp")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testDecodeType() throws {
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("LiteApp", testData.testModuleName)
    }
}
```

**Patterns:**

1. **Class Declaration:**
   - `final class {Name}Tests: XCTestCase` — prevents accidental subclassing
   - Availability guards for platform-specific tests: `@available(macOS 13, *)`, `@available(macOS 14, iOS 17, *)`

2. **Test Functions:**
   - `func test{Description}() throws` — all test methods can throw
   - Descriptive names that explain what's being tested
   - Single assertion per test function (preferred) or grouped related assertions

3. **Setup/Teardown:**
   - `override func setUp()` — called before each test (example: `FuseLibraryTests.swift` loads peer libraries)
   - `override func tearDown()` — called after each test (not commonly used in examples)

4. **Logger Declaration:**
   - File-level logger: `let logger: Logger = Logger(subsystem: "{Module}", category: "Tests")`
   - Logs test execution for debugging: `logger.log("running testLiteApp")`

## Test Structure - Observation Pattern

**Observable Testing with withObservationTracking:**
```swift
final class FuseAppViewModelTests: XCTestCase {
    private func makeViewModel() -> ViewModel {
        let vm = ViewModel()
        vm.items = [
            Item(title: "Alpha"),
            Item(title: "Beta"),
        ]
        return vm
    }

    func testViewModelItemsObservation() {
        let vm = makeViewModel()
        let flag = ObservationFlag()

        withObservationTracking {
            _ = vm.items  // Access tracked property
        } onChange: {
            flag.value = true  // Callback when property changes
        }

        vm.items.append(Item(title: "Test"))
        XCTAssertTrue(flag.value, "onChange should fire when items mutated")
        XCTAssertEqual(vm.items.count, 4)
    }
}
```

**Thread-Safety for Observation:**
```swift
/// Thread-safe flag for use in @Sendable onChange closures.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}
```

## Mocking

**Framework:**
- No third-party mocking library detected (Nimble, Quick, etc.)
- Manual mocking via factory functions and test doubles

**Patterns:**
```swift
// Factory function for creating test instances
private func makeViewModel() -> ViewModel {
    let vm = ViewModel()
    vm.items = [
        Item(title: "Alpha"),
        Item(title: "Beta"),
        Item(title: "Gamma"),
    ]
    return vm
}
```

**What to Mock:**
- Observable state objects (ViewModels) — set initial state manually
- File paths — use test data from `Resources/` directory
- Network requests — not tested in current examples

**What NOT to Mock:**
- Decodable structs — use actual JSON decoding with test data
- SwiftUI Views — tested via environment injection, not mocked
- Observable tracking — use `withObservationTracking` with real objects

## Fixtures and Factories

**Test Data:**
```swift
// From TestData.json
struct TestData : Codable, Hashable {
    var testModuleName: String
}

// In test:
let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
```

**Model Factories:**
```swift
// Item with defaults
let item = Item(id: id, date: date, favorite: true, title: "Test", notes: "Notes")

// Item with minimal setup
let item = Item(title: "Alpha")

// ViewModel with preset items
private func makeViewModel() -> ViewModel {
    let vm = ViewModel()
    vm.items = [Item(title: "Alpha"), Item(title: "Beta")]
    return vm
}
```

**Location:**
- Test data files in `Tests/{ModuleName}Tests/Resources/TestData.json`
- Factory functions defined in test class as private methods
- No separate fixtures directory; data embedded in test files

## Coverage

**Requirements:** Not enforced (no configuration detected)

**View Coverage:**
- All major views have visual tests through example instantiation
- Observable state changes verified with `withObservationTracking`

## Test Types

**Unit Tests:**
- **Scope:** Individual functions and properties
- **Approach:** Direct assertion of return values
- **Example from `LiteAppTests.swift`:**
  ```swift
  func testLiteApp() throws {
      XCTAssertEqual(1 + 2, 3, "basic test")
  }
  ```

**Observable/State Tests:**
- **Scope:** @Observable model changes and side effects
- **Approach:** Track property access with `withObservationTracking`, verify onChange fires
- **Example from `FuseAppViewModelTests.swift`:**
  ```swift
  func testViewModelClearObservation() {
      let vm = makeViewModel()
      let flag = ObservationFlag()

      withObservationTracking {
          _ = vm.items
      } onChange: {
          flag.value = true
      }

      vm.clear()
      XCTAssertTrue(flag.value, "onChange should fire when items cleared")
      XCTAssertTrue(vm.items.isEmpty)
  }
  ```

**Decoding/Serialization Tests:**
- **Scope:** JSON encoding/decoding and data persistence
- **Approach:** Load test data, decode to model, verify structure
- **Example from `LiteAppTests.swift`:**
  ```swift
  func testDecodeType() throws {
      let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
      let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
      XCTAssertEqual("LiteApp", testData.testModuleName)
  }
  ```

**Integration Tests (Skip/Gradle):**
- **Scope:** Transpiled Kotlin/Java code execution via Robolectric
- **Approach:** Run JUnit tests locally or on Android devices
- **Framework:** `SkipTest` with `XCGradleHarness`
- **Example from `XCSkipTests.swift`:**
  ```swift
  @available(macOS 13, macCatalyst 16, *)
  final class XCSkipTests: XCTestCase, XCGradleHarness {
      public func testSkipModule() async throws {
          try await runGradleTests()
      }
  }
  ```

**Async/Await Tests:**
- **Scope:** Asynchronous operations and throws
- **Approach:** Use `async throws` function signature
- **Example from `FuseLibraryTests.swift`:**
  ```swift
  func testAsyncThrowsFunction() async throws {
      let id = UUID()
      let type: FuseLibraryType = try await FuseLibraryModule.createFuseLibraryType(id: id, delay: 0.001)
      XCTAssertEqual(id, type.id)
  }
  ```

## Common Patterns

**Async Testing:**
```swift
func testAsyncThrowsFunction() async throws {
    let id = UUID()
    let type: FuseLibraryType = try await FuseLibraryModule.createFuseLibraryType(id: id, delay: 0.001)
    XCTAssertEqual(id, type.id)
}
```

**Error Testing:**
```swift
func testDecodeType() throws {
    let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
    let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
    XCTAssertEqual("LiteApp", testData.testModuleName)
}
```

**Property Testing:**
```swift
func testItemProperties() {
    let id = UUID()
    let date = Date.now
    let item = Item(id: id, date: date, favorite: true, title: "Test", notes: "Notes")

    XCTAssertEqual(item.id, id)

    let item2 = Item(id: id, date: date, favorite: true, title: "Test", notes: "Notes")
    XCTAssertEqual(item, item2)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try! encoder.encode(item)
    let decoded = try! decoder.decode(Item.self, from: data)
    XCTAssertEqual(decoded.id, item.id)
    XCTAssertEqual(decoded.title, item.title)
}
```

## Platform-Specific Testing

**macOS-Only Tests:**
- View model tests marked `@available(macOS 14, iOS 17, *)`
- Prevents running on platforms with immature Observable API
- Example: `FuseAppViewModelTests.swift` not run on Android

**Android-Only Setup:**
```swift
override func setUp() {
    #if os(Android)
    loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
    #endif
}
```

**Environment Detection:**
```swift
let isJava = ProcessInfo.processInfo.environment["java.io.tmpdir"] != nil
let isAndroid = isJava && ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil
let isRobolectric = isJava && !isAndroid
let is32BitInteger = Int64(Int.max) == Int64(Int32.max)
```

## Test Data

**Resources Directory:**
```
Tests/{ModuleName}Tests/
└── Resources/
    └── TestData.json
```

**Example TestData.json:**
```json
{
  "testModuleName": "LiteApp"
}
```

**Loading Test Data:**
```swift
let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
```

## Test Availability and Platform Guards

**Compiler Directives:**
```swift
#if os(macOS) || os(Linux)
import SkipTest
#endif

@available(macOS 13, *)
final class LiteAppTests: XCTestCase { ... }
```

**Conditional Compilation:**
```swift
#if canImport(OSLog)
import OSLog
let logger: Logger = Logger(subsystem: "FuseLibrary", category: "Tests")
#endif
```

---

*Testing analysis: 2026-02-20*
