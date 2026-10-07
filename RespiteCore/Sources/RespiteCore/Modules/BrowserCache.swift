import Foundation

/// Satu browser yang dikenali + lokasi cache-nya.
public struct BrowserTarget: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Chrome/Arc/Brave/Edge — profil di Application Support/<dir>/{Default,Profile *}/Cache
        /// + ~/Library/Caches/<cacheName>.
        case chromium(appSupportDir: String, cachesName: String)
        /// Firefox — ~/Library/Caches/Firefox/Profiles/*/cache2.
        case gecko
        /// Safari — ~/Library/Caches/com.apple.Safari (butuh Full Disk Access).
        case safari
    }

    public let name: String
    /// Buat deteksi app masih berjalan (di layer app via NSWorkspace).
    public let bundleID: String
    /// Nama bundle relatif (dicari di root Applications yang injectable).
    public let appNames: [String]
    public let kind: Kind

    public init(name: String, bundleID: String, appNames: [String], kind: Kind) {
        self.name = name
        self.bundleID = bundleID
        self.appNames = appNames
        self.kind = kind
    }
}

/// Jenis data browser yang bisa dibersihkan.
public enum BrowserDataType: String, CaseIterable, Sendable, Equatable, Identifiable {
    case cache
    case history
    case cookies

    public var id: String { rawValue }
}

/// Hasil scan satu browser.
public struct BrowserScanResult: Identifiable, Sendable, Equatable {
    public let name: String
    public let bundleID: String
    public let installed: Bool
    /// Folder cache yang benar-benar ada (siap diukur/dibersihkan).
    public let cacheRoots: [URL]
    public let totalCacheBytes: Int64
    /// File database riwayat & cookie (Chromium: History/Cookies per profil;
    /// Firefox: places.sqlite/cookies.sqlite; Safari: tidak didukung —
    /// datanya dilindungi TCC dan versi ini cache-only).
    public let historyURLs: [URL]
    public let totalHistoryBytes: Int64
    public let cookiesURLs: [URL]
    public let totalCookiesBytes: Int64

    public var id: String { bundleID }

    public func urls(for type: BrowserDataType) -> [URL] {
        switch type {
        case .cache: return cacheRoots
        case .history: return historyURLs
        case .cookies: return cookiesURLs
        }
    }

    public func totalBytes(for type: BrowserDataType) -> Int64 {
        switch type {
        case .cache: return totalCacheBytes
        case .history: return totalHistoryBytes
        case .cookies: return totalCookiesBytes
        }
    }
}

public enum BrowserCacheScanner {
    /// Registry browser yang didukung v1 (cache only).
    public static let browsers: [BrowserTarget] = [
        BrowserTarget(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            appNames: ["Google Chrome.app"],
            kind: .chromium(appSupportDir: "Google/Chrome", cachesName: "com.google.Chrome")
        ),
        BrowserTarget(
            name: "Arc",
            bundleID: "company.thebrowser.Browser",
            appNames: ["Arc.app"],
            kind: .chromium(appSupportDir: "Arc", cachesName: "Arc")
        ),
        BrowserTarget(
            name: "Brave",
            bundleID: "com.brave.Browser",
            appNames: ["Brave Browser.app"],
            kind: .chromium(appSupportDir: "BraveSoftware/Brave-Browser", cachesName: "com.brave.Browser")
        ),
        BrowserTarget(
            name: "Microsoft Edge",
            bundleID: "com.microsoft.edgemac",
            appNames: ["Microsoft Edge.app"],
            kind: .chromium(appSupportDir: "Microsoft Edge", cachesName: "com.microsoft.edgemac")
        ),
        BrowserTarget(
            name: "Firefox",
            bundleID: "org.mozilla.firefox",
            appNames: ["Firefox.app"],
            kind: .gecko
        ),
        BrowserTarget(
            name: "Safari",
            bundleID: "com.apple.Safari",
            appNames: ["Safari.app"],
            kind: .safari
        ),
    ]

    public static func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirs: [URL]? = nil
    ) -> [BrowserScanResult] {
        let appRoots = applicationsDirs ?? AppCatalog.defaultPaths
        let scanned = browsers.map { target in
            measure(target: target, home: home, appRoots: appRoots)
        }
        return scanned.filter { $0.installed }
    }

    /// Versi paralel — pengukuran cache tiap browser (deep size, bisa GB-an
    /// per profil Chromium) jalan bareng di TaskGroup; urutan hasil =
    /// urutan registry biar UI-nya stabil.
    public static func scanAsync(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirs: [URL]? = nil
    ) async -> [BrowserScanResult] {
        let appRoots = applicationsDirs ?? AppCatalog.defaultPaths
        let results = await withTaskGroup(of: (Int, BrowserScanResult).self) { group in
            for (index, target) in browsers.enumerated() {
                group.addTask {
                    (index, measure(target: target, home: home, appRoots: appRoots))
                }
            }
            var byIndex: [Int: BrowserScanResult] = [:]
            for await (index, result) in group {
                byIndex[index] = result
            }
            return byIndex.sorted { $0.key < $1.key }.map(\.value)
        }
        return results.filter { $0.installed }
    }

    /// Ukur satu browser (instalasi + cache + riwayat + cookie).
    private static func measure(target: BrowserTarget, home: URL, appRoots: [URL]) -> BrowserScanResult {
        let installed = target.appNames.contains { name in
            appRoots.contains { root in
                FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
            }
        }
        func measured(_ urls: [URL]) -> (existing: [URL], bytes: Int64) {
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            return (existing, existing.reduce(Int64(0)) { $0 + FileTreeSizer.size(of: $1) })
        }
        let cache = measured(cacheURLs(for: target, home: home))
        let history = measured(dataURLs(for: .history, target: target, home: home))
        let cookies = measured(dataURLs(for: .cookies, target: target, home: home))
        return BrowserScanResult(
            name: target.name,
            bundleID: target.bundleID,
            installed: installed,
            cacheRoots: cache.existing,
            totalCacheBytes: cache.bytes,
            historyURLs: history.existing,
            totalHistoryBytes: history.bytes,
            cookiesURLs: cookies.existing,
            totalCookiesBytes: cookies.bytes
        )
    }

    /// Lokasi file riwayat/cookie per browser (belum difilter keberadaannya).
    public static func dataURLs(
        for type: BrowserDataType,
        target: BrowserTarget,
        home: URL
    ) -> [URL] {
        guard type != .cache else { return cacheURLs(for: target, home: home) }
        let library = home.appendingPathComponent("Library")
        let appSupport = library.appendingPathComponent("Application Support")
        switch target.kind {
        case let .chromium(appSupportDir, _):
            let profileRoot = appSupport.appendingPathComponent(appSupportDir)
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: profileRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return [] }
            let fileName = type == .history ? "History" : "Cookies"
            return profiles
                .filter { $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile") }
                .map { $0.appendingPathComponent(fileName) }
        case .gecko:
            let profileRoot = appSupport.appendingPathComponent("Firefox/Profiles")
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: profileRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return [] }
            let fileName = type == .history ? "places.sqlite" : "cookies.sqlite"
            return profiles.map { $0.appendingPathComponent(fileName) }
        case .safari:
            // Data riwayat/cookie Safari dilindungi TCC — cache-only di v1.
            return []
        }
    }

    /// Semua kemungkinan lokasi cache browser (belum difilter keberadaannya).
    public static func cacheURLs(for target: BrowserTarget, home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library")
        switch target.kind {
        case let .chromium(appSupportDir, cachesName):
            // Tiap profil: Default, Profile 1, Profile 2, ...
            let profileRoot = library
                .appendingPathComponent("Application Support/\(appSupportDir)")
            var urls: [URL] = []
            if let profiles = try? FileManager.default.contentsOfDirectory(
                at: profileRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) {
                for profile in profiles {
                    let name = profile.lastPathComponent
                    guard name == "Default" || name.hasPrefix("Profile") else { continue }
                    urls.append(profile.appendingPathComponent("Cache"))
                }
            }
            urls.append(library.appendingPathComponent("Caches/\(cachesName)"))
            return urls
        case .gecko:
            let profilesRoot = library.appendingPathComponent("Caches/Firefox/Profiles")
            var urls: [URL] = []
            if let profiles = try? FileManager.default.contentsOfDirectory(
                at: profilesRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) {
                for profile in profiles {
                    urls.append(profile.appendingPathComponent("cache2"))
                }
            }
            return urls
        case .safari:
            return [library.appendingPathComponent("Caches/com.apple.Safari")]
        }
    }
}
