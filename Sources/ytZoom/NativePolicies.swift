import Foundation

struct ResumePoint: Equatable {
    let videoID: String
    let seconds: Double

    static func capture(_ snapshot: [String: Any], at url: URL) -> ResumePoint? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == "/watch",
              let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
              snapshot["videoID"] as? String == id,
              snapshot["live"] as? Bool == false,
              snapshot["ad"] as? Bool == false,
              let seconds = snapshot["time"] as? Double, seconds.isFinite, seconds >= 0 else { return nil }
        return ResumePoint(videoID: id, seconds: seconds)
    }

    func url(from original: URL) -> URL {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else { return original }
        var items = components.queryItems ?? []
        items.removeAll { ["t", "start", "time_continue"].contains($0.name) }
        items.append(URLQueryItem(name: "t", value: String(Int(min(seconds, 604800))) + "s"))
        components.queryItems = items
        return components.url ?? original
    }

    var settings: [String: Any] { ["videoID": videoID, "time": seconds, "paused": true] }
}

enum IdlePolicy {
    static func isYouTube(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased(), url?.scheme == "https" else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    static func canUnload(hidden: Bool, loading: Bool, mediaPlaying: Bool,
                          url: URL?, snapshot: [String: Any]?) -> Bool {
        guard hidden, !loading, !mediaPlaying, isYouTube(url),
              let snapshot = snapshot, snapshot["playing"] as? Bool == false,
              snapshot["hasDraft"] as? Bool == false,
              snapshot["url"] as? String == url?.absoluteString else { return false }
        return true
    }
}
