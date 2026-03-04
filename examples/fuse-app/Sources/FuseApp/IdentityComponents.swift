import ComposableArchitecture
import SkipFuse
import SwiftUI

// MARK: - Identity Logging

private let identityLogger = Logger(subsystem: "fuse.app", category: "Identity")
func idLog(_ msg: String) {
    identityLogger.debug("\(msg)")
}

// MARK: - CardItem

struct CardItem: Equatable, Identifiable {
    let id: UUID
    var title: String
}

// MARK: - LocalCounterFeature Reducer

@Reducer
struct LocalCounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
    }

    enum Action {
        case decrementButtonTapped
        case incrementButtonTapped
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
            }
        }
    }
}

// MARK: - CounterCard View

/// A view with constructor params (title) + let-with-default (store, instanceID).
/// Exercises the transpiler's mixed-view peer remembering (Plan 05 fix).
struct CounterCard: View {
    let title: String
    let store = Store(initialState: LocalCounterFeature.State()) {
        LocalCounterFeature()
    }
    let instanceID = UUID()

    var body: some View {
        let _ = idLog("[CounterCard] body: title=\(title) instanceID=\(instanceID.uuidString.prefix(8)) count=\(store.count)")
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(instanceID.uuidString.prefix(8))
                    .font(.caption).monospaced()
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

// MARK: - PeerRememberTestView

/// A purpose-built view for peer remembering tests.
/// Has @State + let-with-default but NO constructor params.
/// Exercises the transpiler's unconditional peer remembering (no input hash needed).
struct PeerRememberTestView: View {
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
