// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct IconPlayground: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(iconNames.enumerated()), id: \.offset) { iconIndexName in
                    iconRow(iconIndexName.element, index: iconIndexName.offset)
                }
            }
            .padding()
        }
    }

    func iconRow(_ imageName: String, index: Int) -> some View {
        HStack {
            Text(imageName)
            Spacer()
            Image(systemName: imageName)
                .foregroundStyle(iconColors[index % iconColors.count])
                .font(.title2)
        }
    }
}

private let iconColors: [Color] = [
    .blue, .red, .green, .yellow, .orange,
    .brown, .cyan, .indigo, .mint, .yellow,
    .pink, .purple, .teal,
]

/// SF Symbol names used for icon demos.
private let iconNames: [String] = [
    "star.fill",
    "heart.fill",
    "circle.fill",
    "square.fill",
    "triangle.fill",
    "diamond.fill",
    "hexagon.fill",
    "shield.fill",
    "bell.fill",
    "bookmark.fill",
    "flag.fill",
    "tag.fill",
    "bolt.fill",
    "flame.fill",
    "drop.fill",
    "leaf.fill",
    "moon.fill",
    "sun.max.fill",
    "cloud.fill",
    "snowflake",
    "wind",
    "tornado",
    "globe",
    "map.fill",
    "location.fill",
    "house.fill",
    "building.2.fill",
    "car.fill",
    "bicycle",
    "airplane",
    "bus.fill",
    "tram.fill",
    "ferry.fill",
    "phone.fill",
    "envelope.fill",
    "paperplane.fill",
    "calendar",
    "clock.fill",
    "alarm.fill",
    "timer",
    "stopwatch.fill",
    "camera.fill",
    "photo.fill",
    "video.fill",
    "music.note",
    "mic.fill",
    "speaker.wave.3.fill",
    "headphones",
    "gift.fill",
    "cart.fill",
    "bag.fill",
    "creditcard.fill",
    "banknote.fill",
    "doc.fill",
    "folder.fill",
    "tray.fill",
    "archivebox.fill",
    "book.fill",
    "newspaper.fill",
    "magazine.fill",
    "pencil",
    "highlighter",
    "paintbrush.fill",
    "paintpalette.fill",
    "hammer.fill",
    "wrench.fill",
    "scissors",
    "ruler.fill",
    "lock.fill",
    "key.fill",
    "pin.fill",
    "link",
    "wifi",
    "antenna.radiowaves.left.and.right",
    "battery.100",
    "lightbulb.fill",
    "power",
    "gear",
    "gearshape.fill",
    "person.fill",
    "person.2.fill",
    "person.3.fill",
    "hand.raised.fill",
    "hand.thumbsup.fill",
    "hand.thumbsdown.fill",
    "eye.fill",
    "nose.fill",
    "mouth.fill",
    "brain.head.profile",
    "heart.text.square.fill",
    "cross.fill",
    "staroflife.fill",
    "pills.fill",
    "bandage.fill",
    "stethoscope",
    "pawprint.fill",
    "hare.fill",
    "tortoise.fill",
    "fish.fill",
    "ant.fill",
    "ladybug.fill",
]
