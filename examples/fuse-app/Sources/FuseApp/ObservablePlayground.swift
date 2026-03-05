// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import Observation
import SwiftUI

struct ObservablePlayground: View {
    var body: some View {
        ObservablesOuterView()
            .environment(PlaygroundEnvironmentObject(text: "initialEnvironment"))
    }
}

@Observable class PlaygroundEnvironmentObject {
    var text: String
    init(text: String) {
        self.text = text
    }
}

@Observable class PlaygroundObservable {
    var text = ""
    init(text: String) {
        self.text = text
    }
}

struct ObservablesOuterView: View {
    @State var stateObject = PlaygroundObservable(text: "initialState")
    @Environment(PlaygroundEnvironmentObject.self) var environmentObject
    var body: some View {
        VStack {
            Text(stateObject.text)
            Text(environmentObject.text)
            ObservablesObservableView(observable: stateObject)
                .border(Color.red)
            ObservablesBindingView(text: $stateObject.text)
                .border(Color.blue)
        }
    }
}

struct ObservablesObservableView: View {
    let observable: PlaygroundObservable
    @Environment(PlaygroundEnvironmentObject.self) var environmentObject
    var body: some View {
        Text(observable.text)
        Text(environmentObject.text)
        Button("Button") {
            observable.text = "observableState"
            environmentObject.text = "observableEnvironment"
        }
    }
}

struct ObservablesBindingView: View {
    @Binding var text: String
    var body: some View {
        Button("Button") {
            text = "bindingState"
        }
        .accessibilityIdentifier("binding-button")
    }
}
