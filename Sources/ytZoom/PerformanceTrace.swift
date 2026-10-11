import os

// Captured by Instruments on demand; no timers, page URLs, or browsing data are logged.
enum PerformanceTrace {
    private static let log = OSLog(subsystem: "app.ytzoom.macos", category: .pointsOfInterest)
    static func beginNavigation() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "Navigation", signpostID: id)
        return id
    }
    static func endNavigation(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "Navigation", signpostID: id)
    }
    static func unloaded() { os_signpost(.event, log: log, name: "Page unloaded") }
    static func resumed() { os_signpost(.event, log: log, name: "Page resumed") }
}
