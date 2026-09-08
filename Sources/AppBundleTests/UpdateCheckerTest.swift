@testable import AppBundle
import XCTest

final class UpdateCheckerTest: XCTestCase {
    func testSemanticVersionComparison() {
        assertTrue(UpdateChecker.isVersion("v1.4.0", newerThan: "1.3.9"))
        assertTrue(UpdateChecker.isVersion("2.0.0", newerThan: "v1.99.99"))
        assertFalse(UpdateChecker.isVersion("v1.4.0", newerThan: "1.4.0"))
        assertFalse(UpdateChecker.isVersion("v1.3.9", newerThan: "1.4.0"))
    }

    func testDecodesGitHubReleaseMetadata() throws {
        let release = try UpdateChecker.decodeRelease(Data("""
            {
              "tag_name": "v1.2.3",
              "name": "TileSail 1.2.3",
              "html_url": "https://github.com/cassel/TileSail/releases/tag/v1.2.3",
              "published_at": "2026-09-04T12:00:00Z"
            }
            """.utf8))

        assertEquals(release.version, "v1.2.3")
        assertEquals(release.title, "TileSail 1.2.3")
        assertEquals(release.pageUrl.absoluteString, "https://github.com/cassel/TileSail/releases/tag/v1.2.3")
        XCTAssertNotNil(release.publishedAt)
    }
}
