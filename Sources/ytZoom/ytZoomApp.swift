import AppKit
import Combine
import SwiftUI
import WebKit
import os

@main
struct ytZoomApp: App {
    var body: some Scene {
        Window("ytZoom", id: "main") {
            BrowserWindow()
        }
        .defaultSize(width: 1180, height: 760)
    }
}

enum PerformanceMode: String, CaseIterable, Identifiable {
    case balanced, eco, compatibility
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var explanation: String {
        switch self {
        case .balanced: return "Hide and pause animated thumbnail previews."
        case .eco: return "Pause previews and reduce selected interface motion."
        case .compatibility: return "Use YouTube's original page styling."
        }
    }

    var css: String {
        switch self {
        case .balanced:
            return Self.previewCSS + Self.offscreenCSS
        case .eco:
            return """
            \(Self.previewCSS)
            \(Self.offscreenCSS)
            ytd-rich-grid-media, ytd-compact-video-renderer, ytd-guide-entry-renderer {
                animation-duration: 0s !important;
                transition-duration: 0s !important;
            }
            """
        case .compatibility:
            return ""
        }
    }
}

private extension PerformanceMode {
    static let previewCSS = "ytd-moving-thumbnail-renderer, ytd-video-preview { display: none !important; }"
    static let offscreenCSS = """
    @supports (content-visibility: auto) {
      ytd-rich-item-renderer { content-visibility: auto; contain-intrinsic-size: auto 300px; }
      ytd-comment-thread-renderer { content-visibility: auto; contain-intrinsic-size: auto 150px; }
    }
    """
}

struct BrowserState: Equatable {
    var address = BrowserModel.homeURL.absoluteString
    var loading = false
    var canBack = false
    var canForward = false
}

final class LoadProgress: ObservableObject {
    @Published private(set) var value = 0.0
    func update(_ value: Double) {
        let rounded = (value * 100).rounded() / 100
        if self.value != rounded { self.value = rounded }
    }
}

struct LoadingIndicator: View {
    @ObservedObject var progress: LoadProgress
    let loading: Bool
    var body: some View {
        Group {
            if loading { ProgressView(value: progress.value).progressViewStyle(.linear) }
            else { Color.clear }
        }.frame(height: 2)
    }
}

final class BrowserModel: ObservableObject {
    static let homeURL = URL(string: "https://www.youtube.com/")!
    @Published private(set) var state = BrowserState()
    @Published var errorMessage: String?
    @Published private(set) var unloaded = false
    let loadProgress = LoadProgress()
    var address: String { state.address }
    var loading: Bool { state.loading }
    var canBack: Bool { state.canBack }
    var canForward: Bool { state.canForward }
    private(set) var resumeURL = homeURL
    private(set) var resumePoint: ResumePoint?
    private(set) var automaticallyUnloaded = false
    private var updatePending = false
    private var homeToken: UUID?
    private var unloadToken: UUID?
    private var unloadTimeout: DispatchWorkItem?
    weak var webView: WKWebView?
    lazy var lifecycle = BackgroundLifecycle(browser: self)

    func update(from view: WKWebView) {
        guard webView === view, !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePending = false
            guard let view = self.webView, !self.unloaded else { return }
            let next = BrowserState(address: view.url?.absoluteString ?? Self.homeURL.absoluteString,
                                    loading: view.isLoading, canBack: view.canGoBack, canForward: view.canGoForward)
            if self.state != next { self.state = next }
            self.loadProgress.update(view.estimatedProgress)
        }
    }

    func toggleUnload() { if unloaded { resume() } else { unload(automatically: false) } }

    func resume() {
        PerformanceTrace.resumed()
        automaticallyUnloaded = false
        unloaded = false
    }

    func clearResumePoint() { resumePoint = nil }

    func cancelUnload() {
        unloadToken = nil
        unloadTimeout?.cancel()
        unloadTimeout = nil
    }

    func unload(automatically: Bool, canContinue: @escaping () -> Bool = { true }) {
        homeToken = nil
        guard let view = webView, !unloaded, unloadToken == nil else { return }
        let url = view.url ?? Self.homeURL
        let token = UUID()
        unloadToken = token
        let timeout = DispatchWorkItem { [weak self, weak view] in
            guard let self = self, let view = view, self.unloadToken == token else { return }
            self.cancelUnload()
            if !automatically && self.webView === view && view.url == url && canContinue() {
                self.finishUnload(view, url: url, snapshot: nil, automatically: false)
            }
        }
        unloadTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: timeout)
        view.evaluateJavaScript("window.__ytzoom?.snapshot()") { [weak self, weak view] result, _ in
            guard let self = self, let view = view, self.unloadToken == token else { return }
            self.cancelUnload()
            guard self.webView === view, view.url == url, canContinue() else { return }
            let snapshot = result as? [String: Any]
            if automatically && !IdlePolicy.canUnload(hidden: self.lifecycle.hidden, loading: view.isLoading,
                                                       mediaPlaying: false, url: url, snapshot: snapshot) { return }
            self.finishUnload(view, url: url, snapshot: snapshot, automatically: automatically)
        }
    }

    private func finishUnload(_ view: WKWebView, url: URL, snapshot: [String: Any]?, automatically: Bool) {
        resumePoint = snapshot.flatMap { ResumePoint.capture($0, at: url) }
        resumeURL = resumePoint?.url(from: url) ?? url
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        PerformanceTrace.unloaded()
        automaticallyUnloaded = automatically
        unloaded = true
        var next = state
        next.loading = false; next.canBack = false; next.canForward = false
        if state != next { state = next }
        errorMessage = nil
    }

    func controlPlayback(_ command: String) {
        guard ["toggle", "backward", "forward"].contains(command) else { return }
        webView?.evaluateJavaScript("window.__ytzoom?.command('\(command)')", completionHandler: nil)
    }

    private func load(_ url: URL) {
        homeToken = nil
        cancelUnload()
        errorMessage = nil
        if unloaded {
            resumePoint = nil
            automaticallyUnloaded = false
            resumeURL = url
            unloaded = false
        } else {
            webView?.load(URLRequest(url: url))
        }
    }

    func goHome() {
        cancelUnload()
        guard let view = webView, !unloaded else { load(Self.homeURL); return }
        guard view.url != Self.homeURL else { return }
        let original = view.url
        let token = UUID()
        homeToken = token
        view.evaluateJavaScript("window.__ytzoom?.goHome()") { [weak self, weak view] result, _ in
            guard let self = self, let view = view, self.homeToken == token, self.webView === view else { return }
            let fallback = {
                guard self.homeToken == token, self.webView === view, view.url == original else { return }
                self.load(Self.homeURL)
            }
            if result as? Bool == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(750), execute: fallback)
            } else { fallback() }
        }
    }
    func goBack() { homeToken = nil; cancelUnload(); webView?.goBack() }
    func goForward() { homeToken = nil; cancelUnload(); webView?.goForward() }
    func reload() { homeToken = nil; cancelUnload(); if unloaded { resume() } else { webView?.reload() } }
    func openInBrowser() { NSWorkspace.shared.open(webView?.url ?? (unloaded ? resumeURL : Self.homeURL)) }

    func navigate(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let target: URL?
        if let candidate = URL(string: input),
           ["https", "http"].contains(candidate.scheme?.lowercased() ?? ""),
           candidate.host != nil {
            target = candidate
        } else if !input.contains(" "), input.contains("."),
                  let candidate = URL(string: "https://" + input),
                  candidate.host != nil {
            target = candidate
        } else {
            var query = URLComponents(string: "https://www.youtube.com/results")!
            query.queryItems = [URLQueryItem(name: "search_query", value: input)]
            target = query.url
        }
        guard let url = target else {
            errorMessage = "Could not open that address."
            return
        }
        load(url)
    }
}

struct BrowserWindow: View {
    @StateObject private var browser = BrowserModel()
    @AppStorage("ytzoom.mode") private var modeSetting = PerformanceMode.balanced.rawValue
    @AppStorage("ytzoom.pauseWhenHidden") private var pauseWhenHidden = false
    @AppStorage("ytzoom.playbackRate") private var playbackRate = 1.0
    @AppStorage("ytzoom.darkMode") private var darkMode = false
    @AppStorage("ytzoom.idleUnloadMinutes") private var idleMinutes = 5
    @AppStorage("ytzoom.focusViewing") private var focusViewing = false
    @State private var addressInput = BrowserModel.homeURL.absoluteString
    @FocusState private var addressFocused: Bool
    private var mode: PerformanceMode {
        PerformanceMode(rawValue: modeSetting) ?? .balanced
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: browser.goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!browser.canBack)
                .help("Back")
                .keyboardShortcut("[", modifiers: .command)

                Button(action: browser.goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!browser.canForward)
                .help("Forward")
                .keyboardShortcut("]", modifiers: .command)

                Button(action: browser.goHome) {
                    Image(systemName: "house")
                }.help("YouTube Home")

                Button(action: browser.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
                .keyboardShortcut("r", modifiers: .command)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("YouTube URL or search", text: $addressInput)
                        .textFieldStyle(.plain)
                        .focused($addressFocused)
                        .onSubmit {
                            browser.navigate(addressInput)
                            addressFocused = false
                        }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))

                Button {
                    addressInput = browser.address
                    addressFocused = true
                } label: {
                    Image(systemName: "link")
                }
                .help("Focus address bar")
                .keyboardShortcut("l", modifiers: .command)

                Picker("Performance", selection: $modeSetting) {
                    ForEach(PerformanceMode.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 135)
                .help(mode.explanation)

                playbackMenu

                Button { darkMode.toggle() } label: {
                    Image(systemName: darkMode ? "sun.max" : "moon")
                }
                .help(darkMode ? "Switch to light mode" : "Switch to dark mode")
                .accessibilityLabel(darkMode ? "Switch to light mode" : "Switch to dark mode")
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button(action: browser.openInBrowser) {
                    Image(systemName: "safari")
                }.help("Open in default browser")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            LoadingIndicator(progress: browser.loadProgress, loading: browser.loading)

            if let error = browser.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).lineLimit(2)
                    Spacer()
                    Button("Reload", action: browser.reload)
                    Button {
                        browser.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .font(.caption)
                .padding(8)
                .background(Color.orange.opacity(0.13))
            }

            Group {
                if browser.unloaded {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf").font(.largeTitle)
                        Text("Page unloaded")
                        Text("Resume restores the last address and saved video position. Navigation history is reset.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Resume page", action: browser.toggleUnload)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    YouTubeWebView(browser: browser, mode: mode,
                                   playbackRate: playbackRate, pauseWhenHidden: pauseWhenHidden,
                                   darkMode: darkMode, focusViewing: focusViewing)
                }
            }
            .frame(minWidth: 800, minHeight: 380)

            HStack {
                Text("\(mode.label) mode").fontWeight(.semibold)
                Text("· \(mode.explanation)").lineLimit(1)
                Spacer()
                Text("WebKit processes are managed by macOS").lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .preferredColorScheme(darkMode ? .dark : .light)
        .onAppear { configureLifecycle() }
        .onChange(of: pauseWhenHidden) { _ in configureLifecycle() }
        .onChange(of: idleMinutes) { _ in configureLifecycle() }
        .onReceive(browser.$state.map(\.address).removeDuplicates()) { newAddress in
            if !addressFocused { addressInput = newAddress }
        }
    }

    private func configureLifecycle() {
        browser.lifecycle.configure(pauseWhenHidden: pauseWhenHidden, idleMinutes: idleMinutes)
    }

    private var playbackMenu: some View {
        Menu {
            Button("Seek back 10 seconds") { browser.controlPlayback("backward") }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(browser.unloaded)
            Button("Play or pause") { browser.controlPlayback("toggle") }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(browser.unloaded)
            Button("Seek forward 10 seconds") { browser.controlPlayback("forward") }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(browser.unloaded)
            Picker("Playback speed", selection: $playbackRate) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    Text("\(rate.formatted())×").tag(rate)
                }
            }
            Toggle("Pause when hidden", isOn: $pauseWhenHidden)
            Toggle("Focus viewing", isOn: $focusViewing)
            Picker("Unload hidden idle page after", selection: $idleMinutes) {
                Text("Never").tag(0)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
            }
            Divider()
            Button(browser.unloaded ? "Resume page" : "Unload page", action: browser.toggleUnload)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Playback options")
    }

}

struct YouTubeWebView: NSViewRepresentable {
    let browser: BrowserModel
    let mode: PerformanceMode
    let playbackRate: Double
    let pauseWhenHidden: Bool
    let darkMode: Bool
    let focusViewing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        context.coordinator.mode = mode
        context.coordinator.playbackRate = playbackRate
        context.coordinator.pauseWhenHidden = pauseWhenHidden
        context.coordinator.darkMode = darkMode
        context.coordinator.focusViewing = focusViewing
        configuration.userContentController.add(WeakScriptHandler(context.coordinator), name: "ytzoomLifecycle")
        context.coordinator.installScripts(in: configuration.userContentController)
        let view = BrowserWebView(frame: .zero, configuration: configuration)
        view.windowChanged = { [weak model = browser] window in model?.lifecycle.attach(to: window) }
        view.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.watch(view)
        browser.webView = view
        context.coordinator.applyPreviewRules(to: view)
        view.load(URLRequest(url: browser.resumeURL))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.mode != mode || coordinator.playbackRate != playbackRate ||
            coordinator.pauseWhenHidden != pauseWhenHidden || coordinator.darkMode != darkMode ||
            coordinator.focusViewing != focusViewing {
            coordinator.invalidateSettings()
            coordinator.mode = mode
            coordinator.playbackRate = playbackRate
            coordinator.pauseWhenHidden = pauseWhenHidden
            coordinator.darkMode = darkMode
            coordinator.focusViewing = focusViewing
            view.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
            coordinator.installScripts(in: view.configuration.userContentController)
            coordinator.applySettings(to: view)
            coordinator.applyPreviewRules(to: view)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        coordinator.endNavigationTrace()
        coordinator.observations.removeAll()
        (view as? BrowserWebView)?.windowChanged = nil
        if coordinator.browser.webView === view {
            coordinator.browser.cancelUnload()
            coordinator.browser.lifecycle.detached()
        }
        view.configuration.userContentController.removeScriptMessageHandler(forName: "ytzoomLifecycle")
        view.configuration.userContentController.removeAllContentRuleLists()
        view.configuration.userContentController.removeAllUserScripts()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        if coordinator.browser.webView === view { coordinator.browser.webView = nil }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let browser: BrowserModel
        var mode: PerformanceMode = .balanced
        var playbackRate = 1.0
        var pauseWhenHidden = false
        var darkMode = false
        var focusViewing = false
        private var navigationTrace: OSSignpostID?
        func endNavigationTrace() {
            if let id = navigationTrace { PerformanceTrace.endNavigation(id); navigationTrace = nil }
        }
        private var cachedSettingsScript: String?
        func invalidateSettings() { cachedSettingsScript = nil }
        private var previewRule: WKContentRuleList?
        private var previewRuleApplied = false
        private var pendingResumeInjection = false
        private static let bootstrap = WKUserScript(source: WatchPolicyScript.bootstrap,
                                                    injectionTime: .atDocumentStart, forMainFrameOnly: true)
        private static let integration = WKUserScript(source: PlaybackScript.source +
            "\nwindow.__ytzoom?.configure(window.__ytzoomSettings || {});\n" +
            WatchPolicyScript.bootstrap + "\n" + WatchPolicyScript.source,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        var observations: [NSKeyValueObservation] = []

        init(browser: BrowserModel) {
            self.browser = browser
        }

        func watch(_ view: WKWebView) {
            observations = [
                view.observe(\.url, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                },
                view.observe(\.isLoading, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                },
                view.observe(\.estimatedProgress, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                },
                view.observe(\.canGoBack, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                },
                view.observe(\.canGoForward, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                }
            ]
        }

        private func refresh(_ view: WKWebView?) {
            if let view = view { browser.update(from: view) }
        }

        func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            endNavigationTrace()
            navigationTrace = PerformanceTrace.beginNavigation()
        }

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            endNavigationTrace()
            browser.errorMessage = nil
            browser.update(from: view)
            if pendingResumeInjection {
                browser.clearResumePoint()
                installScripts(in: view.configuration.userContentController)
            }
            browser.lifecycle.refresh()
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            show(error)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            show(error)
        }

        private func show(_ error: Error) {
            endNavigationTrace()
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.browser.webView != nil, !self.browser.unloaded else { return }
                self.browser.errorMessage = error.localizedDescription
            }
        }

        func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
            endNavigationTrace()
            browser.errorMessage = "The web process stopped. Press Reload to retry."
        }

        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            guard ["http", "https", "about"].contains(scheme) else {
                decisionHandler(.cancel)
                return
            }
            if action.navigationType == .linkActivated,
               action.targetFrame?.isMainFrame != false,
               scheme != "about", !isYouTubeOrGoogle(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func isYouTubeOrGoogle(_ url: URL) -> Bool {
            let host = (url.host ?? "").lowercased()
            return ["youtube.com", "youtu.be", "youtube-nocookie.com",
                    "google.com", "googleusercontent.com"].contains {
                host == $0 || host.hasSuffix("." + $0)
            }
        }

        func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let view = browser.webView, message.webView === view,
                  message.frameInfo.isMainFrame, IdlePolicy.isYouTube(message.frameInfo.request.url),
                  let body = message.body as? [String: Any], let playing = body["playing"] as? Bool else { return }
            browser.lifecycle.playbackChanged(playing: playing)
        }

        func applyPreviewRules(to view: WKWebView) {
            let controller = view.configuration.userContentController
            if mode == .compatibility {
                if let rule = previewRule, previewRuleApplied { controller.remove(rule); previewRuleApplied = false }
                return
            }
            if let rule = previewRule {
                if !previewRuleApplied { controller.add(rule); previewRuleApplied = true }
            } else {
                PreviewRules.shared.load { [weak self, weak view] rule in
                    guard let self = self, let view = view, self.browser.webView === view,
                          let rule = rule else { return }
                    self.previewRule = rule
                    self.applyPreviewRules(to: view)
                }
            }
        }

        private var settingsScript: String {
            if let cached = cachedSettingsScript { return cached }
            let settings: [String: Any] = ["css": mode.css, "rate": playbackRate,
                                           "pauseWhenHidden": pauseWhenHidden,
                                           "suppressPreviews": mode != .compatibility, "darkMode": darkMode,
                                           "focusViewing": focusViewing]
            guard let data = try? JSONSerialization.data(withJSONObject: settings),
                  let json = String(data: data, encoding: .utf8) else { return "" }
            let script = "window.__ytzoomSettings = \(json);"
            cachedSettingsScript = script
            return script
        }

        func installScripts(in controller: WKUserContentController) {
            controller.removeAllUserScripts()
            var configuration = settingsScript
            pendingResumeInjection = browser.resumePoint != nil
            if let point = browser.resumePoint,
               let data = try? JSONSerialization.data(withJSONObject: point.settings),
               let json = String(data: data, encoding: .utf8) {
                configuration += "window.__ytzoomResume = \(json);"
            }
            controller.addUserScript(WKUserScript(source: configuration,
                                                  injectionTime: .atDocumentStart, forMainFrameOnly: true))
            controller.addUserScript(Self.bootstrap)
            controller.addUserScript(Self.integration)
        }

        func applySettings(to view: WKWebView) {
            view.evaluateJavaScript(settingsScript + "window.__ytzoom?.configure(window.__ytzoomSettings);",
                                    completionHandler: nil)
            browser.lifecycle.configure(pauseWhenHidden: pauseWhenHidden,
                                        idleMinutes: (UserDefaults.standard.object(forKey: "ytzoom.idleUnloadMinutes") as? Int) ?? 5)
        }

    }
}

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
