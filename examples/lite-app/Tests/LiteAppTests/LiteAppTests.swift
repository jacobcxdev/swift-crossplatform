// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import OSLog
import Foundation
@testable import LiteApp

let logger: Logger = Logger(subsystem: "LiteApp", category: "Tests")

@available(macOS 13, *)
final class LiteAppTests: XCTestCase {

    func testLiteApp() throws {
        logger.log("running testLiteApp")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testDecodeType() throws {
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("LiteApp", testData.testModuleName)
    }

}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
