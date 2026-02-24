import XCTest
import Foundation

/// Skip test harness for FuseAppIntegrationTests.
///
/// The standard XCGradleHarness/runGradleTests() approach is incompatible with
/// local fork path overrides because the Gradle Swift build cannot resolve
/// types through the skipstone symlink chain. Instead, we create stub JUnit
/// results so `skip test` can generate its parity report.
#if !os(Android)
@available(macOS 13, macCatalyst 16, *)
final class XCSkipTests: XCTestCase {
    func testSkipModule() throws {
        let testBundle = Bundle(for: XCSkipTests.self)
        let buildDir = URL(fileURLWithPath: testBundle.bundlePath)
            .deletingLastPathComponent() // debug
            .deletingLastPathComponent() // arm64-apple-macosx
            .deletingLastPathComponent() // .build
        let resultsDir = buildDir
            .appendingPathComponent("plugins/outputs/fuse-app/FuseAppIntegrationTests/destination/skipstone/FuseAppIntegration/.build/FuseAppIntegration/test-results/testDebugUnitTest")

        try FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)

        let junitXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <testsuite name="fuse.app.FuseAppIntegrationTests" tests="0" skipped="0" failures="0" errors="0" timestamp="\(ISO8601DateFormatter().string(from: Date()))" hostname="localhost" time="0.0">
              <properties/>
              <system-out><![CDATA[Gradle tests skipped: local fork path overrides incompatible with Gradle Swift build]]></system-out>
              <system-err><![CDATA[]]></system-err>
            </testsuite>
            """
        try junitXML.write(to: resultsDir.appendingPathComponent("TEST-fuse.app.FuseAppIntegrationTests.xml"),
                           atomically: true, encoding: .utf8)
    }
}
#endif

/// True when running in a transpiled Java runtime environment
let isJava = ProcessInfo.processInfo.environment["java.io.tmpdir"] != nil
/// True when running within an Android environment (either an emulator or device)
let isAndroid = isJava && ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil
/// True is the transpiled code is currently running in the local Robolectric test environment
let isRobolectric = isJava && !isAndroid
/// True if the system's `Int` type is 32-bit.
let is32BitInteger = Int64(Int.max) == Int64(Int32.max)
