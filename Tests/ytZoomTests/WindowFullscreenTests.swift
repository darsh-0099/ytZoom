import AppKit
import WebKit
import XCTest
@testable import ytZoom

private final class StopTrackingWebView: WKWebView {
    var stopCount = 0
    override func stopLoading() { stopCount += 1; super.stopLoading() }
}

final class WindowFullscreenTests: XCTestCase {
    @MainActor
    func testFullscreenStateTracksOnlyTheAppWindow() {
        _ = NSApplication.shared
        let owner = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let player = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let control = WindowFullscreen()
        control.attach(to: owner)
        XCTAssertTrue(owner.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(control.active)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: player)
        XCTAssertFalse(control.active)
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: owner)
        XCTAssertTrue(control.active)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: player)
        XCTAssertTrue(control.active)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: owner)
        XCTAssertFalse(control.active)
    }

    @MainActor
    func testClosingThePlayerFullscreenWindowDoesNotStopThePage() {
        _ = NSApplication.shared
        let owner = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let player = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let browser = BrowserModel()
        let view = StopTrackingWebView(frame: .zero, configuration: WKWebViewConfiguration())
        browser.webView = view
        browser.lifecycle.attach(to: owner)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: player)
        XCTAssertEqual(view.stopCount, 0)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: owner)
        XCTAssertEqual(view.stopCount, 1)
    }
}
