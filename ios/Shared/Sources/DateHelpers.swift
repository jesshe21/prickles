import Foundation

enum DateHelpers {

    /// "just now", "5 minutes ago", "2 hours ago", "3 days ago"
    static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let diff = max(0, Int(now.timeIntervalSince(date)))
        if diff < 60 { return "just now" }
        if diff < 3600 {
            let m = diff / 60
            return "\(m) \(m == 1 ? "minute" : "minutes") ago"
        }
        if diff < 86400 {
            let h = diff / 3600
            return "\(h) \(h == 1 ? "hour" : "hours") ago"
        }
        let d = diff / 86400
        return "\(d) \(d == 1 ? "day" : "days") ago"
    }

    /// "45m", "2h", "2h 30m"
    static func shortDuration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "Apr 15, 5:02 PM"
    static func shortDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d, h:mm a")
        return df.string(from: date)
    }

    /// Returns "Apr 15, 5:02 PM · 1h 3m" or "Apr 15, 5:02 PM · 1h 3m and counting" for ongoing.
    static func historyMeta(from: Date, to: Date?, now: Date = Date()) -> String {
        let end = to ?? now
        let mins = max(1, Int(end.timeIntervalSince(from) / 60))
        let duration = shortDuration(minutes: mins)
        let start = shortDateTime(from)
        return to == nil ? "\(start) · \(duration) and counting" : "\(start) · \(duration)"
    }
}
