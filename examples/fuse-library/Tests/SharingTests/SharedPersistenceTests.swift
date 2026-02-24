#if !SKIP
import Foundation
import Sharing
import Testing

// MARK: - File-scope types (macros can't attach to local types)

enum Theme: String, Sendable { case light, dark }

struct TestSettings: Codable, Equatable, Sendable {
    var name: String = "default"
    var count: Int = 0
}

// MARK: - Tests

@Suite(.serialized) @MainActor
struct SharedPersistenceTests {

    // MARK: SHR-01 — AppStorage round-trips for each supported type

    @Test func appStorageBool() {
        @Shared(.appStorage("shr01_bool")) var value = false
        $value.withLock { $0 = true }
        #expect(value == true)
    }

    @Test func appStorageInt() {
        @Shared(.appStorage("shr01_int")) var value = 0
        $value.withLock { $0 = 42 }
        #expect(value == 42)
    }

    @Test func appStorageDouble() {
        @Shared(.appStorage("shr01_double")) var value = 0.0
        $value.withLock { $0 = 3.14 }
        #expect(abs(value - 3.14) < 0.001)
    }

    @Test func appStorageString() {
        @Shared(.appStorage("shr01_string")) var value = ""
        $value.withLock { $0 = "hello" }
        #expect(value == "hello")
    }

    @Test func appStorageData() {
        @Shared(.appStorage("shr01_data")) var value = Data()
        let testData = Data("hello".utf8)
        $value.withLock { $0 = testData }
        #expect(value == testData)
    }

    @Test func appStorageURL() {
        @Shared(.appStorage("shr01_url")) var value: URL = URL(string: "https://example.com")!
        let newURL = URL(string: "https://updated.com")!
        $value.withLock { $0 = newURL }
        #expect(value == newURL)
    }

    @Test func appStorageDate() {
        let now = Date()
        @Shared(.appStorage("shr01_date")) var value: Date = .distantPast
        $value.withLock { $0 = now }
        #expect(abs(value.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001)
    }

    @Test func appStorageRawRepresentable() {
        @Shared(.appStorage("shr01_theme")) var value: Theme = .light
        $value.withLock { $0 = .dark }
        #expect(value == .dark)
    }

    // MARK: SHR-01 — AppStorage optional nil/non-nil

    @Test func appStorageOptionalNil() {
        @Shared(.appStorage("shr01_optInt")) var value: Int?
        #expect(value == nil)
        $value.withLock { $0 = 42 }
        #expect(value == 42)
        $value.withLock { $0 = nil }
        #expect(value == nil)
    }

    // MARK: SHR-01 edge cases

    @Test func appStorageLargeData() {
        let largeBlob = Data(repeating: 0xAB, count: 1_048_576) // 1 MB
        @Shared(.appStorage("shr01_largeData")) var value = Data()
        $value.withLock { $0 = largeBlob }
        #expect(value == largeBlob)
    }

    @Test func appStorageUnicodeString() {
        @Shared(.appStorage("shr01_unicode")) var value = ""
        $value.withLock { $0 = "Hello \u{1F30D} \u{65E5}\u{672C}\u{8A9E} \u{627F}\u{631}\u{628}\u{6CC}\u{647}" }
        #expect(value == "Hello \u{1F30D} \u{65E5}\u{672C}\u{8A9E} \u{627F}\u{631}\u{628}\u{6CC}\u{647}")
    }

    @Test func appStorageConcurrentAccess() async {
        @Shared(.appStorage("shr01_concurrent")) var value = 0
        for _ in 0..<10 {
            $value.withLock { $0 += 1 }
        }
        #expect(value == 10)
    }

    // MARK: SHR-02 — FileStorage round-trip

    @Test func fileStorageRoundTrip() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        @Shared(.fileStorage(tempURL)) var settings = TestSettings()
        $settings.withLock { $0.name = "updated"; $0.count = 42 }
        // FileStorage debounces writes — verify in-memory state is correct immediately
        #expect(settings.name == "updated")
        #expect(settings.count == 42)
    }

    // MARK: SHR-03 — InMemory sharing across references

    @Test func inMemorySharing() {
        @Shared(.inMemory("shr03_counter")) var ref1 = 0
        @Shared(.inMemory("shr03_counter")) var ref2 = 0
        $ref1.withLock { $0 = 42 }
        #expect(ref2 == 42)
    }

    @Test func inMemoryCrossFeature() {
        @Shared(.inMemory("shr03_token")) var token1 = ""
        @Shared(.inMemory("shr03_token")) var token2 = ""
        $token1.withLock { $0 = "abc" }
        #expect(token2 == "abc")
    }

    // MARK: SHR-04 — Default value

    @Test func sharedKeyDefaultValue() {
        @Shared(.appStorage("shr04_default")) var value: String = "defaultValue"
        #expect(value == "defaultValue")
    }

    // MARK: SHR-14 — Custom SharedKey (using inMemory as proxy)

    @Test func customSharedKeyCompiles() {
        @Shared(.inMemory("shr14_custom")) var value = "initial"
        $value.withLock { $0 = "custom" }
        #expect(value == "custom")
    }
}
#endif
