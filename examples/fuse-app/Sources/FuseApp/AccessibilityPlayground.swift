// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AccessibilityPlayground: View {
    @State var isOn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Simulate a custom control with an accessibility label, value, and traits:")
                Text(isOn ? "+" : "-").font(.largeTitle)
                    .accessibilityLabel("My custom control")
                    .accessibilityValue(isOn ? "On" : "Off")
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { isOn = !isOn }

                Divider()

                Text("Hide the following element from accessibility:")
                Text("Hidden").font(.largeTitle)
                    .accessibilityHeading(.h2)
                    .accessibilityHidden(true)
            }
            .padding()
        }
    }
}
