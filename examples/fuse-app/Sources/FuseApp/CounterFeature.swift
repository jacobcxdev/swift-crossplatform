import ComposableArchitecture
import SwiftUI

// MARK: - CounterFeature Reducer

@Reducer
struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        var fact: String?
        var isLoadingFact = false
        var totalChanges = 0
    }

    @CasePathable
    enum Action: ViewAction {
        case view(View)
        case factResponse(Result<String, Error>)
        case incrementResponse

        @CasePathable
        enum View {
            case incrementButtonTapped
            case decrementButtonTapped
            case factButtonTapped
            case delayedIncrementButtonTapped
            case resetButtonTapped
        }
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.numberFact) var numberFact

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.incrementButtonTapped):
                state.count += 1
                state.fact = nil
                state.totalChanges += 1
                return .none

            case .view(.decrementButtonTapped):
                state.count -= 1
                state.fact = nil
                state.totalChanges += 1
                return .none

            case .view(.factButtonTapped):
                state.isLoadingFact = true
                state.fact = nil
                return .run { [count = state.count] send in
                    let fact = try await numberFact.fetch(count)
                    await send(.factResponse(.success(fact)))
                } catch: { error, send in
                    await send(.factResponse(.failure(error)))
                }

            case let .factResponse(.success(fact)):
                state.isLoadingFact = false
                state.fact = fact
                state.totalChanges += 1
                return .none

            case .factResponse(.failure):
                state.isLoadingFact = false
                state.fact = "Could not load fact."
                state.totalChanges += 1
                return .none

            case .view(.delayedIncrementButtonTapped):
                return .run { send in
                    try await clock.sleep(for: .seconds(1))
                    await send(.incrementResponse)
                }

            case .incrementResponse:
                state.count += 1
                state.totalChanges += 1
                return .none

            case .view(.resetButtonTapped):
                state.count = 0
                state.fact = nil
                state.isLoadingFact = false
                state.totalChanges += 1
                return .none
            }
        }
        .onChange(of: \.count) { _, _ in
            Reduce { state, _ in
                return .none
            }
        }
    }
}

// MARK: - CounterView

@ViewAction(for: CounterFeature.self)
struct CounterView: View {
    @Bindable var store: StoreOf<CounterFeature>

    var body: some View {
        List {
            Section("Counter") {
                HStack {
                    Button("-") { send(.decrementButtonTapped) }
                        .buttonStyle(.borderless)
                    Text("\(store.count)")
                        .font(.title2)
                        .frame(maxWidth: .infinity)
                    Button("+") { send(.incrementButtonTapped) }
                        .buttonStyle(.borderless)
                }

                Button("Delayed +1") { send(.delayedIncrementButtonTapped) }
                Button("Reset") { send(.resetButtonTapped) }
            }

            Section("Fact") {
                Button("Get Fact") { send(.factButtonTapped) }
                    .disabled(store.isLoadingFact)
                if store.isLoadingFact {
                    ProgressView()
                }
                if let fact = store.fact {
                    Text(fact)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Stats") {
                HStack {
                    Text("Total Changes")
                    Spacer()
                    Text("\(store.totalChanges)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Counter")
    }
}
