// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct KeychainPlayground: View {
    var body: some View {
        ContentUnavailableView(
            "Not Yet Ported",
            systemImage: "key",
            description: Text("This playground requires platform-specific APIs.")
        )
    }
}
