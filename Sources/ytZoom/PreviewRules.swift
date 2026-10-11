import WebKit

// One compiled rule, cached by WebKit and shared across unload/resume cycles.
final class PreviewRules {
    static let shared = PreviewRules()
    private var rule: WKContentRuleList?
    private var loading = false
    private var callbacks: [(WKContentRuleList?) -> Void] = []
    static let json = #"[{"trigger":{"url-filter":"^https?://i\\.ytimg\\.com/an_webp/","resource-type":["image"],"if-domain":["*youtube.com"]},"action":{"type":"block"}}]"#

    func load(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let rule = rule { completion(rule); return }
        callbacks.append(completion)
        guard !loading else { return }
        loading = true
        let store = WKContentRuleListStore.default()!
        store.lookUpContentRuleList(forIdentifier: "ytzoom-preview-images-v1") { [weak self] rule, _ in
            if let rule = rule { self?.finish(rule); return }
            store.compileContentRuleList(forIdentifier: "ytzoom-preview-images-v1", encodedContentRuleList: Self.json) {
                [weak self] rule, _ in self?.finish(rule)
            }
        }
    }

    private func finish(_ rule: WKContentRuleList?) {
        self.rule = rule
        loading = false
        let pending = callbacks
        callbacks.removeAll()
        pending.forEach { $0(rule) }
    }
}
