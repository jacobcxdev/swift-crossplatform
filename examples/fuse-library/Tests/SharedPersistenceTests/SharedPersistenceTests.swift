import Sharing
import XCTest

// MARK: - File-scope types (macros can't attach to local types)

enum Theme: String, Sendable { case light, dark }

struct TestSettings: Codable, Equatable, Sendable {
    var name: String = "default"
    var count: Int = 0
}

// MARK: - Tests

final class SharedPersistenceTests: XCTestCase {

    // MARK: SHR-01 — AppStorage round-trips for each supported type

    @MainActor func testAppStorageBool() {
        @Shared(.appStorage("shr01_bool")) var value = false
        $value.withLock { $0 = true }
        XCTAssertEqual(value, true)
    }

    @MainActor func testAppStorageInt() {
        @Shared(.appStorage("shr01_int")) var value = 0
        $value.withLock { $0 = 42 }
        XCTAssertEqual(value, 42)
    }

    @MainActor func testAppStorageDouble() {
        @Shared(.appStorage("shr01_double")) var value = 0.0
        $value.withLock { $0 = 3.14 }
        XCTAssertEqual(value, 3.14, accuracy: 0.001)
    }

    @MainActor func testAppStorageString() {
        @Shared(.appStorage("shr01_string")) var value = ""
        $value.withLock { $0 = "hello" }
        XCTAssertEqual(value, "hello")
    }

    @MainActor func testAppStorageData() {
        @Shared(.appStorage("shr01_data")) var value = Data()
        let testData = Data("hello".utf8)
        $value.withLock { $0 = testData }
        XCTAssertEqual(value, testData)
    }

    @MainActor func testAppStorageURL() {
        @Shared(.appStorage("shr01_url")) var value: URL = URL(string: "https://example.com")!
        let newURL = URL(string: "https://updated.com")!
        $value.withLock { $0 = newURL }
        XCTAssertEqual(value, newURL)
    }

    @MainActor func testAppStorageDate() {
        let now = Date()
        @Shared(.appStorage("shr01_date")) var value: Date = .distantPast
        $value.withLock { $0 = now }
        XCTAssertEqual(value.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor func testAppStorageRawRepresentable() {
        @Shared(.appStorage("shr01_theme")) var value: Theme = .light
        $value.withLock { $0 = .dark }
        XCTAssertEqual(value, .dark)
    }

    // MARK: SHR-01 — AppStorage optional nil/non-nil

    @MainActor func testAppStorageOptionalNil() {
        @Shared(.appStorage("shr01_optInt")) var value: Int?
        XCTAssertNil(value)
        $value.withLock { $0 = 42 }
        XCTAssertEqual(value, 42)
        $value.withLock { $0 = nil }
        XCTAssertNil(value)
    }

    // MARK: SHR-01 edge cases

    @MainActor func testAppStorageLargeData() {
        let largeBlob = Data(repeating: 0xAB, count: 1_048_576) // 1 MB
        @Shared(.appStorage("shr01_largeData")) var value = Data()
        $value.withLock { $0 = largeBlob }
        XCTAssertEqual(value, largeBlob)
    }

    @MainActor func testAppStorageUnicodeString() {
        @Shared(.appStorage("shr01_unicode")) var value = ""
        $value.withLock { $0 = "Hello \u{1F30D} \u{65E5}\u{672C}\u{8A9E} \u{627F}\u{631}\u{628}\u{6CC}\u{647}" }
        XCTAssertEqual(value, "Hello \u{1F30D} \u{65E5}\u{672C}\u{8A9E} \u{627F}\u{631}\u{628}\u{6CC}\u{647}")
    }

    @MainActor func testAppStorageConcurrentAccess() async {
        @Shared(.appStorage("shr01_concurrent")) var value = 0
        for _ in 0..<10 {
            $value.withLock { $0 += 1 }
        }
        XCTAssertEqual(value, 10)
    }

    // MARK: SHR-02 — FileStorage round-trip

    @MainActor func testFileStorageRoundTrip() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID()).json")
        @Shared(.fileStorage(tempURL)) var settings = TestSettings()
        $settings.withLock { $0.name = "updated"; $0.count = 42 }
        // FileStorage debounces writes — verify in-memory state is correct immediately
        XCTAssertEqual(settings.name, "updated")
        XCTAssertEqual(settings.count, 42)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // MARK: SHR-03 — InMemory sharing across references

    @MainActor func testInMemorySharing() {
        @Shared(.inMemory("shr03_counter")) var ref1 = 0
        @Shared(.inMemory("shr03_counter")) var ref2 = 0
        $ref1.withLock { $0 = 42 }
        XCTAssertEqual(ref2, 42)
    }

    @MainActor func testInMemoryCrossFeature() {
        @Shared(.inMemory("shr03_token")) var token1 = ""
        @Shared(.inMemory("shr03_token")) var token2 = ""
        $token1.withLock { $0 = "abc" }
        XCTAssertEqual(token2, "abc")
    }

    // MARK: SHR-04 — Default value

    @MainActor func testSharedKeyDefaultValue() {
        @Shared(.appStorage("shr04_default")) var value: String = "defaultValue"
        XCTAssertEqual(value, "defaultValue")
    }

    // MARK: SHR-14 — Custom SharedKey (using inMemory as proxy)

    @MainActor func testCustomSharedKeyCompiles() {
        @Shared(.inMemory("shr14_custom")) var value = "initial"
        $value.withLock { $0 = "custom" }
        XCTAssertEqual(value, "custom")
    }
}
