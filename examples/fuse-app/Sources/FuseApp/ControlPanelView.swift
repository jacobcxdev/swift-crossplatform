import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - ControlPanelView

struct ControlPanelView: View {
    let store: StoreOf<TestHarnessFeature>

    var body: some View {
        List {
            Section("Auto-Run") {
                if let autoID = LaunchConfig.autoRunScenario {
                    Text("Auto-run scenario: \(autoID)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Auto-run: disabled (manual mode)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Scenarios") {
                ForEach(ScenarioRegistry.all) { scenario in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scenario.name)
                                .font(.headline)
                            Text(scenario.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ScenarioRunControl(
                            isRunning: store.runningScenarioID == scenario.id,
                            isDisabled: store.isScenarioRunning,
                            action: {
                                Task {
                                    await runScenario(scenario, store: store)
                                }
                            }
                        )
                    }
                }
            }

            Section("Status") {
                if let running = store.runningScenarioID {
                    Label("Running: \(running)", systemImage: "play.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Idle", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Control Panel")
    }
}

struct ScenarioRunControl: View {
    let isRunning: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isRunning {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Button(action: action) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.bordered)
                .frame(width: 44, height: 44)
                .disabled(isDisabled)
            }
        }
        .frame(width: 44, height: 44)
    }
}

#if !os(Android)
#Preview("Control Panel") {
    NavigationStack {
        ControlPanelView(
            store: Store(
                initialState: TestHarnessFeature.State(
                    selectedTab: .control,
                    runningScenarioID: ScenarioRegistry.foreachNamespaceAddCard.id
                )
            ) {
                TestHarnessFeature()
            }
        )
    }
}
#endif
