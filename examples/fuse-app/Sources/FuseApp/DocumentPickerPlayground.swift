// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct DocumentPickerPlayground: View {
    var body: some View {
        ContentUnavailableView(
            "Not Yet Ported",
            systemImage: "doc.badge.plus",
            description: Text("This playground requires platform-specific APIs.")
        )
    }
}
