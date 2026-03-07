// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture

@Reducer
public struct ToggleFeature {
    @ObservableState
    public struct State: Equatable {
        public var isOn = false
        public init(isOn: Bool = false) {
            self.isOn = isOn
        }
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
    }
}
