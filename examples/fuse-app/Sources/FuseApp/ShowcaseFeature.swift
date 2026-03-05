// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SwiftUI

// MARK: - PlaygroundPlaceholderFeature

@Reducer
struct PlaygroundPlaceholderFeature {
    @ObservableState
    struct State: Equatable {
        let type: PlaygroundType
    }

    enum Action {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

// MARK: - ShowcasePath

@Reducer(state: .equatable)
enum ShowcasePath {
    case playground(PlaygroundPlaceholderFeature)
}

// MARK: - ShowcaseFeature

@Reducer
struct ShowcaseFeature {
    @ObservableState
    struct State: Equatable {
        var path = StackState<ShowcasePath.State>()
        var searchText: String = ""

        var filteredPlaygrounds: [PlaygroundType] {
            let trimmed = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return PlaygroundType.allCases }
            return PlaygroundType.allCases.filter { playground in
                let words = playground.title.split(separator: " ")
                return words.contains { $0.lowercased().hasPrefix(trimmed) }
            }
        }
    }

    @CasePathable
    enum Action {
        case path(StackActionOf<ShowcasePath>)
        case playgroundTapped(PlaygroundType)
        case searchTextChanged(String)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .path:
                return .none
            case .playgroundTapped(let type):
                state.path.append(.playground(.init(type: type)))
                return .none
            case .searchTextChanged(let text):
                state.searchText = text
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            ShowcasePath.body
        }
    }
}

// MARK: - ShowcaseView

struct ShowcaseView: View {
    @Bindable var store: StoreOf<ShowcaseFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                ForEach(store.filteredPlaygrounds, id: \.self) { playground in
                    NavigationLink(state: ShowcasePath.State.playground(.init(type: playground))) {
                        Label(playground.title, systemImage: playground.systemImage)
                    }
                }
            }
            .navigationTitle("Showcase")
            .searchable(text: $store.searchText.sending(\.searchTextChanged))
        } destination: { pathStore in
            switch pathStore.case {
            case .playground(let playgroundStore):
                Text("Playground: \(playgroundStore.type.title)")
                    .navigationTitle(playgroundStore.type.title)
            }
        }
    }
}
