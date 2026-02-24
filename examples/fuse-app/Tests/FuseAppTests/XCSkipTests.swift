// Licensed under the GNU General Public License v3.0 or later
// SPDX-License-Identifier: GPL-3.0-or-later

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
