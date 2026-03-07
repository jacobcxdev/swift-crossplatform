// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import Foundation

@Reducer
public struct AlertFeature {
    @ObservableState
    public struct State: Equatable {
        public var value = ""
        public var data: Int? = nil
        public var titleIsPresented = false
        public var titleMessageIsPresented = false
        public var twoButtonsIsPresented = false
        public var threeButtonsIsPresented = false
        public var fiveButtonsIsPresented = false
        public var textFieldIsPresented = false
        public var secureFieldIsPresented = false
        public var textFieldText = ""
        public var secureFieldText = ""
        public var dataIsPresented = false
        public init() {}
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case titleButtonTapped
        case titleMessageButtonTapped
        case twoButtonsButtonTapped
        case threeButtonsButtonTapped
        case fiveButtonsButtonTapped
        case textFieldButtonTapped
        case secureFieldButtonTapped
        case dataIncrementTapped
        case dataNilTapped
        case dataPresentTapped
        case alertOptionSelected(String)
        case alertCancelTapped
        case alertDestructiveTapped
        case textFieldSubmitted
        case secureFieldSubmitted
        case dataAlertDataTapped(Int)
        case dataAlertNilTapped
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .titleButtonTapped:
                state.titleIsPresented = true
                return .none
            case .titleMessageButtonTapped:
                state.titleMessageIsPresented = true
                return .none
            case .twoButtonsButtonTapped:
                state.twoButtonsIsPresented = true
                return .none
            case .threeButtonsButtonTapped:
                state.threeButtonsIsPresented = true
                return .none
            case .fiveButtonsButtonTapped:
                state.fiveButtonsIsPresented = true
                return .none
            case .textFieldButtonTapped:
                state.textFieldIsPresented = true
                return .none
            case .secureFieldButtonTapped:
                state.secureFieldIsPresented = true
                return .none
            case .dataIncrementTapped:
                if state.data == nil {
                    state.data = 1
                } else {
                    state.data = state.data! + 1
                }
                return .none
            case .dataNilTapped:
                state.data = nil
                return .none
            case .dataPresentTapped:
                state.dataIsPresented = true
                return .none
            case .alertOptionSelected(let option):
                state.value = option
                return .none
            case .alertCancelTapped:
                state.value = "Custom Cancel"
                return .none
            case .alertDestructiveTapped:
                state.value = "Destructive"
                return .none
            case .textFieldSubmitted:
                state.value = state.textFieldText
                return .none
            case .secureFieldSubmitted:
                state.value = state.textFieldText
                return .none
            case .dataAlertDataTapped(let d):
                state.value = "\(d)"
                return .none
            case .dataAlertNilTapped:
                state.data = nil
                return .none
            }
        }
    }
}

public enum AlertPlaygroundError: LocalizedError, Sendable {
    case testError
}
