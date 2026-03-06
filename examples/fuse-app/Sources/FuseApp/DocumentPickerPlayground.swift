// Copyright 2023–2025 Skip
import Foundation
import SwiftUI
#if canImport(SkipKit)
import SkipKit
#endif

/// This component uses the `SkipKit` module from https://source.skip.tools/skip-kit
struct DocumentPickerPlayground: View {
#if canImport(SkipKit)
    @State var presentPreview = false
    @State var presentCamera = false
    @State var presentMediaPicker = false
    @State var selectedDocument: URL? = nil
    @State var filename: String? = nil
    @State var mimeType: String? = nil

    var body: some View {
        VStack(alignment: .center) {
            HStack {
                Button("Pick Document") {
                    presentPreview = true
                }
                .buttonStyle(.borderedProminent)
                .withDocumentPicker(isPresented: $presentPreview, allowedContentTypes: [.image, .pdf], selectedDocumentURL: $selectedDocument, selectedFilename: $filename, selectedFileMimeType: $mimeType)

                Button("Take Photo") {
                    presentCamera = true
                }
                .buttonStyle(.borderedProminent)
                .withMediaPicker(type: .camera, isPresented: $presentCamera, selectedImageURL: $selectedDocument)

                Button("Select Media") {
                    presentMediaPicker = true
                }
                .buttonStyle(.borderedProminent)
                .withMediaPicker(type: .library, isPresented: $presentMediaPicker, selectedImageURL: $selectedDocument)
            }

            if let selectedDocument {
                Text("Selected Image: \(selectedDocument.lastPathComponent)")
                    .font(.callout)
                AsyncImage(url: selectedDocument) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
            }
        }
    }
#else
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.largeTitle)
            Text("Requires SkipKit")
                .font(.title2)
            Text("Add skip-kit dependency to enable document picking, camera, and media selection.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
#endif
}
