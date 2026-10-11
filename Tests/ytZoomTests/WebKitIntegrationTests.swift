import XCTest
import WebKit
import AppKit
@testable import ytZoom

private final class PageDelegate: NSObject, WKNavigationDelegate {
    var finished: ((WKWebView) -> Void)?
    var failed: ((Error) -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished?(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed?(error) }
}

final class WebKitIntegrationTests: XCTestCase {
    @MainActor
    func testPlaybackScriptExecutesInNativeWebKitWithIdempotentSettings() {
        _ = NSApplication.shared
        let done = expectation(description: "Native script fixture")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        WindowFullscreen.enablePlayer(in: configuration)
        configuration.userContentController.addUserScript(WKUserScript(
            source: PlaybackScript.source + "\nwindow.__ytzoom?.configure({css:'body{color:red}',rate:1.5,darkMode:true});",
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = PageDelegate()
        view.navigationDelegate = delegate
        delegate.failed = { error in XCTFail(error.localizedDescription); done.fulfill() }
        delegate.finished = { webView in
            webView.evaluateJavaScript("""
            (() => {
              const style = document.getElementById('ytzoom-style');
              for(let i=0;i<1000;i++) window.__ytzoom.configure({css:'body{color:red}',rate:1.5,darkMode:true});
              return {dark:document.documentElement.hasAttribute('dark'),
                      fullscreenEnabled:document.fullscreenEnabled,
                      stableStyle:style===document.getElementById('ytzoom-style'),
                      speed:document.querySelector('video').playbackRate,
                      playing:window.__ytzoom.snapshot().playing};
            })();
            """) { result, error in
                XCTAssertNil(error)
                let data = result as? [String: Any]
                XCTAssertEqual(data?["dark"] as? Bool, true)
                XCTAssertEqual(data?["fullscreenEnabled"] as? Bool, true)
                XCTAssertEqual(data?["stableStyle"] as? Bool, true)
                XCTAssertEqual(data?["speed"] as? Double, 1.5)
                XCTAssertEqual(data?["playing"] as? Bool, false)
                done.fulfill()
            }
        }
        view.loadHTMLString("<html><body><div id='movie_player'><video></video></div></body></html>",
                            baseURL: URL(string: "https://www.youtube.com/watch?v=fixture"))
        wait(for: [done], timeout: 30)
        view.stopLoading()
        view.navigationDelegate = nil
        configuration.userContentController.removeAllUserScripts()
    }
}
