// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct NotificationPlayground: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.largeTitle)
            Text("Not Yet Ported")
                .font(.title2)
            Text("This playground requires SkipKit and SkipNotify platform-specific APIs.")
                .foregroundStyle(.secondary)
        }
    }
}
