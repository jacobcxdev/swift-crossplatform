import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - ControlPanelView

struct ControlPanelView: View {
    let store: StoreOf<TestHarnessFeature>
    @State var expandedTabs: Set<String> = []
    @State var eventLogExpanded: Bool = false

    var body: some View {
        List {
            Section("Status") {
                if let running = store.runningScenarioID {
                    Label("Running: \(running)", systemImage: "play.fill")
                        .font(.caption).foregroundStyle(.orange)
                    if let step = store.currentStepDescription {
                        Text(step)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Label("Idle", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }

                Toggle("Pause on all checkpoints", isOn: Binding(
                    get: { store.breakOnAllCheckpoints },
                    set: { _ in store.send(.toggleBreakOnAllCheckpoints) }
                ))
                .font(.subheadline)
            }

            Section("Auto-Run") {
                if let autoID = LaunchConfig.autoRunScenario {
                    Text("Auto-run scenario: \(autoID)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Auto-run: disabled (manual mode)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Event Log (captures events from all tabs)
            Section {
                Button {
                    eventLogExpanded.toggle()
                } label: {
                    HStack {
                        Image(systemName: eventLogExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Event Log (\(store.eventLog.count))")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if eventLogExpanded {
                    if store.eventLog.isEmpty {
                        Text("No events yet")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Button {
                            store.send(.clearEventLog)
                        } label: {
                            Text("Clear Log")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)

                        ForEach(store.eventLog) { event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(event.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(event.kind.rawValue.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(colorForKind(event.kind))
                                    .frame(width: 80, alignment: .leading)
                                Text(event.detail)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            ForEach(TestHarnessFeature.State.Tab.allCases, id: \.rawValue) { tab in
                let scenarios = ScenarioRegistry.all.filter { $0.tab == tab }
                if !scenarios.isEmpty {
                    let selectedCount = scenarios.filter { store.selectedScenarioIDs.contains($0.id) }.count
                    let isExpanded = expandedTabs.contains(tab.rawValue)
                    Section {
                        Button {
                            if isExpanded {
                                expandedTabs.remove(tab.rawValue)
                            } else {
                                expandedTabs.insert(tab.rawValue)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(tab.displayName)
                                    .font(.headline)
                                Spacer()
                                Text("\(selectedCount)/\(scenarios.count)")
                                    .font(.caption)
                                    .foregroundStyle(selectedCount > 0 ? .blue : .secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if isExpanded {
                            let allSelected = selectedCount == scenarios.count
                            Button {
                                let ids = scenarios.map { $0.id }
                                store.send(.scenarioSetSelected(ids: ids, selected: !allSelected))
                            } label: {
                                Text(allSelected ? "Deselect All" : "Select All")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isScenarioRunning)

                            ForEach(scenarios) { scenario in
                                Button {
                                    store.send(.scenarioToggled(id: scenario.id))
                                } label: {
                                    HStack {
                                        Image(systemName: store.selectedScenarioIDs.contains(scenario.id)
                                              ? "checkmark.circle.fill" : "checkmark.circle")
                                            .foregroundStyle(store.selectedScenarioIDs.contains(scenario.id)
                                                             ? .blue : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scenario.name).font(.headline)
                                            Text(scenario.description)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isScenarioRunning)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Control Panel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        store.send(.resetAll)
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .disabled(store.isScenarioRunning)

                    Button {
                        let selected = ScenarioRegistry.all.filter {
                            store.selectedScenarioIDs.contains($0.id)
                        }
                        Task {
                            for scenario in selected {
                                let completed = await runScenario(scenario, store: store)
                                if !completed { break }
                            }
                        }
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(store.selectedScenarioIDs.isEmpty || store.isScenarioRunning)
                }
            }
        }
    }

    private func colorForKind(_ kind: EngineEvent.Kind) -> Color {
        switch kind {
        case .send: .blue
        case .uiCommand: .orange
        case .uiAck: .green
        case .reset: .red
        case .log: .primary
        case .checkpoint: .purple
        case .wait: .yellow
        }
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
