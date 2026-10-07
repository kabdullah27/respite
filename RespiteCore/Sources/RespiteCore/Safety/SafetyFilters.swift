import Foundation

// MARK: - Protected List (TRD §4.20 p1)

/// Daftar hard-coded yang TIDAK PERNAH bisa disentuh operasi Respite —
/// bukan config, nggak bisa dioverride user atau whitelist. Dicek di titik
/// paling awal setiap operasi, bukan cuma di UI.
public enum ProtectedList {
    /// Proses sistem kritis — nggak pernah ditawarin buat di-kill/restart.
    public static let criticalProcesses: Set<String> = [
        "kernel_task", "WindowServer", "launchd", "loginwindow",
        "coreservicesd", "cfprefsd",
    ]

    /// Path home-relative yang nggak pernah masuk auto-scan.
    static let protectedRelativePrefixes: [String] = [
        "Documents",
        "Desktop",
        "Library/Keychains",
        "Library/Mail",
        "Library/Messages",
        "Pictures/Photos Library.photoslibrary",
    ]

    /// `homeDirectory` parameter buat inject fixture di unit test.
    public static func isProtected(
        _ url: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = url.standardizedFileURL.path
        for rel in protectedRelativePrefixes {
            let protectedPath = homeDirectory
                .appendingPathComponent(rel)
                .standardizedFileURL.path
            if path == protectedPath || path.hasPrefix(protectedPath + "/") {
                return true
            }
        }
        return false
    }
}

// MARK: - User Whitelist (TRD §4.20 p7)

/// Layer exclude milik user — DI ATAS Protected List (filter hasil scan),
/// tapi nggak pernah bisa override Protected List (yang reject di level operasi).
/// Match-nya prefix path, pattern glob menyusul kalau kebutuhan muncul.
public struct UserWhitelist: Sendable, Equatable {
    public static let defaultsKey = "app.respite.userWhitelist"

    public private(set) var patterns: [String]

    public init(patterns: [String] = []) {
        self.patterns = patterns
    }

    public static func load(from defaults: UserDefaults = .standard) -> UserWhitelist {
        UserWhitelist(patterns: defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(patterns, forKey: Self.defaultsKey)
    }

    public mutating func add(_ pattern: String) {
        let normalized = Self.normalize(pattern)
        guard !normalized.isEmpty, !patterns.contains(normalized) else { return }
        patterns.append(normalized)
    }

    public mutating func remove(_ pattern: String) {
        patterns.removeAll { $0 == Self.normalize(pattern) }
    }

    static func normalize(_ pattern: String) -> String {
        let expanded = (pattern as NSString).expandingTildeInPath
        return (expanded as NSString).standardizingPath
    }

    /// True kalau URL ada di bawah salah satu pattern exclude user.
    public func isExcluded(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return patterns.contains { pattern in
            path == pattern || path.hasPrefix(pattern + "/")
        }
    }
}

// MARK: - Recency Guard (TRD §4.20 p8)

/// Apapun yang dimodifikasi dalam N hari terakhir default-nya NGGAK ke-check
/// di list rekomendasi (badge "Baru" di UI). User tetep bisa pilih manual.
public enum RecencyGuard {
    public static let defaultsKey = "app.respite.recencyDays"
    public static let defaultDays = 7

    public static func thresholdDays(from defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: defaultsKey)
        return value > 0 ? value : defaultDays
    }

    public static func shouldSelectByDefault(
        lastModified: Date,
        now: Date = Date(),
        days: Int = defaultDays
    ) -> Bool {
        lastModified < now.addingTimeInterval(-Double(days) * 86_400)
    }
}
