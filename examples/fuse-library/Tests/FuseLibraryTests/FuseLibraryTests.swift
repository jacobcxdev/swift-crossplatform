// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import XCTest
#if canImport(OSLog)
import OSLog
#endif
import Foundation
import SkipBridge
@testable import FuseLibrary

#if canImport(OSLog)
let logger: Logger = Logger(subsystem: "FuseLibrary", category: "Tests")
#endif

@available(macOS 13, *)
final class FuseLibraryTests: XCTestCase {
    override func setUp() {
        #if os(Android)
        // needed to load the compiled bridge from the transpiled tests
        loadPeerLibrary(packageName: "fuse-library", moduleName: "FuseLibrary")
        #endif
    }

    func testFuseLibrary() throws {
        #if canImport(OSLog)
        logger.log("running testFuseLibrary")
        #endif
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

    func testAsyncThrowsFunction() async throws {
        let id = UUID()
        let type: FuseLibraryModule.FuseLibraryType = try await FuseLibraryModule.createFuseLibraryType(id: id, delay: 0.001)
        XCTAssertEqual(id, type.id)
    }

}
