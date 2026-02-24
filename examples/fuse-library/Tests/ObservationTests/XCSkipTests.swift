// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation
import TestUtilities
#if os(macOS) || os(Linux)
import SkipTest

@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase, XCGradleHarness {
    public func testSkipModule() async throws {
        try XCTSkipIf(
            hasLocalForkPaths(relativeTo: #filePath),
            "skipstone cannot resolve local fork paths; use `skip android test` for Android verification"
        )
        try await runGradleTests()
    }
}
#endif
