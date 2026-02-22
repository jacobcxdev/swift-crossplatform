import ComposableArchitecture
import XCTest
@testable import FuseApp

// Placeholder — full integration tests added in Task 2
final class FuseAppIntegrationTests: XCTestCase {
    @MainActor func testAppStoreInitializes() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        XCTAssertEqual(store.state.selectedTab, .counter)
    }
}
