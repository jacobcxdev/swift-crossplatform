// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
import OSLog
import Foundation
@testable import LiteLibrary

let logger: Logger = Logger(subsystem: "LiteLibrary", category: "Tests")

@available(macOS 13, *)
final class LiteLibraryTests: XCTestCase {

    func testLiteLibrary() throws {
        logger.log("running testLiteLibrary")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testDecodeType() throws {
        // load the TestData.json file from the Resources folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("LiteLibrary", testData.testModuleName)
    }

}

struct TestData : Codable, Hashable {
    var testModuleName: String
}
