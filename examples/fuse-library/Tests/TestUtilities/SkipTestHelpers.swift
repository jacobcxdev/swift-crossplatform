import Foundation

/// True when running in a transpiled Java runtime environment
public let isJava = ProcessInfo.processInfo.environment["java.io.tmpdir"] != nil
/// True when running within an Android environment (either an emulator or device)
public let isAndroid = isJava && ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil
/// True when the transpiled code is currently running in the local Robolectric test environment
public let isRobolectric = isJava && !isAndroid
/// True if the system's `Int` type is 32-bit.
public let is32BitInteger = Int64(Int.max) == Int64(Int32.max)

/// Check if local fork paths exist relative to a test file.
///
/// skipstone cannot resolve local fork paths (`../../forks/`) through symlinks —
/// `runGradleTests()` calls `XCTFail` internally on Gradle failure, bypassing catch blocks.
/// Use `skip android test` for Android verification instead.
///
/// - Parameter filePath: Pass `#filePath` from the calling test file.
/// - Returns: `true` if the repo root contains a `forks/` directory.
public func hasLocalForkPaths(relativeTo filePath: String) -> Bool {
    let repoRoot = URL(fileURLWithPath: filePath)
        .deletingLastPathComponent() // -> Tests/<Target>/
        .deletingLastPathComponent() // -> Tests/
        .deletingLastPathComponent() // -> example root
        .deletingLastPathComponent() // -> examples/
        .deletingLastPathComponent() // -> repo root
    return FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("forks").path)
}
