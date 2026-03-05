// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from skipapp-showcase-fuse ScenePhasePlayground.swift

import SwiftUI

struct ScenePhasePlayground: View {
    @Environment(\.scenePhase) var scenePhase
    @State var history: [ScenePhase] = []

    var body: some View {
        List {
            Section("ScenePhase history") {
                ForEach(Array(history.enumerated()), id: \.offset) { phase in
                    Text(verbatim: String(describing: phase.element))
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            logger.log("onChange(of: scenePhase): \(String(describing: phase))")
            history.append(phase)
        }
    }
}
