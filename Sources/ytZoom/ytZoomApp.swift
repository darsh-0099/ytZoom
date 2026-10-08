import AppKit
import Combine
import SwiftUI
import WebKit

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
            return "ytd-moving-thumbnail-renderer, ytd-video-preview { display: none !important; }"
        case .eco:
            return """
            ytd-moving-thumbnail-renderer, ytd-video-preview { display: none !important; }
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

final class BrowserModel: ObservableObject {
    static let homeURL = URL(string: "https://www.youtube.com/")!
    @Published private(set) var address = homeURL.absoluteString
    @Published private(set) var loading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var canBack = false
    @Published private(set) var canForward = false
    @Published var errorMessage: String?

    @Published private(set) var unloaded = false
    private(set) var resumeURL = homeURL
    private var updatePending = false
    weak var webView: WKWebView?

    func update(from view: WKWebView) {
        guard webView === view, !updatePending else { return }
        updatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updatePending = false
            guard let view = self.webView, !self.unloaded else { return }
            let address = view.url?.absoluteString ?? Self.homeURL.absoluteString
            if self.address != address { self.address = address }
            if self.loading != view.isLoading { self.loading = view.isLoading }
            // Progress only needs percent precision; avoid redraws for tiny changes.
            let progress = (view.estimatedProgress * 100).rounded() / 100
            if self.progress != progress { self.progress = progress }
            if self.canBack != view.canGoBack { self.canBack = view.canGoBack }
            if self.canForward != view.canGoForward { self.canForward = view.canGoForward }
        }
    }

    func toggleUnload() {
        if unloaded {
            unloaded = false
        } else {
            resumeURL = webView?.url ?? Self.homeURL
            webView?.pauseAllMediaPlayback(completionHandler: nil)
            webView?.stopLoading()
            unloaded = true
            loading = false
            canBack = false
            canForward = false
            errorMessage = nil
        }
    }

    func controlPlayback(_ command: String) {
        guard ["toggle", "backward", "forward"].contains(command) else { return }
        webView?.evaluateJavaScript("window.__ytzoom?.command('\(command)')", completionHandler: nil)
    }

    private func load(_ url: URL) {
        errorMessage = nil
        if unloaded {
            resumeURL = url
            unloaded = false
        } else {
            webView?.load(URLRequest(url: url))
        }
    }

    func goHome() { load(Self.homeURL) }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { if unloaded { unloaded = false } else { webView?.reload() } }
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

            if browser.loading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            } else {
                Color.clear.frame(height: 2)
            }

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

            playbackToolbar

            Group {
                if browser.unloaded {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf").font(.largeTitle)
                        Text("Page unloaded")
                        Text("Resume reloads the last address. Navigation history and playback position are reset.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Resume page", action: browser.toggleUnload)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    YouTubeWebView(browser: browser, mode: mode,
                                   playbackRate: playbackRate, pauseWhenHidden: pauseWhenHidden,
                                   darkMode: darkMode)
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
        .onReceive(browser.$address) { newAddress in
            if !addressFocused { addressInput = newAddress }
        }
    }

    private var playbackToolbar: some View {
        HStack(spacing: 12) {
            Button { browser.controlPlayback("backward") } label: {
                Image(systemName: "gobackward.10")
            }.help("Seek back 10 seconds (Command-Left)")
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(browser.unloaded)
            Button { browser.controlPlayback("toggle") } label: {
                Image(systemName: "playpause")
            }.help("Play or pause (Command-P)")
                .keyboardShortcut("p", modifiers: .command)
                .disabled(browser.unloaded)
            Button { browser.controlPlayback("forward") } label: {
                Image(systemName: "goforward.10")
            }.help("Seek forward 10 seconds (Command-Right)")
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(browser.unloaded)
            Picker("Speed", selection: $playbackRate) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    Text("\(rate.formatted())×").tag(rate)
                }
            }.frame(width: 130)
                .disabled(browser.unloaded)
            Toggle("Pause when hidden", isOn: $pauseWhenHidden)
                .help("Pause media when ytZoom is hidden or minimized. Resume manually.")
            Spacer()
            Button(browser.unloaded ? "Resume page" : "Unload page", action: browser.toggleUnload)
                .help("Unload releases the page and clears navigation history. Resume reloads the last URL.")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)

    }
}

struct YouTubeWebView: NSViewRepresentable {
    @ObservedObject var browser: BrowserModel
    let mode: PerformanceMode
    let playbackRate: Double
    let pauseWhenHidden: Bool
    let darkMode: Bool

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
        context.coordinator.installScripts(in: configuration.userContentController)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.watch(view)
        browser.webView = view
        view.load(URLRequest(url: browser.resumeURL))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.mode != mode || coordinator.playbackRate != playbackRate ||
            coordinator.pauseWhenHidden != pauseWhenHidden || coordinator.darkMode != darkMode {
            coordinator.mode = mode
            coordinator.playbackRate = playbackRate
            coordinator.pauseWhenHidden = pauseWhenHidden
            coordinator.darkMode = darkMode
            view.appearance = NSAppearance(named: darkMode ? .darkAqua : .aqua)
            coordinator.installScripts(in: view.configuration.userContentController)
            coordinator.applySettings(to: view)
            coordinator.pauseIfHidden(view)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        coordinator.observations.removeAll()
        coordinator.notifications.forEach { NotificationCenter.default.removeObserver($0) }
        coordinator.notifications.removeAll()
        view.configuration.userContentController.removeAllUserScripts()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        if coordinator.browser.webView === view { coordinator.browser.webView = nil }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browser: BrowserModel
        var mode: PerformanceMode = .balanced
        var playbackRate = 1.0
        var pauseWhenHidden = false
        var darkMode = false
        var observations: [NSKeyValueObservation] = []
        var notifications: [NSObjectProtocol] = []

        init(browser: BrowserModel) {
            self.browser = browser
        }

        func watch(_ view: WKWebView) {
            for name in [NSApplication.didHideNotification, NSWindow.didMiniaturizeNotification] {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil,
                                                                  queue: .main) { [weak self, weak view] note in
                    guard let self = self, let view = view else { return }
                    if name == NSWindow.didMiniaturizeNotification,
                       (note.object as? NSWindow) !== view.window { return }
                    self.pauseIfHidden(view)
                }
                notifications.append(token)
            }
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

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            browser.errorMessage = nil
            browser.update(from: view)
            applySettings(to: view)
            pauseIfHidden(view)
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            show(error)
        }

        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            show(error)
        }

        private func show(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.browser.webView != nil, !self.browser.unloaded else { return }
                self.browser.errorMessage = error.localizedDescription
            }
        }

        func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
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

        func pauseIfHidden(_ view: WKWebView) {
            guard pauseWhenHidden, NSApp.isHidden || view.window?.isMiniaturized == true else { return }
            view.pauseAllMediaPlayback(completionHandler: nil)
        }

        private var settingsScript: String {
            let settings: [String: Any] = ["css": mode.css, "rate": playbackRate,
                                           "pauseWhenHidden": pauseWhenHidden,
                                           "suppressPreviews": mode != .compatibility, "darkMode": darkMode]
            guard let data = try? JSONSerialization.data(withJSONObject: settings),
                  let json = String(data: data, encoding: .utf8) else { return "" }
            return "window.__ytzoom?.configure(\(json));"
        }

        func installScripts(in controller: WKUserContentController) {
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(source: PlaybackScript.source + "\n" + settingsScript,
                                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

        func applySettings(to view: WKWebView) {
            view.evaluateJavaScript(settingsScript, completionHandler: nil)
        }
    }
}
