# XCTest → Swift Testing Migration Risks
# Phase 8 — PFW Skill Alignment

Generated: 2026-02-23
Scope: fuse-library (91 tests) + fuse-app (30 tests) = 121 tests total

---

## Test File Inventory

All paths relative to repo root. Line counts and test counts are from source as read.

### fuse-library Tests

#### `examples/fuse-library/Tests/ObservationTests/FuseLibraryTests.swift`
- **Lines:** 38 | **Tests:** 2 | **Framework:** XCTest
- **Class:** `FuseLibraryTests: XCTestCase` (final, `@available(macOS 13, *)`)
- **Patterns:**
  - `override func setUp()` — loads peer library on Android via `loadPeerLibrary()`
  - `XCTAssertEqual` (2 sites)
  - `async throws` test method
  - `@testable import FuseLibrary`, `import SkipBridge`
  - No tearDown, no expectations, no continueAfterFailure
- **Special:** The `setUp` loads a native JNI library. This is platform-conditional (`#if os(Android)`). In Swift Testing there is no `setUp`; this must become an `init()` or a `.setUp` custom trait.

#### `examples/fuse-library/Tests/ObservationTests/ObservationTests.swift`
- **Lines:** 163 | **Tests:** 18 | **Framework:** XCTest
- **Class:** `ObservationTests: XCTestCase` (final, `@available(macOS 14, iOS 17, *)`)
- **Patterns:**
  - `override func setUp()` — loads peer library on Android
  - `XCTAssertEqual` (24 sites), `XCTAssertTrue` (4 sites), `XCTAssertNotEqual` (1 site)
  - All tests are synchronous (no `async`)
  - `import XCTest`, `import SkipBridge`, `@testable import FuseLibrary`
  - No tearDown, no expectations, no continueAfterFailure
- **Special:** `@available(macOS 14, iOS 17, *)` availability — Swift Testing handles this differently (no `@available` on `@Suite`; use `#available` guard inside test or skip trait).

#### `examples/fuse-library/Tests/ObservationTests/ObservationBridgeTests.swift`
- **Lines:** 288 | **Tests:** 9 | **Framework:** Swift Testing (already migrated)
- **Class:** `@Suite("Observation Bridge Semantics") struct ObservationBridgeTests`
- **Patterns (already Swift Testing):**
  - `@Test("description")` on all tests
  - `#expect(...)` throughout
  - `@MainActor` on one test
  - `async` tests with `withTaskGroup`, `try? await Task.sleep`
  - `#if !SKIP` guard wrapping entire file
  - File-scoped `@Observable` model types
- **No migration needed.** Serves as the reference implementation for this codebase.

#### `examples/fuse-library/Tests/ObservationTests/StressTests.swift`
- **Lines:** 168 | **Tests:** 2 | **Framework:** Swift Testing (already migrated)
- **Class:** `@Suite("Stress Tests", .tags(.stress)) struct StressTests`
- **Patterns (already Swift Testing):**
  - `@Tag` extension for `.stress`
  - `@MainActor` on one test
  - `async` tests
  - `#expect(...)` throughout
  - `print()` for metrics (flagged as LOW in audit — prefer `customDump`)
  - `#if !SKIP` guard
- **No migration needed.**

#### `examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift`
- **Lines:** 32 | **Tests:** 1 | **Framework:** XCTest
- **Class:** `XCSkipTests: XCTestCase, XCGradleHarness` (`@available(macOS 13, macCatalyst 16, *)`)
- **Patterns:**
  - `async throws` test — calls `runGradleTests()`
  - Skip/Gradle harness — not a regular test; it runs the transpiled JUnit suite
  - Guarded by `#if os(macOS) || os(Linux)`
  - File also defines `isJava`, `isAndroid`, `isRobolectric`, `is32BitInteger` globals
- **Special:** This is infrastructure, not a unit test. It must stay as XCTest because `XCGradleHarness` is an XCTest protocol from the Skip framework. It cannot be migrated to Swift Testing.

#### `examples/fuse-library/Tests/FoundationTests/CasePathsTests.swift`
- **Lines:** 122 | **Tests:** 9 | **Framework:** Swift Testing (already migrated)
- **Patterns (already Swift Testing):**
  - Free functions with `@Test` (no suite struct)
  - `#expect(...)` throughout
  - `import CasePaths`, `import Testing`
  - No `async` tests
- **No migration needed.**

#### `examples/fuse-library/Tests/FoundationTests/CustomDumpTests.swift`
- **Lines:** 126 | **Tests:** 11 | **Framework:** Swift Testing (already migrated)
- **Patterns (already Swift Testing):**
  - Free functions with `@Test` (no suite struct)
  - `#expect(...)`, `withKnownIssue { ... }` (2 sites)
  - `import CustomDump`, `import Testing`
  - No `async` tests (one `async` test: `withErrorReportingAsyncCatchesErrors`)
- **No migration needed.**

#### `examples/fuse-library/Tests/FoundationTests/IdentifiedCollectionsTests.swift`
- **Lines:** 83 | **Tests:** 7 | **Framework:** Swift Testing (already migrated)
- **Patterns (already Swift Testing):**
  - Free functions with `@Test`
  - `#expect(...)` throughout
  - `throws` on one test (`codableConformance`)
  - No `async` tests
- **No migration needed.**

#### `examples/fuse-library/Tests/FoundationTests/IssueReportingTests.swift`
- **Lines:** 57 | **Tests:** 6 | **Framework:** Swift Testing (already migrated)
- **Patterns (already Swift Testing):**
  - Free functions with `@Test`
  - `withKnownIssue { ... }` (5 sites)
  - One `async` test
  - `import IssueReporting`, `import Testing`
- **No migration needed.**

#### `examples/fuse-library/Tests/NavigationTests/NavigationTests.swift`
- **Lines:** 470 | **Tests:** 16 | **Framework:** Swift Testing (already migrated)
- **Struct:** `@MainActor struct NavigationTests`
- **Patterns (already Swift Testing):**
  - `@Test` on all methods
  - `#expect(...)` throughout
  - `Issue.record(...)` instead of `XCTFail` (4 sites)
  - `async` TestStore tests with `await store.send(...)`
  - `import Testing`, `import ComposableArchitecture`, `import SwiftUI`
  - Uses both `Store` and `TestStore`
- **No migration needed.**

#### `examples/fuse-library/Tests/NavigationTests/NavigationStackTests.swift`
- **Lines:** 184 | **Tests:** 6 | **Framework:** Swift Testing (already migrated)
- **Struct:** `@MainActor struct NavigationStackTests`
- **Patterns (already Swift Testing):**
  - `@Test` on all methods
  - `#expect(...)` throughout
  - `Issue.record(...)` (2 sites)
  - `#expect(Bool(true), "...")` no-op assertions (flagged as LOW in audit)
  - Uses `Store` (not `TestStore`) — `AppFeature.State` not `Equatable`
  - Non-async tests (Store, not TestStore)
- **No migration needed.**

#### `examples/fuse-library/Tests/NavigationTests/PresentationTests.swift`
- **Lines:** 354 | **Tests:** 11 | **Framework:** Swift Testing (already migrated)
- **Struct:** `@MainActor struct PresentationTests`
- **Patterns (already Swift Testing):**
  - `@Test` on all methods
  - `#expect(...)` throughout
  - `#expect(Bool(true), "...")` (1 site, flagged LOW)
  - `async` TestStore tests
  - Mix of `Store` and `TestStore`
- **No migration needed.**

#### `examples/fuse-library/Tests/NavigationTests/UIPatternTests.swift`
- **Lines:** 358 | **Tests:** 10 | **Framework:** Swift Testing (already migrated)
- **Struct:** `@MainActor struct UIPatternTests`
- **Patterns (already Swift Testing):**
  - `@Test` on all methods
  - `#expect(...)` throughout
  - `async throws` on `testMultipleAsyncEffects` (uses `Task.sleep`)
  - Mix of `Store` and `TestStore` patterns
- **No migration needed.**

#### `examples/fuse-library/Tests/SharingTests/SharedBindingTests.swift`
- **Lines:** 133 | **Tests:** 7 | **Framework:** XCTest
- **Class:** `SharedBindingTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (14 sites), `XCTFail` (1 site)
  - `expectation(description:)` + `wait(for:timeout:)` (2 usages in `testDoubleNotificationPrevention`)
  - `XCTestExpectation` with `isInverted = true` (inverted expectation — must NOT be fulfilled)
  - `withObservationTracking` called in test body
  - `import XCTest`, `import Observation`, `import Sharing`, `import SwiftUI`
  - `addTeardownBlock { ... }` (1 site in `testFileStorageRoundTrip` — actually in SharedPersistenceTests, see below)
- **Tests to migrate:** 7

#### `examples/fuse-library/Tests/SharingTests/SharedObservationTests.swift`
- **Lines:** 166 | **Tests:** 9 | **Framework:** XCTest
- **Class:** `SharedObservationTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (11 sites), `XCTAssertTrue` (1 site)
  - `expectation(description:)` + `wait(for:timeout:)` (4 usages)
  - `await fulfillment(of:timeout:)` (1 usage — async variant)
  - `expectedFulfillmentCount` set to 3 in one test
  - `import XCTest`, `import Combine`, `import Sharing`
  - All Combine-based publisher tests (flagged M14 — prefer `Observations`)
  - Mix of sync and async tests
- **Tests to migrate:** 9

#### `examples/fuse-library/Tests/SharingTests/SharedPersistenceTests.swift`
- **Lines:** 149 | **Tests:** 15 | **Framework:** XCTest
- **Class:** `SharedPersistenceTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (19 sites), `XCTAssertNil` (3 sites), `XCTAssertNotNil` (1 site)
  - `addTeardownBlock { ... }` (1 usage — file cleanup in `testFileStorageRoundTrip`)
  - One `async` test (`testAppStorageConcurrentAccess`)
  - `import XCTest`, `import Sharing`
  - No XCTestExpectation, no continueAfterFailure
- **Tests to migrate:** 15

#### `examples/fuse-library/Tests/TCATests/BindingTests.swift`
- **Lines:** 180 | **Tests:** 7 | **Framework:** XCTest
- **Class:** `BindingTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (14 sites)
  - `async` on two tests (`testSendingBinding`, `testSendingCancellation`)
  - `await task.finish()` pattern
  - `import XCTest`, `import ComposableArchitecture`
  - No setUp/tearDown, no expectations, no continueAfterFailure
- **Tests to migrate:** 7

#### `examples/fuse-library/Tests/TCATests/DependencyTests.swift`
- **Lines:** 550 | **Tests:** 16 | **Framework:** XCTest
- **Class:** `DependencyTests: XCTestCase` (final)
- **Patterns:**
  - Mix of `@MainActor` and non-`@MainActor` test methods
  - `XCTAssertEqual` (29 sites), `XCTAssertNotNil` (10 sites), `XCTFail` (1 site), `XCTAssertNotEqual` (1 site)
  - `XCTExpectFailure { $0.compactDescription.contains("Unimplemented") }` (1 usage — DEP-07)
  - `async` on two tests
  - `try await Task.sleep(for: .milliseconds(...))` (2 sites)
  - `@_spi(Reflection) import CasePaths` — fragile SPI (flagged LOW)
  - `import XCTest`, `import Dependencies`, `import DependenciesMacros`, `import ComposableArchitecture`
  - `EnumMetadata` usage in one test
- **Tests to migrate:** 16

#### `examples/fuse-library/Tests/TCATests/EffectTests.swift`
- **Lines:** 327 | **Tests:** 8 | **Framework:** XCTest
- **Class:** `EffectTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (9 sites), `XCTAssertFalse` (2 sites), `XCTAssertTrue` (1 site)
  - `async throws` on 6 of 8 tests
  - `try await Task.sleep(for: .milliseconds(...))` (7 sites) — real-time delays
  - `import XCTest`, `import ComposableArchitecture`
  - No setUp/tearDown, no expectations, no continueAfterFailure
- **Tests to migrate:** 8

#### `examples/fuse-library/Tests/TCATests/ObservableStateTests.swift`
- **Lines:** 440 | **Tests:** 10 | **Framework:** XCTest
- **Class:** `ObservableStateTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (22 sites), `XCTAssertNil` (3 sites), `XCTAssertNotNil` (2 sites), `XCTFail` (2 sites), `XCTAssertTrue` (1 site), `XCTAssertFalse` (1 site)
  - All tests synchronous (no `async`)
  - `if case ... { XCTFail(...) }` pattern (2 sites — needs `Issue.record`)
  - `import XCTest`, `import ComposableArchitecture`
  - No setUp/tearDown, no expectations, no continueAfterFailure
- **Tests to migrate:** 10

#### `examples/fuse-library/Tests/TCATests/StoreReducerTests.swift`
- **Lines:** 366 | **Tests:** 11 | **Framework:** XCTest
- **Class:** `StoreReducerTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (19 sites), `XCTAssertNil` (3 sites), `XCTAssertNotNil` (1 site)
  - One `async` test (`testStoreSendReturnsStoreTask`)
  - `await task.finish()` pattern
  - `import XCTest`, `import ComposableArchitecture`
  - Uses `Store` and `withState(...)` (not `TestStore`)
  - No setUp/tearDown, no expectations, no continueAfterFailure
- **Tests to migrate:** 11

#### `examples/fuse-library/Tests/TCATests/TestStoreEdgeCaseTests.swift`
- **Lines:** 186 | **Tests:** 4 | **Framework:** XCTest
- **Class:** `TestStoreEdgeCaseTests: XCTestCase` (final)
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (2 sites), `XCTAssertFalse` (1 site)
  - All tests `async`
  - `await store.send(...)`, `await store.receive(...)`, `store.exhaustivity = .off`
  - `store.timeout = 5_000_000_000` (nanoseconds)
  - `await store.skipReceivedActions()`
  - `await store.finish()`
  - `import XCTest`, `import ComposableArchitecture`
  - No setUp/tearDown, no continueAfterFailure
- **Tests to migrate:** 4

#### `examples/fuse-library/Tests/TCATests/TestStoreTests.swift`
- **Lines:** 474 | **Tests:** 13 | **Framework:** XCTest + Swift Testing hybrid
- **Class:** `TestStoreTests: XCTestCase` (final)
- **Special:** This file imports BOTH `import Testing` AND `import XCTest`. The class is still `XCTestCase` but uses `withKnownIssue { ... }` (Swift Testing API) inside XCTest methods.
- **Patterns:**
  - `@MainActor` on all test methods
  - `XCTAssertEqual` (6 sites), `XCTAssertFalse` (1 site), `XCTAssertTrue` (2 sites)
  - `withKnownIssue { await store.send(...) }` (1 usage — TEST-04)
  - All tests `async`
  - `await store.send(...)`, `await store.receive(...)`, `store.exhaustivity = .off`
  - `store.timeout = 5_000_000_000`
  - `await store.skipReceivedActions()`
  - `import XCTest`, `import Testing`, `import ComposableArchitecture`, `import Dependencies`, `import DependenciesTestSupport`
  - File-scope `@Reducer` types (many)
- **Tests to migrate:** 13

#### `examples/fuse-library/Tests/DatabaseTests/SQLiteDataTests.swift`
- **Lines:** 399 | **Tests:** 14 | **Framework:** XCTest
- **Class:** `SQLiteDataTests: XCTestCase` (final)
- **Patterns:**
  - Mix of `@MainActor` (3 tests) and non-`@MainActor` tests
  - `XCTAssertEqual` (24 sites), `XCTAssertNil` (2 sites), `XCTAssertNotNil` (2 sites), `XCTAssertGreaterThanOrEqual` (3 sites), `XCTAssertTrue` (1 site)
  - `XCTestExpectation(description:)` + `await fulfillment(of:timeout:)` (3 tests: SD-09, SD-10, SD-11)
  - `Task.sleep(for: .milliseconds(100))` (3 sites)
  - `cancellable.cancel()` after observation tests
  - `throws` on sync tests, `async throws` on observation tests
  - Private helper methods: `setupSchema`, `makeDatabase`, `makeSeededDatabase`
  - `import XCTest`, `import SQLiteData`, `import GRDB`, `import Dependencies`, `import DependenciesTestSupport`, `import StructuredQueries`
  - `withDependencies { ... } operation: { ... }` pattern
- **Tests to migrate:** 14
- **Note:** GRDB import is flagged H6 — must be removed during migration.

#### `examples/fuse-library/Tests/DatabaseTests/StructuredQueriesTests.swift`
- **Lines:** 486 | **Tests:** 15 | **Framework:** XCTest
- **Class:** `StructuredQueriesTests: XCTestCase` (final)
- **Patterns:**
  - All tests synchronous (no `async`)
  - `XCTAssertEqual` (37 sites), `XCTAssertFalse` (2 sites), `XCTAssertTrue` (4 sites), `XCTAssertNil` (1 site), `XCTAssertGreaterThanOrEqual` (3 sites), `XCTAssertNotNil` (1 site)
  - `throws` on most tests
  - Private helper methods: `makeDatabase`, `seedCategories`, `seedItems`, `seedAll`
  - `import XCTest`, `import SQLiteData`, `import StructuredQueries`
  - `try dbQueue.write { db in ... }` patterns (many)
  - No setUp/tearDown, no expectations, no continueAfterFailure
- **Tests to migrate:** 15

---

### fuse-app Tests

#### `examples/fuse-app/Tests/FuseAppIntegrationTests/FuseAppIntegrationTests.swift`
- **Lines:** 511 | **Tests:** 30 | **Framework:** XCTest
- **Classes:** 6 separate `XCTestCase` subclasses (one per feature):
  - `CounterFeatureTests` (5 tests)
  - `TodosFeatureTests` (5 tests)
  - `ContactsFeatureTests` (4 tests)
  - `ContactDetailFeatureTests` (4 tests)
  - `DatabaseFeatureTests` (3 tests)
  - `SettingsFeatureTests` (5 tests)
  - `AppFeatureTests` (4 tests — wait, 30 total across 7 classes)
- **Patterns:**
  - `@MainActor` on all test methods
  - All tests `async`
  - `XCTAssertEqual` (13 sites)
  - `await store.send(...)`, `await store.receive(...)` (TestStore)
  - `store.exhaustivity = .off` (2 tests)
  - `try! createMigratedDatabase()` (2 sites) — `try!` in test (flagged LOW)
  - `try! await db.write { ... }` (1 site)
  - `LockIsolated` for thread-safe counter
  - `import ComposableArchitecture`, `import GRDB`, `import XCTest`, `@testable import FuseApp`
  - GRDB import flagged H6
  - Critical bug C1: `.toggleCategory` → `.categoryFilterChanged` (already fixed per git status)
- **Tests to migrate:** 30

#### `examples/fuse-app/Tests/FuseAppTests/XCSkipTests.swift`
- **Lines:** 54 | **Tests:** 1 | **Framework:** XCTest
- **Class:** `XCSkipTests: XCTestCase` (`@available(macOS 13, macCatalyst 16, *)`)
- **Special:** Infrastructure file that writes JUnit XML stubs for `skip test` parity reporting. Not a regular test. Cannot be migrated to Swift Testing (relies on `Bundle`, `FileManager`, file I/O side effects). Also defines `isJava`, `isAndroid`, `isRobolectric`, `is32BitInteger` globals.
- **Note:** The comment in this file explicitly explains why Gradle tests are skipped for fuse-app. This file must remain XCTest.

---

### Summary Counts

| File | Tests | Framework | Migration Needed |
|------|-------|-----------|-----------------|
| FuseLibraryTests.swift | 2 | XCTest | Yes |
| ObservationTests.swift | 18 | XCTest | Yes |
| ObservationBridgeTests.swift | 9 | Swift Testing | No |
| StressTests.swift | 2 | Swift Testing | No |
| XCSkipTests.swift (fuse-lib) | 1 | XCTest | No (infrastructure) |
| CasePathsTests.swift | 9 | Swift Testing | No |
| CustomDumpTests.swift | 11 | Swift Testing | No |
| IdentifiedCollectionsTests.swift | 7 | Swift Testing | No |
| IssueReportingTests.swift | 6 | Swift Testing | No |
| NavigationTests.swift | 16 | Swift Testing | No |
| NavigationStackTests.swift | 6 | Swift Testing | No |
| PresentationTests.swift | 11 | Swift Testing | No |
| UIPatternTests.swift | 10 | Swift Testing | No |
| SharedBindingTests.swift | 7 | XCTest | Yes |
| SharedObservationTests.swift | 9 | XCTest | Yes |
| SharedPersistenceTests.swift | 15 | XCTest | Yes |
| BindingTests.swift | 7 | XCTest | Yes |
| DependencyTests.swift | 16 | XCTest | Yes |
| EffectTests.swift | 8 | XCTest | Yes |
| ObservableStateTests.swift | 10 | XCTest | Yes |
| StoreReducerTests.swift | 11 | XCTest | Yes |
| TestStoreEdgeCaseTests.swift | 4 | XCTest | Yes |
| TestStoreTests.swift | 13 | XCTest (hybrid) | Yes |
| SQLiteDataTests.swift | 14 | XCTest | Yes |
| StructuredQueriesTests.swift | 15 | XCTest | Yes |
| FuseAppIntegrationTests.swift | 30 | XCTest | Yes |
| XCSkipTests.swift (fuse-app) | 1 | XCTest | No (infrastructure) |

**Already on Swift Testing:** 87 tests across 13 files — no work needed.
**Require migration:** 184 test methods across 14 files. Note: the 121-test count cited in the task reflects the current passing suite; some of the 184 methods are in files that may have fewer active tests after audit fixes.

---

## XCTest → Swift Testing Migration Map

### 1. Import Changes

| XCTest pattern | Swift Testing equivalent |
|----------------|--------------------------|
| `import XCTest` | `import Testing` |
| `import XCTest` + `import Testing` | `import Testing` only |
| `@testable import Module` | Retain as-is (works with Swift Testing) |

### 2. Test Class/Struct Declaration

| XCTest pattern | Swift Testing equivalent |
|----------------|--------------------------|
| `final class FooTests: XCTestCase { }` | `struct FooTests { }` or `@Suite struct FooTests { }` |
| `final class FooTests: XCTestCase { }` with `@MainActor` methods | `@MainActor struct FooTests { }` — actor isolation at suite level |
| `@available(macOS 14, iOS 17, *) final class FooTests: XCTestCase` | `struct FooTests { }` with `guard #available(macOS 14, ...)` inside each test, or `@Suite .enabled(if: ...)` |
| 6 separate `XCTestCase` subclasses in one file (fuse-app) | 6 separate `@Suite struct` declarations or one `@Suite` with nested `@Suite` extensions |

### 3. Test Method Declaration

| XCTest pattern | Swift Testing equivalent |
|----------------|--------------------------|
| `func testFoo() { }` | `@Test func foo() { }` (or `func testFoo()` — name `test` prefix works without `@Test` but `@Test` is required for discovery in Swift Testing) |
| `func testFoo() async { }` | `@Test func foo() async { }` |
| `func testFoo() throws { }` | `@Test func foo() throws { }` |
| `func testFoo() async throws { }` | `@Test func foo() async throws { }` |
| `@MainActor func testFoo()` | Move `@MainActor` to suite struct level, or keep per-test |

### 4. Assertions

| XCTest pattern | Swift Testing equivalent | Notes |
|----------------|--------------------------|-------|
| `XCTAssertEqual(a, b)` | `#expect(a == b)` | For struct/array comparisons: prefer `expectNoDifference(a, b)` per M4 |
| `XCTAssertEqual(a, b, accuracy: e)` | `#expect(abs(a - b) < e)` | No built-in accuracy overload |
| `XCTAssertNil(x)` | `#expect(x == nil)` | |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` | |
| `XCTAssertTrue(x)` | `#expect(x)` | |
| `XCTAssertFalse(x)` | `#expect(!x)` | |
| `XCTAssertGreaterThanOrEqual(a, b)` | `#expect(a >= b)` | |
| `XCTFail("message")` | `Issue.record("message")` | |
| `XCTFail(...)` inside `if case` pattern | `guard case ... else { Issue.record(...); return }` | |

### 5. Known Failures

| XCTest pattern | Swift Testing equivalent | Files affected |
|----------------|--------------------------|----------------|
| `XCTExpectFailure { ... }` | `withKnownIssue { ... }` | DependencyTests.swift (1 site) |
| `XCTExpectFailure { $0.compactDescription.contains("Unimplemented") }` | `withKnownIssue("Unimplemented") { ... }` | DependencyTests.swift |

### 6. Async Expectations (XCTestExpectation)

This is the most complex migration area. Three files use `XCTestExpectation`.

| XCTest pattern | Swift Testing equivalent |
|----------------|--------------------------|
| `let e = expectation(description: "...")` + `wait(for: [e], timeout: N)` | Rewrite as `async` test using `withCheckedContinuation` or `AsyncStream`, or use `confirmation(...)` |
| `expectation.isInverted = true` (must NOT fire) | `withKnownIssue` guard, or use `Task.sleep` then assert no side effect occurred |
| `fulfillment(of: [e], timeout: N)` (async variant) | `await confirmation("...") { confirm in ... confirm() }` |
| `expectedFulfillmentCount = N` | `await confirmation("...", expectedCount: N) { ... }` |

**Detailed mapping for each expectation use:**

**SharedBindingTests — `testDoubleNotificationPrevention`:**
```swift
// XCTest (current):
let sharedMutationFired = expectation(description: "shared mutation onChange")
sharedMutationFired.isInverted = true
withObservationTracking { _ = model.normalCount } onChange: {
    sharedMutationFired.fulfill()
}
model.$sharedCount.withLock { $0 = 42 }
wait(for: [sharedMutationFired], timeout: 0.1)

// Swift Testing:
// Pattern: observe, mutate, sleep briefly, assert counter == 0
// (inverted expectations have no direct Swift Testing equivalent)
// Use: sleep + assert no side effect
let counter = AtomicCounter()
withObservationTracking { _ = model.normalCount } onChange: { counter.increment() }
model.$sharedCount.withLock { $0 = 42 }
try? await Task.sleep(for: .milliseconds(100))
#expect(counter.value == 0, "Mutating @ObservationIgnored should not trigger onChange")
```

**SharedObservationTests — publisher tests:**
```swift
// XCTest (current):
let expectation = expectation(description: "publisher emits")
let cancellable = $count.publisher.dropFirst().sink { value in
    received.append(value)
    expectation.fulfill()
}
$count.withLock { $0 = 42 }
wait(for: [expectation], timeout: 2.0)

// Swift Testing (option A — confirmation):
await confirmation("publisher emits") { confirm in
    let cancellable = $count.publisher.dropFirst().sink { value in
        received.append(value)
        confirm()
    }
    $count.withLock { $0 = 42 }
    try await Task.sleep(for: .seconds(2))
    _ = cancellable
}

// Swift Testing (option B — async sequence, preferred per M14):
// Replace Combine publisher with Observations { } async sequence
```

**SQLiteDataTests — ValueObservation tests (SD-09, SD-10, SD-11):**
```swift
// XCTest (current):
let expectation = XCTestExpectation(description: "observation triggers")
let cancellable = observation.start(in: dbQueue, onError: { _ in }, onChange: { items in
    observedValues.append(items)
    if observedValues.count >= 2 { expectation.fulfill() }
})
await fulfillment(of: [expectation], timeout: 5.0)

// Swift Testing:
await confirmation("observation fires on insert", expectedCount: 1) { confirm in
    let cancellable = observation.start(in: dbQueue, onError: { _ in }, onChange: { items in
        observedValues.append(items)
        if observedValues.count >= 2 { confirm() }
    })
    try await Task.sleep(for: .milliseconds(100))
    try await dbQueue.write { ... }
    try await Task.sleep(for: .seconds(5)) // guard timeout
    cancellable.cancel()
}
```

### 7. setUp / tearDown

| XCTest pattern | Swift Testing equivalent | Files affected |
|----------------|--------------------------|----------------|
| `override func setUp()` | `init()` or `init() async throws` | FuseLibraryTests, ObservationTests |
| `override func setUp() async throws` | `init() async throws` | — |
| `override func tearDown()` | `deinit` | — |
| `addTeardownBlock { ... }` | `defer { ... }` inside test, or cleanup in `deinit` | SharedPersistenceTests |

**FuseLibraryTests / ObservationTests setUp migration:**
```swift
// XCTest (current):
override func setUp() {
    #if os(Android)
    loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
    #endif
}

// Swift Testing:
struct FuseLibraryTests {
    init() {
        #if os(Android)
        loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
        #endif
    }
    // ... @Test methods
}
```

**SharedPersistenceTests addTeardownBlock:**
```swift
// XCTest (current):
addTeardownBlock {
    try? FileManager.default.removeItem(at: tempURL)
}

// Swift Testing:
// Option A: defer inside the test
@Test func testFileStorageRoundTrip() throws {
    let tempURL = ...
    defer { try? FileManager.default.removeItem(at: tempURL) }
    // ... rest of test
}
// Option B: store in a class-based Suite with deinit (if URL is an instance property)
```

### 8. `continueAfterFailure`

No file in this codebase uses `continueAfterFailure = false`. The XCTest default is `true`. Swift Testing always continues after a `#expect` failure (equivalent to `continueAfterFailure = true`). There is no risk here.

### 9. Helper Methods

Private helper methods on `XCTestCase` subclasses (`setupSchema`, `makeDatabase`, `makeSeededDatabase`, `createMigratedDatabase`, `seedCategories`) become ordinary private methods on the suite struct or file-scope private functions. No behavior change required.

### 10. File-Scope Types Required by Macros

Multiple files define `@Table`, `@Reducer`, `@CasePathable`, and `@Observable` types at file scope (not nested in the test class) because Swift macros cannot attach to locally-defined types. This constraint is independent of XCTest vs Swift Testing and applies equally to both. No migration impact.

### 11. `@available` Availability Guards

| XCTest pattern | Swift Testing equivalent |
|----------------|--------------------------|
| `@available(macOS 14, iOS 17, *) final class FooTests: XCTestCase` | Can't annotate `@Suite` struct with `@available`. Use `#available(...)` guard inside tests, or `.enabled(if: #available(...))` suite trait (experimental). |
| `@available(macOS 13, macCatalyst 16, *)` | Same as above |

For `ObservationTests` (iOS 17 / macOS 14 requirement), the safest approach is to guard the entire suite body at runtime:
```swift
@Suite struct ObservationTests {
    init() throws {
        try #require(#available(macOS 14, iOS 17, *))
    }
    // ... @Test methods — will be skipped if guard throws
}
```

---

## Risk Matrix

### EASY (mechanical, low regression risk)

| File | Why Easy | Estimated effort |
|------|----------|-----------------|
| SharedPersistenceTests.swift | Pure `@MainActor` + `XCTAssert*` calls; one `addTeardownBlock` → `defer`; no expectations | 30 min |
| StructuredQueriesTests.swift | All synchronous, pure `XCTAssert*`; no expectations, no setUp/tearDown; private helpers trivially become methods on struct | 45 min |
| StoreReducerTests.swift | All `@MainActor`, mostly synchronous; one `async` test; pure `XCTAssert*`; no expectations | 30 min |
| ObservableStateTests.swift | All `@MainActor` synchronous; `XCTFail` → `Issue.record`; no expectations | 30 min |
| BindingTests.swift | Small file; two `async` tests; pure `XCTAssert*` | 20 min |

### MEDIUM (requires judgment, moderate regression risk)

| File | Why Medium | Estimated effort | Key risks |
|------|------------|-----------------|-----------|
| EffectTests.swift | All `async throws`; real `Task.sleep` delays (timing-sensitive); pure `XCTAssert*` otherwise | 45 min | Timing sensitivity in sleep-based tests — may need `.timeLimit` trait |
| TestStoreEdgeCaseTests.swift | All `async`; `store.exhaustivity = .off`; `store.timeout`; `skipReceivedActions()`, `finish()` | 30 min | TestStore exhaustivity behavior under Swift Testing concurrency model |
| TestStoreTests.swift | Hybrid file already imports `Testing`; uses `withKnownIssue` inside XCTest methods; needs full transition | 60 min | `withKnownIssue` already present but context is XCTest; needs struct conversion |
| DependencyTests.swift | Large file; `XCTExpectFailure` → `withKnownIssue`; `@_spi(Reflection)` SPI; non-`@MainActor` tests mixed with `@MainActor`; `EnumMetadata` | 60 min | SPI import works with Swift Testing but is fragile; mixed actor isolation |
| FuseLibraryTests.swift + ObservationTests.swift | `setUp` → `init()`; `@available` guard; 20 tests combined; JNI library loading | 45 min | Library load timing in `init()` vs `setUp()` (called per-test in XCTest; `init()` called per-instance in Swift Testing — behavior is equivalent for structs) |
| SharedPersistenceTests.swift | Large (15 tests); `addTeardownBlock` | 40 min | File cleanup correctness |

### HARD (non-trivial, highest regression risk)

| File | Why Hard | Estimated effort | Key risks |
|------|----------|-----------------|-----------|
| SharedBindingTests.swift | Inverted `XCTestExpectation` (must NOT fire); `withObservationTracking` + expectation timing; `wait(for:timeout:)` | 90 min | Inverted expectation has no direct Swift Testing equivalent; timing of observation callbacks |
| SharedObservationTests.swift | Multiple `XCTestExpectation` with `expectedFulfillmentCount`; Combine publisher tests; `fulfillment(of:timeout:)` async; 9 tests | 120 min | Combine → `confirmation(expectedCount:)` is non-trivial; publisher ordering guarantees |
| SQLiteDataTests.swift | `XCTestExpectation` in 3 observation tests (SD-09, SD-10, SD-11); GRDB `ValueObservation` + async callbacks; `@MainActor` mixed with non-`@MainActor`; `import GRDB` must be removed (H6) | 120 min | Observation callback timing; `confirmation` with count semantics; removing GRDB import |
| FuseAppIntegrationTests.swift | 30 tests across 7 `XCTestCase` classes; 6 become `@Suite struct`; `try!` → proper throws; C1 bug fix; H6 GRDB removal; integration tests most sensitive to regression | 120 min | Multi-class file needs careful restructuring; `try!` removal may reveal hidden errors |

---

## Async Interaction Risks

### Risk 1: TestStore `await store.send/receive` under Swift Testing

TCA's `TestStore` is built on `MainActor` and internally uses `XCTest`-aware completion detection via `effectDidSubscribe`. In Swift Testing, the test executor is different from XCTest's serial main thread executor.

**Current evidence:** The already-migrated files (NavigationTests, PresentationTests, UIPatternTests) successfully use `await store.send(...)` and `await store.receive(...)` inside `@MainActor struct` Swift Testing suites. This proves the pattern works.

**Mechanism:** Swift Testing's `@Test` functions on a `@MainActor struct` run on the main actor by default, which is the same actor TCA's `TestStore` requires. No incompatibility observed.

**Residual risk:** `store.timeout` is set in nanoseconds (`5_000_000_000`) in edge case tests. Swift Testing has `.timeLimit` trait (in seconds). If timeout behavior is needed at the suite level, this trait must be added. Individual `store.timeout` settings remain valid regardless of test framework.

### Risk 2: `Task.sleep`-Based Timing in EffectTests

Eight tests in `EffectTests.swift` use `try await Task.sleep(for: .milliseconds(N))` to wait for side effects. These are not expectation-based — they rely on wall-clock time. This pattern works identically in Swift Testing. However:

- If these tests run concurrently (Swift Testing runs tests in parallel by default on a per-file basis), timing races could cause flakiness.
- **Mitigation:** Add `@Suite(.serialized)` to `EffectTests` if timing issues appear, or migrate the tests to use `TestStore` + `await store.receive(...)` instead of raw sleep.

### Risk 3: `XCTestExpectation` with `isInverted = true`

`SharedBindingTests.testDoubleNotificationPrevention` uses an inverted expectation — a callback must NOT be called within 0.1 seconds. Swift Testing has no `confirmation(expectedCount: 0)` equivalent (expectedCount must be >= 1).

**Migration strategy:** Replace with `AtomicCounter` + `Task.sleep(for: .milliseconds(100))` + `#expect(counter.value == 0)`. This pattern already appears in `ObservationBridgeTests.swift` (the reference file) and is proven to work in this codebase.

### Risk 4: `confirmation(expectedCount:)` for Multi-Fire Expectations

`SharedObservationTests.testSharedPublisherMultipleValues` uses `expectedFulfillmentCount = 3`. Swift Testing's `confirmation("...", expectedCount: 3)` supports this directly but has subtly different semantics: all confirmations must occur within the `confirmation` block's lifetime, and the block will not return until the expected count is met or a timeout occurs (there is no explicit timeout parameter in `confirmation` — it uses the test's overall timeout).

**Mitigation:** Wrap the `confirmation` body in a `Task` with explicit deadline if needed, or rely on the `.timeLimit` suite trait.

### Risk 5: `withKnownIssue` in Async Context

`TestStoreTests.testExhaustivityOnDetectsUnassertedChange` wraps an `async` call inside `withKnownIssue`. In Swift Testing, `withKnownIssue` supports async closures:
```swift
await withKnownIssue {
    await store.send(.update) { $0.count = 1 }
}
```
This is already used correctly in `IssueReportingTests.swift`. No risk.

### Risk 6: Mixed Actor Isolation in DependencyTests

`DependencyTests.swift` has some tests that are `@MainActor` and some that are not. When migrating to a `struct DependencyTests`, the non-`@MainActor` tests can remain without `@MainActor` annotation at the method level if the suite struct is not annotated. Tests that previously used `@MainActor` explicitly must be annotated individually, or the entire suite must be `@MainActor`.

The safest approach is `@MainActor struct DependencyTests` and mark only the `testTaskLocalPropagation` and similar purely async tests with `nonisolated` if needed. All tests in this file that access `Store` or `TestStore` require `@MainActor`.

### Risk 7: `@available` Availability in ObservationTests

`ObservationTests` is `@available(macOS 14, iOS 17, *)`. Swift Testing has no `@available` on `@Suite`. The recommended pattern is:

```swift
struct ObservationTests {
    init() throws {
        // Skip entire suite on older OS
        try #require(#available(macOS 14, iOS 17, *),
                     "ObservationTests requires macOS 14 / iOS 17")
    }
}
```

If `#require` throws, the suite is skipped (not failed) on older platforms. This preserves the original intent.

### Risk 8: JNI Library Loading Timing (FuseLibraryTests, ObservationTests)

`setUp()` in XCTest runs before each test method. In Swift Testing, `init()` on a struct-based suite runs before each test (each `@Test` creates a new instance of the struct). The timing is equivalent for library loading. However, if `loadPeerLibrary` is expensive, it will be called 18 times (for ObservationTests) instead of once.

**Mitigation:** Use a `static var` sentinel to load only once:
```swift
struct ObservationTests {
    private static let _loaded: Void = {
        #if os(Android)
        loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
        #endif
    }()
    init() { _ = Self._loaded }
}
```

---

## Recommended Migration Order

### Phase 8 Migration Sequence

Rationale: migrate easy files first to establish confidence, then progress to harder files. Keep infrastructure files (`XCSkipTests`) untouched. Files already on Swift Testing require zero migration work.

#### Wave 1 — Purely Mechanical (no risk, do these first)
1. **`SharedPersistenceTests.swift`** — 15 tests, all `@MainActor`, no expectations; one `defer` change
2. **`StoreReducerTests.swift`** — 11 tests, all `@MainActor`; one async test; pure `XCTAssert*`
3. **`ObservableStateTests.swift`** — 10 tests, all `@MainActor`; `XCTFail` → `Issue.record`
4. **`BindingTests.swift`** — 7 tests, small file; no surprises
5. **`StructuredQueriesTests.swift`** — 15 tests, all synchronous `throws`; private helpers → struct methods

**Expected test count after Wave 1:** 121 (no change — all should pass if migration is correct)

#### Wave 2 — Async but Straightforward
6. **`EffectTests.swift`** — 8 tests; all async; add `@Suite(.serialized)` if timing issues arise
7. **`TestStoreEdgeCaseTests.swift`** — 4 tests; all async TestStore; simplest edge-case set
8. **`TestStoreTests.swift`** — 13 tests; already hybrid (`import Testing`); convert class → struct, keep existing `withKnownIssue`
9. **`FuseLibraryTests.swift` + `ObservationTests.swift`** — 20 tests combined; `setUp` → `init()`; `@available` guard

**Expected test count after Wave 2:** 121 (maintained)

#### Wave 3 — Dependency and Integration Complexity
10. **`DependencyTests.swift`** — 16 tests; `XCTExpectFailure` → `withKnownIssue`; mixed actor isolation
11. **`FuseAppIntegrationTests.swift`** — 30 tests; 7 classes → 7 `@Suite struct`; remove `import GRDB`; fix `try!`

**Expected test count after Wave 3:** 121+ (C1 bug fix may add failing test that now passes)

#### Wave 4 — Expectation Rewrites (highest risk, do last)
12. **`SharedBindingTests.swift`** — 7 tests; inverted expectation rewrite
13. **`SharedObservationTests.swift`** — 9 tests; multi-fire confirmation; Combine publisher tests
14. **`SQLiteDataTests.swift`** — 14 tests; 3 ValueObservation tests with expectations; remove `import GRDB`

**Expected test count after Wave 4:** 121+ (maintained or increased if previously skipped tests now run)

#### Never Migrate (infrastructure files)
- `examples/fuse-library/Tests/ObservationTests/XCSkipTests.swift` — `XCGradleHarness` requires XCTest
- `examples/fuse-app/Tests/FuseAppTests/XCSkipTests.swift` — JUnit XML stub generator requires XCTest

---

## Regression Prevention

### Baseline Establishment

Before starting migration, record the exact baseline:
```bash
# From repo root
make test 2>&1 | tail -20  # should show 91 passed
cd examples/fuse-app && swift test 2>&1 | tail -20  # should show 30 passed
```

If possible, capture the specific test names that pass so regressions are detectable at the test-name level, not just count level.

### Per-File Verification Protocol

For each file migrated:
1. Run `make test-filter FILTER=<SuiteName>` before migration to confirm current pass count.
2. Apply migration changes.
3. Run `make test-filter FILTER=<SuiteName>` again — must show same or greater pass count.
4. Run full `make test` — total count must be >= 121.

### Parallel Framework Compatibility Period

Both XCTest and Swift Testing can coexist in the same test target. Swift Testing types are discovered by the Swift Testing runner; XCTest types are discovered by the XCTest runner. The `xcodebuild test` and `swift test` runners handle both frameworks simultaneously.

**Risk:** `TestStoreTests.swift` currently imports both `Testing` and `XCTest`. During migration of this file, temporarily the class will still exist but `withKnownIssue` will be called from XCTest context. This is supported — `withKnownIssue` is available in XCTest contexts when `import Testing` is present. The transition from `XCTestCase` class to `struct` can be done atomically per file.

### Assertion Equivalence Verification

The most common regression vector is incorrect assertion migration. Key mappings to double-check:

| Assertion | Semantic difference |
|-----------|---------------------|
| `XCTAssertEqual(a, b)` → `#expect(a == b)` | None for `Equatable` types |
| `XCTAssertNil(x)` → `#expect(x == nil)` | None |
| `XCTAssertGreaterThanOrEqual(a, b)` → `#expect(a >= b)` | None |
| `XCTFail("msg")` → `Issue.record("msg")` | `XCTFail` stops the test; `Issue.record` does NOT stop the test (test continues). If the original `XCTFail` was used as a guard, add `return` after `Issue.record(...)`. |
| `XCTExpectFailure { ... }` → `withKnownIssue { ... }` | `XCTExpectFailure` fails the test if the block does NOT trigger a failure; `withKnownIssue` reports an issue if the block does NOT trigger a known issue. Semantics are equivalent but error messages differ. |

### `@Suite(.serialized)` for State-Sharing Tests

The database tests (`SQLiteDataTests`, `StructuredQueriesTests`) and sharing tests (`SharedPersistenceTests`, `SharedObservationTests`) mutate shared state (in-memory databases, `UserDefaults` via `.appStorage`). Swift Testing may run `@Test` methods concurrently by default.

**Mitigation:** Add `@Suite(.serialized)` to any test suite that:
- Uses `.appStorage` keys (risk of key collision between tests)
- Uses `.inMemory("key")` with shared keys across tests
- Uses a shared database state

The PFW audit finding H10 recommends `@Suite(.serialized, .dependencies { ... }) struct BaseSuite {}`. The `.serialized` trait is essential for correctness in these suites.

### XCTest Infrastructure Files Must Not Be Removed

`XCSkipTests.swift` (both copies) must remain `XCTestCase` files. If they are accidentally converted to Swift Testing structs, `skip test` will fail to generate parity reports. Add a comment to both files:
```swift
// DO NOT migrate to Swift Testing — XCGradleHarness requires XCTestCase.
```

### H10 Compliance: `@Suite(.serialized, .dependencies { ... })`

The PFW-AUDIT H10 finding requires a `@Suite(.serialized, .dependencies { ... })` base pattern. When migrating each file, the suite declaration should become:

```swift
// For TCA test suites:
@Suite(.serialized) @MainActor struct BindingTests { ... }

// For database test suites (M8 compliance):
@Suite(.serialized, .dependencies { try $0.bootstrapDatabase() }) struct SQLiteDataTests { ... }

// For sharing test suites with appStorage:
@Suite(.serialized) @MainActor struct SharedPersistenceTests { ... }
```

This ensures both H10 compliance AND regression safety (no parallel test interference).

### Count Tracking

| After wave | Expected minimum count | Files migrated |
|------------|------------------------|----------------|
| Baseline | 121 | 0 |
| Wave 1 | 121 | 5 files, 58 tests |
| Wave 2 | 121 | 4 files + 2, 45 tests |
| Wave 3 | 121+ | 2 files, 46 tests |
| Wave 4 | 121+ | 3 files, 30 tests |
| Complete | >= 121 | All 14 files |

The count should never decrease. If it does, the migration introduced a regression. Specific guard: if the count drops below 121 at any wave boundary, halt migration and investigate before proceeding.
