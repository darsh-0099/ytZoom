import AppKit
import SwiftUI
import WebKit

final class WindowFullscreen: ObservableObject {
    @Published private(set) var active = false
    private weak var window: NSWindow?
    private var notifications: [NSObjectProtocol] = []

    init() {
        notifications = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self, let window = note.object as? NSWindow, window === self.window else { return }
                self.active = name == NSWindow.didEnterFullScreenNotification
            }
        }
    }

    deinit { notifications.forEach { NotificationCenter.default.removeObserver($0) } }

    func attach(to window: NSWindow) {
        self.window = window
        window.collectionBehavior.insert(.fullScreenPrimary)
        active = window.styleMask.contains(.fullScreen)
    }

    func toggle() { window?.toggleFullScreen(nil) }

    static func enablePlayer(in configuration: WKWebViewConfiguration) {
        configuration.preferences.isElementFullscreenEnabled = true
    }
}

struct FullscreenButton: View {
    @ObservedObject var fullscreen: WindowFullscreen
    var body: some View {
        Button(action: fullscreen.toggle) {
            Image(systemName: fullscreen.active ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
        }
        .help(fullscreen.active ? "Exit fullscreen" : "Enter fullscreen")
        .accessibilityLabel(fullscreen.active ? "Exit fullscreen" : "Enter fullscreen")
        .keyboardShortcut("f", modifiers: [.control, .command])
    }
}

// This anchor stays in the app window when WebKit moves its view into a separate
// fullscreen window. Lifecycle observers must keep tracking the original window.
struct BrowserWindowAnchor: NSViewRepresentable {
    let browser: BrowserModel
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.attached = { [weak browser] window in
            browser?.fullscreen.attach(to: window)
            browser?.lifecycle.attach(to: window)
        }
        return view
    }
    func updateNSView(_ view: AnchorView, context: Context) {}
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) { view.attached = nil }

    final class AnchorView: NSView {
        var attached: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = window else { return }
            // Publish window state after SwiftUI finishes attaching the view.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self = self, let window = window, self.window === window else { return }
                self.attached?(window)
            }
        }
    }
}
