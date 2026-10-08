import AppKit
import Combine
import SwiftUI
import WebKit

@main
struct ytZoomApp: App {
    var body: some Scene {
        WindowGroup("ytZoom") {
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
        case .balanced: return "Hide animated thumbnail previews."
        case .eco: return "Reduce previews and selected interface motion."
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

    weak var webView: WKWebView?

    func update(from view: WKWebView) {
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self = self, let view = view else { return }
            self.address = view.url?.absoluteString ?? Self.homeURL.absoluteString
            self.loading = view.isLoading
            self.progress = view.estimatedProgress
            self.canBack = view.canGoBack
            self.canForward = view.canGoForward
        }
    }

    func goHome() { webView?.load(URLRequest(url: Self.homeURL)) }
    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func openInBrowser() { NSWorkspace.shared.open(webView?.url ?? Self.homeURL) }

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
        webView?.load(URLRequest(url: url))
    }
}

struct BrowserWindow: View {
    @StateObject private var browser = BrowserModel()
    @AppStorage("ytzoom.mode") private var modeSetting = PerformanceMode.balanced.rawValue
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

            YouTubeWebView(browser: browser, mode: mode)
                .frame(minWidth: 600, minHeight: 380)

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
        .onReceive(browser.$address) { newAddress in
            if !addressFocused { addressInput = newAddress }
        }
    }
}

struct YouTubeWebView: NSViewRepresentable {
    @ObservedObject var browser: BrowserModel
    let mode: PerformanceMode

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.mode = mode
        context.coordinator.watch(view)
        browser.webView = view
        view.load(URLRequest(url: BrowserModel.homeURL))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            context.coordinator.applyStyle(to: view)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.observations.removeAll()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        coordinator.browser.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let browser: BrowserModel
        var mode: PerformanceMode = .balanced
        var observations: [NSKeyValueObservation] = []

        init(browser: BrowserModel) {
            self.browser = browser
        }

        func watch(_ view: WKWebView) {
            observations = [
                view.observe(\.url, options: [.new]) { [weak self, weak view] _, _ in
                    self?.refresh(view)
                },
                view.observe(\.title, options: [.new]) { [weak self, weak view] _, _ in
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
            applyStyle(to: view)
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
                self?.browser.errorMessage = error.localizedDescription
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

        func applyStyle(to view: WKWebView) {
            guard let data = try? JSONSerialization.data(withJSONObject: [mode.css]),
                  let cssJSON = String(data: data, encoding: .utf8) else { return }
            let script = """
            (() => {
              const css = \(cssJSON)[0];
              let style = document.getElementById('ytzoom-style');
              if (!css) { if (style) style.remove(); return; }
              if (!style) {
                style = document.createElement('style');
                style.id = 'ytzoom-style';
                (document.head || document.documentElement).appendChild(style);
              }
              style.textContent = css;
            })();
            """
            view.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
