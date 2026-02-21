// Licensed under the GNU General Public License v3.0 with Linking Exception
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception

import Foundation

public class FuseLibraryModule {

    public static func createFuseLibraryType(id: UUID, delay: Double? = nil) async throws -> FuseLibraryType {
        if let delay = delay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return FuseLibraryType(id: id)
    }

    /// An example of a type that can be bridged between Swift and Kotlin
    public struct FuseLibraryType: Identifiable, Hashable, Codable {
        public var id: UUID
    }
}
