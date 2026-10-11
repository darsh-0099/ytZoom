import AppKit
import WebKit

// Owned by the window model, so foreground notifications survive a web-view unload.
final class BackgroundLifecycle {
    private weak var browser: BrowserModel?
    private weak var window: NSWindow?
    private var notifications: [NSObjectProtocol] = []
    private var idleWork: DispatchWorkItem?
    private var epoch = 0
    private var mediaPlaying = false
    private var suspensionRequested = false
    private var pauseWhenHidden = false
    private var idleMinutes = 5
    private var closed = false

    init(browser: BrowserModel) {
        self.browser = browser
        let names: [Notification.Name] = [NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification]
        notifications = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self else { return }
                if let notifiedWindow = note.object as? NSWindow, notifiedWindow !== self.window { return }
                if name == NSWindow.willCloseNotification {
                    self.closed = true
                    self.cancelIdle()
                    self.browser?.cancelUnload()
                    self.browser?.webView?.pauseAllMediaPlayback(completionHandler: nil)
                    self.browser?.webView?.stopLoading()
                    return
                }
                self.refresh()
            }
        }
    }

    deinit {
        idleWork?.cancel()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var hidden: Bool { window != nil && (NSApp.isHidden || window?.isMiniaturized == true) }

    func attach(to window: NSWindow?) {
        guard let window = window else { return }
        self.window = window
        closed = false
        refresh()
    }

    func configure(pauseWhenHidden: Bool, idleMinutes: Int) {
        let minutes = [0, 5, 15, 30].contains(idleMinutes) ? idleMinutes : 5
        if self.idleMinutes != minutes { cancelIdle() }
        self.pauseWhenHidden = pauseWhenHidden
        self.idleMinutes = minutes
        refresh()
    }

    func playbackChanged(playing: Bool) {
        mediaPlaying = playing
        if playing { cancelIdle() } else { refresh() }
    }

    func detached() {
        cancelIdle()
        suspensionRequested = false
        mediaPlaying = false
    }

    func refresh() {
        guard !closed, let browser = browser else { return }
        if !hidden {
            cancelIdle()
            if browser.automaticallyUnloaded { browser.resume() }
        }
        guard let view = browser.webView else { return }
        let suspend = hidden && pauseWhenHidden
        if suspend != suspensionRequested {
            suspensionRequested = suspend
            if suspend {
                // Pause first: unsuspending on return should not restart audio automatically.
                view.pauseAllMediaPlayback { [weak self, weak view] in
                    guard let self = self, let view = view, self.suspensionRequested,
                          self.browser?.webView === view else { return }
                    view.setAllMediaPlaybackSuspended(true, completionHandler: nil)
                    self.mediaPlaying = false
                    self.scheduleIdle()
                }
            } else {
                view.setAllMediaPlaybackSuspended(false, completionHandler: nil)
            }
        }
        scheduleIdle()
    }

    private func cancelIdle() {
        epoch += 1
        idleWork?.cancel()
        idleWork = nil
    }

    private func scheduleIdle() {
        guard let browser = browser, let view = browser.webView, !closed, hidden,
              idleMinutes > 0, !view.isLoading, !mediaPlaying,
              IdlePolicy.isYouTube(view.url), !browser.unloaded else {
            cancelIdle()
            return
        }
        guard idleWork == nil else { return }
        let scheduledEpoch = epoch
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self = self, let view = view, self.epoch == scheduledEpoch,
                  self.hidden, self.browser?.webView === view else { return }
            self.idleWork = nil
            view.requestMediaPlaybackState { [weak self, weak view] state in
                guard let self = self, let view = view, state != .playing,
                      self.epoch == scheduledEpoch, self.hidden, !view.isLoading,
                      self.browser?.webView === view else { return }
                self.browser?.unload(automatically: true) { [weak self] in
                    self?.epoch == scheduledEpoch && self?.hidden == true
                }
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(idleMinutes * 60), execute: work)
    }
}
