import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - Identity Logging

private let identityLogger = Logger(subsystem: "fuse.app", category: "Identity")
func idLog(_ msg: String) {
    identityLogger.debug("\(msg)")
}

// MARK: - LocalCounterFeature Reducer

@Reducer
struct LocalCounterFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var title: String
        var count = 0
    }

    enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
        case reset
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .decrementButtonTapped:
                state.count -= 1
                return .none
            case .incrementButtonTapped:
                state.count += 1
                return .none
            case .reset:
                state.count = 0
                return .none
            }
        }
    }
}

// MARK: - CounterCardView (TCA-scoped)

/// A card view backed by a parent-scoped store via TCA `.forEach`.
struct CounterCardView: View {
    let store: StoreOf<LocalCounterFeature>

    var body: some View {
        let _ = idLog("[CounterCard] body: title=\(store.title) count=\(store.count)")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.title).font(.headline)
                Spacer()
                Text("id: \(store.id.uuidString.prefix(8))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("-") { store.send(.decrementButtonTapped) }
                    .buttonStyle(.borderless)
                Text("\(store.count)")
                    .font(.title3).frame(minWidth: 40)
                Button("+") { store.send(.incrementButtonTapped) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CounterCard (standalone, for peer survival tests)

/// A standalone counter card with its own store. Used by Peer Survival tab
/// to test transpiler peer remembering (let-with-default store creation).
struct CounterCard: View {
    var title: String
    var externalIncrementTrigger: Int = 0
    var externalResetTrigger: Int = 0
    let store = Store(initialState: LocalCounterFeature.State(id: UUID(), title: "")) {
        LocalCounterFeature()
    }
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[CounterCard] body: title=\(title) count=\(store.count) instanceID=\(instanceID.uuidString.prefix(8))")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("id: \(instanceID.uuidString.prefix(8))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("-") { store.send(.decrementButtonTapped) }
                    .buttonStyle(.borderless)
                Text("\(store.count)")
                    .font(.title3).frame(minWidth: 40)
                Button("+") { store.send(.incrementButtonTapped) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: externalIncrementTrigger) { _, _ in store.send(.incrementButtonTapped) }
        .onChange(of: externalResetTrigger) { _, _ in store.send(.reset) }
    }
}

// MARK: - PeerRememberTestView

/// A purpose-built view for peer remembering tests.
/// Has @State + let-with-default but NO constructor params.
/// Exercises the transpiler's unconditional peer remembering (no input hash needed).
struct PeerRememberTestView: View {
    var externalTapTrigger: Int = 0
    var externalResetTrigger: Int = 0
    @State var tapCount: Int = 0
    let color: Color = .blue
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[PeerRememberTestView] body: tapCount=\(tapCount) instanceID=\(instanceID.uuidString.prefix(8))")
        Button {
            tapCount += 1
        } label: {
            Text("Taps: \(tapCount) (id: \(instanceID.uuidString.prefix(8)))")
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onChange(of: externalTapTrigger) { _, _ in tapCount += 1 }
        .onChange(of: externalResetTrigger) { _, _ in tapCount = 0 }
    }
}

// MARK: - SectionHeaderView

struct SectionHeaderView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Section \(number): \(title)")
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
