import XCTest
import AppKit
@testable import NudgeServer

final class NavServerTests: XCTestCase {

    func testOpenApplication() async throws {
        let appIdentifier = "com.apple.Safari"
        try await openApplication(bundleIdentifier: appIdentifier)
        let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == appIdentifier }
        XCTAssertNotNil(app, "Safari should be running after openApplication is called.")
    }
}
