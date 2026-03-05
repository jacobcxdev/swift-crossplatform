// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LottiePlayground: View {
    var body: some View {
        ContentUnavailableView(
            "Not Yet Ported",
            systemImage: "play.rectangle",
            description: Text("This playground requires platform-specific APIs.")
        )
    }
}
