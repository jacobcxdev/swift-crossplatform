// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SkipFuse

private let logger = Logger(subsystem: "dev.jacobcx.fuseApp", category: "SQLItemEditor")

@Reducer
public struct SQLItemEditorFeature {
    @ObservableState
    public struct State: Equatable {
        public var item: SQLItem

        public init(item: SQLItem) {
            logger.debug("SQLItemEditorFeature.State.init item.id=\(item.id)")
            self.item = item
        }
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveTapped
    }

    @Dependency(\.dismiss) var dismiss
    @Dependency(\.sqlClient) var sqlClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .saveTapped:
                let itemId = state.item.id
                logger.debug("SQLItemEditorFeature: .saveTapped id=\(itemId)")
                let item = state.item
                return .run { [sqlClient, dismiss] _ in
                    logger.debug("SQLItemEditorFeature: updating item")
                    try await sqlClient.update(item)
                    logger.debug("SQLItemEditorFeature: dismissing")
                    await dismiss()
                } catch: { error, _ in
                    logger.error("SQLItemEditorFeature: save FAILED: \(error)")
                }
            }
        }
    }
}
