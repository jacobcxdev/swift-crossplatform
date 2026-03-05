// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SecureFieldPlayground: View {
    @State var text = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SecureField("Default", text: $text)
                SecureField("With prompt", text: $text, prompt: Text("Prompt"))
                SecureField("Fixed width", text: $text)
                    .frame(width: 200)
                SecureField(".disabled(true)", text: $text)
                    .disabled(true)
                SecureField(".foregroundStyle(.red)", text: $text)
                    .foregroundStyle(.red)
                SecureField(".tint(.red)", text: $text)
                    .tint(.red)
            }
            .textFieldStyle(.roundedBorder)
            .padding()
        }
    }
}
