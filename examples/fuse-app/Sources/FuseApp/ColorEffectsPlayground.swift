// Copyright 2023-2025 Skip
import SwiftUI

struct ColorEffectsPlayground: View {
    @State internal var brightnessValue: Double = 0.0
    @State internal var contrastValue: Double = 1.0
    @State internal var saturationValue: Double = 1.0
    @State internal var hueRotationValue: Double = 0.0
    @State internal var showColorInvert: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Reference image
                Section {
                    VStack(spacing: 8) {
                        Text("Original (no effects)")
                            .font(.headline)
                        sampleContent
                    }
                }

                Divider()

                // Brightness
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("brightness(\(brightnessValue, specifier: "%.2f"))")
                                .font(.headline)
                            Spacer()
                        }
                        sampleContent
                            .brightness(brightnessValue)
                        Slider(value: $brightnessValue, in: -1.0...1.0)
                        Text("Range: -1.0 (black) to 1.0 (white)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Contrast
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("contrast(\(contrastValue, specifier: "%.2f"))")
                                .font(.headline)
                            Spacer()
                        }
                        sampleContent
                            .contrast(contrastValue)
                        Slider(value: $contrastValue, in: 0.0...2.0)
                        Text("Range: 0.0 (gray) to 2.0 (high contrast)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Saturation
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("saturation(\(saturationValue, specifier: "%.2f"))")
                                .font(.headline)
                            Spacer()
                        }
                        sampleContent
                            .saturation(saturationValue)
                        Slider(value: $saturationValue, in: 0.0...3.0)
                        Text("Range: 0.0 (grayscale) to 3.0 (oversaturated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Hue Rotation
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("hueRotation(\(Int(hueRotationValue))\u{00B0})")
                                .font(.headline)
                            Spacer()
                        }
                        sampleContent
                            .hueRotation(.degrees(hueRotationValue))
                        Slider(value: $hueRotationValue, in: 0...360)
                        Text("Rotates all colors around the color wheel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Color Invert
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("colorInvert()")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $showColorInvert)
                                .labelsHidden()
                        }
                        if showColorInvert {
                            sampleContent
                                .colorInvert()
                        } else {
                            sampleContent
                        }
                        Text("Inverts all colors (like a photo negative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Color Multiply
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("colorMultiply(_:)")
                                .font(.headline)
                            Spacer()
                        }
                        HStack(spacing: 12) {
                            VStack {
                                sampleContent
                                    .colorMultiply(.red)
                                Text(".red")
                                    .font(.caption)
                            }
                            VStack {
                                sampleContent
                                    .colorMultiply(.green)
                                Text(".green")
                                    .font(.caption)
                            }
                            VStack {
                                sampleContent
                                    .colorMultiply(.blue)
                                Text(".blue")
                                    .font(.caption)
                            }
                        }
                        Text("Multiplies each pixel by the given color")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Combined Effects
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Combined effects")
                                .font(.headline)
                            Spacer()
                        }
                        sampleContent
                            .saturation(0.5)
                            .brightness(0.1)
                            .contrast(1.2)
                        Text(".saturation(0.5).brightness(0.1).contrast(1.2)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // On shapes/colors
                Section {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Effects on shapes")
                                .font(.headline)
                            Spacer()
                        }
                        HStack(spacing: 20) {
                            VStack {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 60, height: 60)
                                Text("Original")
                                    .font(.caption)
                            }
                            VStack {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 60, height: 60)
                                    .brightness(0.3)
                                Text("brightness")
                                    .font(.caption)
                            }
                            VStack {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 60, height: 60)
                                    .saturation(0)
                                Text("saturation(0)")
                                    .font(.caption)
                            }
                            VStack {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 60, height: 60)
                                    .colorInvert()
                                Text("colorInvert")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    /// A colorful sample view used in place of the upstream Cat image.
    /// Uses a gradient with overlaid shapes to provide rich color content
    /// for demonstrating color effects.
    private var sampleContent: some View {
        ZStack {
            LinearGradient(
                colors: [.red, .orange, .yellow, .green, .blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                Image(systemName: "moon.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
