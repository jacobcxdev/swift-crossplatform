// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import Foundation
import Observation
@testable import FuseApp

/// Thread-safe flag for use in @Sendable onChange closures.
private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

/// ViewModel observation tests — macOS only for now.
///
/// These live in a non-skipstone target because fuse-app depends on local fork
/// overrides (skip-android-bridge, skip-ui) which prevent Gradle builds.
/// Move to the skipstone-enabled FuseAppTests target once forks are merged upstream.
@available(macOS 14, iOS 17, *)
final class FuseAppViewModelTests: XCTestCase {

    private func makeViewModel() -> ViewModel {
        let vm = ViewModel()
        vm.items = [
            Item(title: "Alpha"),
            Item(title: "Beta"),
            Item(title: "Gamma"),
        ]
        return vm
    }

    func testViewModelItemsObservation() {
        let vm = makeViewModel()
        let flag = ObservationFlag()

        withObservationTracking {
            _ = vm.items
        } onChange: {
            flag.value = true
        }

        vm.items.append(Item(title: "Test Item"))
        XCTAssertTrue(flag.value, "onChange should fire when items mutated")
        XCTAssertEqual(vm.items.count, 4)
    }

    func testViewModelClearObservation() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.items.isEmpty)

        let flag = ObservationFlag()

        withObservationTracking {
            _ = vm.items
        } onChange: {
            flag.value = true
        }

        vm.clear()
        XCTAssertTrue(flag.value, "onChange should fire when items cleared")
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testViewModelSaveObservation() {
        let vm = makeViewModel()
        let firstItem = vm.items[0]

        let flag = ObservationFlag()

        withObservationTracking {
            _ = vm.items
        } onChange: {
            flag.value = true
        }

        var modified = firstItem
        modified.title = "Modified Title"
        vm.save(item: modified)
        XCTAssertTrue(flag.value, "onChange should fire when item saved")

        let saved = vm.items.first { $0.id == firstItem.id }
        XCTAssertEqual(saved?.title, "Modified Title")
    }

    func testViewModelDidSet() {
        let vm = makeViewModel()
        vm.items.append(Item(title: "didSet test"))
        XCTAssertEqual(vm.items.count, 4)
    }

    func testItemProperties() {
        let id = UUID()
        let date = Date.now
        let item = Item(id: id, date: date, favorite: true, title: "Test", notes: "Notes")

        XCTAssertEqual(item.id, id)

        let item2 = Item(id: id, date: date, favorite: true, title: "Test", notes: "Notes")
        XCTAssertEqual(item, item2)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try! encoder.encode(item)
        let decoded = try! decoder.decode(Item.self, from: data)
        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.title, item.title)
        XCTAssertEqual(decoded.favorite, item.favorite)
        XCTAssertEqual(decoded.notes, item.notes)
    }

    func testViewModelMultipleAccesses() {
        let vm = makeViewModel()
        let flag = ObservationFlag()

        withObservationTracking {
            _ = vm.items.count
            for _ in vm.items.prefix(3) { }
        } onChange: {
            flag.value = true
        }

        vm.items.append(Item(title: "Multi-access test"))
        XCTAssertTrue(flag.value, "onChange should fire for multiple accesses")
    }
}
