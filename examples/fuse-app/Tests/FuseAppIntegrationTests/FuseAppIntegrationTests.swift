#if !SKIP
import ComposableArchitecture
import Foundation
import Testing
@testable import FuseApp

// MARK: - TestHarnessFeature Integration Tests

@Suite(.serialized) @MainActor
struct TestHarnessFeatureTests {

    @Test func initialState() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }
        #expect(store.state.selectedTab == .showcase)
        #expect(store.state.showcase == ShowcaseFeature.State())
        #expect(store.state.pendingUICommand == nil)
        #expect(store.state.isScenarioRunning == false)
        #expect(store.state.eventLog.isEmpty)
    }

    @Test func resetAllClearsPendingCommandAndShowcase() async {
        var initialState = TestHarnessFeature.State(pendingUICommand: .scrollToTop)
        initialState.showcase.searchText = "test"
        let store = TestStore(initialState: initialState) {
            TestHarnessFeature()
        }

        await store.send(.resetAll) {
            $0.showcase = ShowcaseFeature.State()
            $0.pendingUICommand = nil
        }
    }

    @Test func executeAndCancelUICommand() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        await store.send(.executeUICommand(.scrollToBottom)) {
            $0.pendingUICommand = .scrollToBottom
        }

        await store.send(.cancelUICommand) {
            $0.pendingUICommand = nil
        }
    }

    @Test func scenarioLifecycle() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        await store.send(.scenarioStarted(id: "test-scenario")) {
            $0.runningScenarioID = "test-scenario"
        }

        #expect(store.state.isScenarioRunning == true)

        await store.send(.scenarioStepChanged(description: "Step 1")) {
            $0.currentStepDescription = "Step 1"
        }

        await store.send(.scenarioEnded) {
            $0.runningScenarioID = nil
            $0.currentStepDescription = nil
            $0.executionMode = .playing
            $0.currentStepIndex = 0
            $0.totalStepCount = 0
        }

        #expect(store.state.isScenarioRunning == false)
    }

    @Test func eventLogAppendAndClear() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        let event = EngineEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 0),
            kind: .log,
            detail: "test event"
        )

        await store.send(.eventLogAppend(event)) {
            $0.eventLog = [event]
        }

        await store.send(.clearEventLog) {
            $0.eventLog = []
        }
    }
}

// MARK: - ShowcaseFeature Tests

@Suite(.serialized) @MainActor
struct ShowcaseFeatureTests {

    @Test func playgroundTapped() async {
        let store = TestStore(initialState: ShowcaseFeature.State()) {
            ShowcaseFeature()
        }

        await store.send(.playgroundTapped(.alert)) {
            $0.path[id: 0] = .playground(.init(type: .alert))
        }
    }

    @Test func searchFiltering() async {
        let store = TestStore(initialState: ShowcaseFeature.State()) {
            ShowcaseFeature()
        }

        await store.send(.searchTextChanged("But")) {
            $0.searchText = "But"
        }

        // "But" should match "Button" (word prefix)
        #expect(store.state.filteredPlaygrounds == [.button])
    }

    @Test func searchEmptyShowsAll() async {
        var initialState = ShowcaseFeature.State()
        initialState.searchText = "But"
        let store = TestStore(initialState: initialState) {
            ShowcaseFeature()
        }

        #expect(store.state.filteredPlaygrounds.count == 1)

        await store.send(.searchTextChanged("")) {
            $0.searchText = ""
        }

        #expect(store.state.filteredPlaygrounds.count == 84)
        #expect(store.state.filteredPlaygrounds == PlaygroundType.allCases)
    }

    @Test func navigationPopRemovesFromPath() async {
        var initialState = ShowcaseFeature.State()
        initialState.path.append(.playground(.init(type: .color)))
        initialState.path.append(.playground(.init(type: .grid)))

        let store = TestStore(initialState: initialState) {
            ShowcaseFeature()
        }

        #expect(store.state.path.count == 2)

        await store.send(.path(.popFrom(id: store.state.path.ids.last!))) {
            $0.path.removeLast()
        }
    }

    @Test func tabSwitching() async {
        let store = TestStore(initialState: TestHarnessFeature.State()) {
            TestHarnessFeature()
        }

        #expect(store.state.selectedTab == .showcase)

        await store.send(.tabSelected(.control)) {
            $0.selectedTab = .control
        }

        await store.send(.tabSelected(.showcase)) {
            $0.selectedTab = .showcase
        }
    }

    @Test func resetAllClearsShowcasePath() async {
        var initialState = TestHarnessFeature.State()
        initialState.showcase.path.append(.playground(.init(type: .alert)))
        initialState.showcase.searchText = "test"

        let store = TestStore(initialState: initialState) {
            TestHarnessFeature()
        }

        await store.send(.resetAll) {
            $0.showcase = ShowcaseFeature.State()
            $0.pendingUICommand = nil
        }

        #expect(store.state.showcase.path.isEmpty)
        #expect(store.state.showcase.searchText.isEmpty)
    }
}
#endif
