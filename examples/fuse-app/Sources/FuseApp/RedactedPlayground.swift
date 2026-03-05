// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct RedactedPlayground: View {
    var body: some View {
        List {
            Section(".placeholder on Text") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This text is redacted")
                        .font(.headline)
                    Text("Secondary information that should be hidden behind a placeholder shimmer effect.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .redacted(reason: .placeholder)
                .padding(.vertical, 4)
            }
            Section(".placeholder on Image") {
                HStack {
                    Image(systemName: "photo")
                        .resizable()
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading) {
                        Text("Image with caption")
                            .font(.headline)
                        Text("This demonstrates redaction on mixed content.")
                            .font(.caption)
                    }
                }
                .redacted(reason: .placeholder)
                .padding(.vertical, 4)
            }
            Section(".placeholder on Form-like content") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text("John Doe")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Email")
                        Spacer()
                        Text("john@example.com")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Phone")
                        Spacer()
                        Text("+1 555-0123")
                            .foregroundStyle(.secondary)
                    }
                }
                .redacted(reason: .placeholder)
                .padding(.vertical, 4)
            }
            Section("Not redacted (comparison)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This text is NOT redacted")
                        .font(.headline)
                    Text("You can read this text normally for comparison with the sections above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
