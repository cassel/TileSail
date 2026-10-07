@testable import AppBundle
import XCTest

final class StartupAgentTest: XCTestCase {
    func testExternalAgentRemovesDuplicateRegistrationRegardlessOfSetting() {
        for enabled in [true, false] {
            for debug in [true, false] {
                XCTAssertEqual(startupRegistrationAction(externalAgent: true, enabled: enabled, debug: debug), .unregister)
            }
        }
        XCTAssertEqual(startupRegistrationAction(externalAgent: false, enabled: true, debug: false), .register)
        XCTAssertEqual(startupRegistrationAction(externalAgent: false, enabled: true, debug: true), .debugIgnored)
    }

    func testFailedScanStillDisablesOwnService() {
        XCTAssertEqual(startupRegistrationAction(externalAgent: false, enabled: false, debug: false, scanSucceeded: false), .unregister)
        XCTAssertEqual(startupRegistrationAction(externalAgent: false, enabled: true, debug: false, scanSucceeded: false), .scanFailed)
    }

    func testRecognizedForms() {
        XCTAssertTrue(isManagedStartupAgent(["ProgramArguments": ["/Users/example/Applications/AeroSpaceSmooth.app/Contents/MacOS/AeroSpaceSmooth", "--config-path", "/custom/config"]]))
        XCTAssertTrue(isManagedStartupAgent(["ProgramArguments": ["/usr/bin/open", "-a", "/Applications/TileSail.app", "--args", "--config-path", "/custom/config"]]))
        XCTAssertTrue(isManagedStartupAgent(["Program": "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"]))
        XCTAssertFalse(isManagedStartupAgent(["ProgramArguments": ["/usr/bin/open", "-a", "/Applications/Other.app"]]))
    }
}
