// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct NotificationPlayground: View {
    var body: some View {
        ContentUnavailableView(
            "Not Yet Ported",
            systemImage: "bell",
            description: Text("This playground requires SkipKit and SkipNotify platform-specific APIs.")
        )
    }
}
