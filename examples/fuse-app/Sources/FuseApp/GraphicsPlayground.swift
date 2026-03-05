// Copyright 2023-2025 Skip
import SwiftUI

struct GraphicsPlayground: View {
    @State var isRotating3D = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("Standard")
                    Spacer()
                    ZStack {
                        sampleContent
                        Text("Hello")
                            .font(.title).bold()
                            .foregroundStyle(Color.red)
                    }
                    .frame(width: 200, height: 200)
                }
                HStack {
                    Text(".grayscale(0.99)")
                    Spacer()
                    ZStack {
                        sampleContent
                        Text("Hello")
                            .font(.title).bold()
                            .foregroundStyle(Color.red)
                    }
                    .frame(width: 200, height: 200)
                    .grayscale(0.99)
                }
                HStack {
                    Text(".grayscale(0.25)")
                    Spacer()
                    ZStack {
                        sampleContent
                        Text("Hello")
                            .font(.title).bold()
                            .foregroundStyle(Color.red)
                    }
                    .frame(width: 200, height: 200)
                    .grayscale(0.25)
                }
                HStack {
                    Text(".colorInvert()")
                    Spacer()
                    Image(systemName: "swift")
                        .resizable()
                        .scaledToFit()
                        .colorInvert()
                        .frame(width: 50, height: 50)
                    sampleContent
                        .foregroundStyle(Color.red)
                        .colorInvert()
                        .frame(width: 100, height: 100)
                    Text("123")
                        .foregroundStyle(Color.red)
                        .colorInvert()
                }
                Text(".rotation3DEffects")
                sampleContent
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotation3DEffect(.degrees(isRotating3D ? 0.0 : 360.0), axis: (x: 0, y: 1, z: 0))
                    .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: isRotating3D)
                    .onAppear { isRotating3D = true }
                sampleContent
                    .frame(width: 400, height: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotation3DEffect(.degrees(45.0), axis: (x: 1.0, y: 0.0, z: 0.0))
            }
            .padding()
        }
    }

    /// A colorful sample view used in place of the upstream Cat image.
    /// Uses a gradient with overlaid shapes to provide visually rich content
    /// for demonstrating graphics effects.
    private var sampleContent: some View {
        LinearGradient(
            colors: [.orange, .pink, .purple, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
