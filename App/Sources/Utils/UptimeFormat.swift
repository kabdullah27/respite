import Foundation

/// Format uptime di layer app biar bisa di-localize (core tetap UI-free).
enum UptimeFormat {
    static func string(from seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 {
            return String(
                format: NSLocalizedString("%d hari %d jam", comment: "Uptime dalam hari dan jam"),
                days, hours
            )
        }
        return String(format: NSLocalizedString("%d jam", comment: "Uptime dalam jam"), hours)
    }
}
