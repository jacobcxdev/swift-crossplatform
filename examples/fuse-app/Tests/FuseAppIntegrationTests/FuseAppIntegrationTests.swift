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
        #expect(store.state.selectedTab == .control)
        #expect(store.state.pendingUICommand == nil)
        #expect(store.state.isScenarioRunning == false)
        #expect(store.state.eventLog.isEmpty)
    }

    @Test func resetAllClearsPendingCommand() async {
        let store = TestStore(
            initialState: TestHarnessFeature.State(pendingUICommand: .scrollToTop)
        ) {
            TestHarnessFeature()
        }

        await store.send(.resetAll) {
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
#endif
