@testable import AppBundle
import XCTest

final class WindowManagerConflictDetectorTest: XCTestCase {
    func testDetectsKnownManagersAndIgnoresCurrentProcess() {
        let candidates = [
            RunningWindowManagerCandidate(
                processIdentifier: 10,
                name: "TileSail",
                bundleIdentifier: "bobko.aerospace.debug",
                executableName: "TileSail",
            ),
            RunningWindowManagerCandidate(
                processIdentifier: 11,
                name: "OmniWM",
                bundleIdentifier: "example.omniwm",
                executableName: "OmniWM",
            ),
            RunningWindowManagerCandidate(
                processIdentifier: 12,
                name: "Safari",
                bundleIdentifier: "com.apple.Safari",
                executableName: "Safari",
            ),
        ]

        let conflicts = WindowManagerConflictDetector.conflicts(
            among: candidates,
            currentProcessIdentifier: 10,
        )

        assertEquals(conflicts.map(\.processIdentifier), [11])
    }

    func testDetectsBackgroundManagerByExecutableName() {
        let conflicts = WindowManagerConflictDetector.conflicts(
            among: [RunningWindowManagerCandidate(
                processIdentifier: 22,
                name: "Background Agent",
                bundleIdentifier: nil,
                executableName: "yabai",
            )],
            currentProcessIdentifier: 1,
        )

        assertEquals(conflicts.first?.name, "Background Agent")
    }
}
