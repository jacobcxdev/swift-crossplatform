// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

private enum SafeAreaPlaygroundType: String, CaseIterable {
    case fullscreenContent
    case fullscreenBackground
    case plainList
    case plainListNoNavStack
    case list
    case bottomBar

    var title: String {
        switch self {
        case .fullscreenContent:
            return "Ignore safe area"
        case .fullscreenBackground:
            return "Background ignores safe area"
        case .plainList:
            return "Plain list"
        case .plainListNoNavStack:
            return "Plain list outside nav stack"
        case .list:
            return "List"
        case .bottomBar:
            return "Bottom toolbar"
        }
    }

    var coverId: String {
        rawValue + "Cover"
    }

    var sheetId: String {
        rawValue + "Sheet"
    }
}

struct SafeAreaPlayground: View {
    @State var isCoverPresented = false
    @State var isSheetPresented = false
    @State var playgroundType: SafeAreaPlaygroundType = .fullscreenContent

    var body: some View {
        List {
            NavigationLink("Background") {
                SafeAreaBackgroundView()
            }
            Section("Fullscreen cover") {
                ForEach(SafeAreaPlaygroundType.allCases, id: \.coverId) { playgroundType in
                    Button(playgroundType.title) {
                        self.playgroundType = playgroundType
                        isCoverPresented = true
                    }
                }
            }
            Section("Sheet") {
                ForEach(SafeAreaPlaygroundType.allCases, id: \.sheetId) { playgroundType in
                    Button(playgroundType.title) {
                        self.playgroundType = playgroundType
                        isSheetPresented = true
                    }
                }
            }
        }
        #if os(macOS)
        .sheet(isPresented: $isSheetPresented) {
            safeAreaPlaygroundContent(for: playgroundType)
        }
        #else
        .sheet(isPresented: $isSheetPresented) {
            safeAreaPlaygroundContent(for: playgroundType)
        }
        .fullScreenCover(isPresented: $isCoverPresented) {
            safeAreaPlaygroundContent(for: playgroundType)
        }
        #endif
    }

    @ViewBuilder private func safeAreaPlaygroundContent(
        for playgroundType: SafeAreaPlaygroundType
    ) -> some View {
        switch playgroundType {
        case .fullscreenContent:
            SafeAreaFullscreenContent()
        case .fullscreenBackground:
            SafeAreaFullscreenBackground()
        case .plainList:
            SafeAreaPlainList()
        case .plainListNoNavStack:
            SafeAreaPlainListNoNavStack()
        case .list:
            SafeAreaList()
        case .bottomBar:
            #if os(macOS)
            SafeAreaList()
            #else
            SafeAreaBottomBar()
            #endif
        }
    }
}

// MARK: - Sub-views

private struct SafeAreaBackgroundView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Button("Dismiss") {
            dismiss()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.yellow, ignoresSafeAreaEdges: .all)
    }
}

private struct SafeAreaFullscreenContent: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.yellow
            Button("Dismiss") {
                dismiss()
            }
        }
        .border(.blue, width: 20.0)
        .ignoresSafeArea()
    }
}

private struct SafeAreaFullscreenBackground: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.yellow
                .ignoresSafeArea()
            Button("Dismiss") {
                dismiss()
            }
        }
        .border(.blue, width: 20.0)
    }
}

private struct SafeAreaPlainList: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(0..<40) { index in
                Text("Row: \(index)")
            }
            .listStyle(.plain)
            .navigationTitle("Plain list")
            .toolbar {
                Button("Dismiss") {
                    dismiss()
                }
            }
        }
    }
}

private struct SafeAreaPlainListNoNavStack: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Button("Dismiss") { dismiss() }
            ForEach(0..<40) { index in
                Text("Row: \(index)")
            }
        }
        .listStyle(.plain)
    }
}

private struct SafeAreaList: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(0..<40) { index in
                Text("Row: \(index)")
            }
            .navigationTitle("List")
            .toolbar {
                Button("Dismiss") {
                    dismiss()
                }
            }
        }
    }
}

#if os(macOS)
#else
private struct SafeAreaBottomBar: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(0..<40) { index in
                Text("Row: \(index)")
            }
            .navigationTitle("Bottom toolbar")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button("Dismiss") {
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif
