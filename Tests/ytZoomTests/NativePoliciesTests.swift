import XCTest
import WebKit
@testable import ytZoom

final class NativePoliciesTests: XCTestCase {
    private let url = URL(string: "https://www.youtube.com/watch?v=example&list=playlist&t=2s")!
    private var snapshot: [String: Any] {
        ["url": url.absoluteString, "playing": false, "hasDraft": false, "videoID": "example", "time": 42.5, "live": false, "ad": false]
    }

    func testIdlePageCanUnloadButPlaybackLoadingForegroundAndUnknownPagesCannot() {
        XCTAssertTrue(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false, url: url, snapshot: snapshot))
        XCTAssertFalse(IdlePolicy.canUnload(hidden: false, loading: false, mediaPlaying: false, url: url, snapshot: snapshot))
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: true, mediaPlaying: false, url: url, snapshot: snapshot))
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: true, url: url, snapshot: snapshot))
        var draft = snapshot; draft["hasDraft"] = true
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false, url: url, snapshot: draft))
        var buffering = snapshot; buffering["playing"] = true
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false, url: url, snapshot: buffering))
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false, url: url, snapshot: nil))
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false,
                                            url: URL(string: "https://accounts.google.com/"), snapshot: snapshot))
        XCTAssertFalse(IdlePolicy.isYouTube(URL(string: "https://youtube.com.evil.test/")))
        XCTAssertFalse(IdlePolicy.isYouTube(URL(string: "https://notyoutube.com/")))
    }

    func testStaleSnapshotsCannotUnloadANewNavigation() {
        var stale = snapshot; stale["url"] = "https://www.youtube.com/watch?v=previous"
        XCTAssertFalse(IdlePolicy.canUnload(hidden: true, loading: false, mediaPlaying: false, url: url, snapshot: stale))
    }

    func testResumePreservesPlaylistAndReplacesTimestampWithoutDuplicates() throws {
        let point = try XCTUnwrap(ResumePoint.capture(snapshot, at: url))
        let components = try XCTUnwrap(URLComponents(url: point.url(from: url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "list" })?.value, "playlist")
        XCTAssertEqual(components.queryItems?.filter { $0.name == "t" }.count, 1)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "t" })?.value, "42s")
        XCTAssertEqual(point.settings["paused"] as? Bool, true)
    }

    func testAdsLiveStreamsWrongVideoIDsAndInvalidPositionsDoNotProduceResumePoints() {
        let changes: [(String, Any)] = [("ad", true), ("live", true), ("videoID", "previous"),
                                      ("time", Double.nan), ("time", Double.infinity), ("time", -1.0)]
        for change in changes {
            var invalid = snapshot; invalid[change.0] = change.1
            XCTAssertNil(ResumePoint.capture(invalid, at: url))
        }
    }

    func testPreviewRuleTargetsOnlyAnimatedImagePath() throws {
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(PreviewRules.json.utf8)) as? [[String: Any]])
        let trigger = try XCTUnwrap(entries.first?["trigger"] as? [String: Any])
        let filter = try XCTUnwrap(trigger["url-filter"] as? String)
        let regex = try NSRegularExpression(pattern: filter)
        func matches(_ url: String) -> Bool { regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        XCTAssertTrue(matches("https://i.ytimg.com/an_webp/video/preview.webp"))
        XCTAssertFalse(matches("https://i.ytimg.com/vi/video/hqdefault.jpg"))
        XCTAssertFalse(matches("https://rr1.googlevideo.com/videoplayback?id=video"))
        XCTAssertFalse(matches("https://www.youtube.com/youtubei/v1/player"))
        XCTAssertEqual(trigger["resource-type"] as? [String], ["image"])
    }

    @MainActor
    func testPreviewRuleCompilesInWebKit() {
        let done = expectation(description: "Compiled native preview rule")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ytzoom-preview-rule-test",
                                                                encodedContentRuleList: PreviewRules.json) { rule, error in
            XCTAssertNil(error)
            XCTAssertNotNil(rule)
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }
}
