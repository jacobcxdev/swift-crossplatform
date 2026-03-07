// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import ComposableArchitecture
import SwiftUI

public struct AlertView: View {
    @Bindable var store: StoreOf<AlertFeature>

    public init(store: StoreOf<AlertFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(store.value).bold()
            Button("Title") {
                store.send(.titleButtonTapped)
            }
            Button("Title + Message") {
                store.send(.titleMessageButtonTapped)
            }
            Button("Two Buttons") {
                store.send(.twoButtonsButtonTapped)
            }
            Button("Three Buttons") {
                store.send(.threeButtonsButtonTapped)
            }
            Button("Five Buttons") {
                store.send(.fiveButtonsButtonTapped)
            }
            Divider()
            Button("Text Field") {
                store.send(.textFieldButtonTapped)
            }
            Button("Secure Field") {
                store.send(.secureFieldButtonTapped)
            }
            Divider()
            Text("Present with data")
            Button("Data: \(String(describing: store.data))") {
                store.send(.dataIncrementTapped)
            }
            Button("Nil data") {
                store.send(.dataNilTapped)
            }
            Button("Present") {
                store.send(.dataPresentTapped)
            }
        }
        .padding()
        .alert("Title", isPresented: $store.titleIsPresented) {
        }
        .alert("Title + Message", isPresented: $store.titleMessageIsPresented) {
        } message: {
            Text("This is the alert message to show beneath the title")
        }
        .alert("Two Buttons", isPresented: $store.twoButtonsIsPresented) {
            Button("Option") {
                store.send(.alertOptionSelected("Option"))
            }
            Button("Cancel", role: .cancel) {
                store.send(.alertCancelTapped)
            }
        }
        .alert("Three Buttons", isPresented: $store.threeButtonsIsPresented) {
            Button("Cancel", role: .cancel) {
                store.send(.alertCancelTapped)
            }
            Button("Option") {
                store.send(.alertOptionSelected("Option"))
            }
            Button("Destructive", role: .destructive) {
                store.send(.alertDestructiveTapped)
            }
        }
        .alert("Five Buttons", isPresented: $store.fiveButtonsIsPresented) {
            Button("Cancel", role: .cancel) {
                store.send(.alertCancelTapped)
            }
            Button("Destructive", role: .destructive) {
                store.send(.alertDestructiveTapped)
            }
            Button("Option 1") {
                store.send(.alertOptionSelected("Option 1"))
            }
            Button("Option 2") {
                store.send(.alertOptionSelected("Option 2"))
            }
            Button("Option 3") {
                store.send(.alertOptionSelected("Option 3"))
            }
        }
        .alert("Text Field", isPresented: $store.textFieldIsPresented) {
            TextField("Enter text", text: $store.textFieldText)
            Button("Submit") {
                store.send(.textFieldSubmitted)
            }
            Button("Cancel", role: .cancel) {
                store.send(.alertCancelTapped)
            }
        }
        .alert("Sign In", isPresented: $store.secureFieldIsPresented) {
            TextField("Username", text: $store.textFieldText)
            SecureField("Password", text: $store.secureFieldText)
            Button("Submit") {
                store.send(.secureFieldSubmitted)
            }
            Button("Cancel", role: .cancel) {
                store.send(.alertCancelTapped)
            }
        }
        .alert("Data", isPresented: $store.dataIsPresented, presenting: store.data) { d in
            Button("Data: \(d)") {
                store.send(.dataAlertDataTapped(d))
            }
            Button("Nil Data", role: .destructive) {
                store.send(.dataAlertNilTapped)
            }
        }
    }
}
