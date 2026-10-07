import Foundation

/// Satu aplikasi terinstall.
public struct InstalledApp: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let sizeBytes: Int64

    public init(url: URL, name: String, bundleID: String?, sizeBytes: Int64) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
    }
}

/// Satu sisa data aplikasi. `confidence` nentuin default tercentang atau nggak
/// (TRD §4.2: confidence rendah jangan auto-check).
public struct LeftoverItem: Identifiable, Sendable, Equatable {
    public enum Confidence: String, Sendable, Equatable {
        /// Cocok persis dengan bundle ID.
        case exact
        /// Cocok nama app — Electron apps sering pakai nama beda dari bundle ID.
        case fuzzy
    }

    public let id: UUID
    public let url: URL
    public let confidence: Confidence
    public let sizeBytes: Int64

    public var isSelectedByDefault: Bool { confidence == .exact }

    public init(url: URL, confidence: Confidence, sizeBytes: Int64) {
        self.id = UUID()
        self.url = url
        self.confidence = confidence
        self.sizeBytes = sizeBytes
    }
}

public enum AppCatalogEvent: Sendable {
    case found(InstalledApp)
    case finished(total: Int)
}

public enum AppCatalog {
    static var defaultPaths: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Ukur satu .app → InstalledApp. Skip app sistem Apple & Respite sendiri.
    static func makeInstalledApp(from bundleURL: URL) -> InstalledApp? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        let bundleID = dict["CFBundleIdentifier"] as? String

        // Jangan tawarin: app sistem Apple (SIP-protected) & diri sendiri.
        if let bundleID, bundleID.hasPrefix("com.apple.") { return nil }
        if let bundleID {
            let lower = bundleID.lowercased()
            // "ringkas" = nama lama — guard ini ada sebelum rename, tetap
            // dipertahankan biar build lama di sistem user ketangkep juga.
            if lower.contains("respite") || lower.contains("ringkas") { return nil }
        }

        let rawName = (dict["CFBundleName"] as? String) ?? ""
        let name = rawName.isEmpty
            ? bundleURL.deletingPathExtension().lastPathComponent
            : rawName
        return InstalledApp(
            url: bundleURL,
            name: name,
            bundleID: bundleID,
            sizeBytes: FileTreeSizer.size(of: bundleURL)
        )
    }

    /// Versi streaming — app diukur PARALEL (deep size tiap bundle =
    /// IO-bound; koleksi app besar bisa ratusan GB total) tapi di-yield
    /// BERURUTAN: index terkecil yang belum keluar ditahan sampai lengkap,
    /// jadi urutan tetap stabil & UI tetap nampilin progres, bukan blank.
    public static func scanApps(searchPaths: [URL]? = nil) -> AsyncThrowingStream<AppCatalogEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let paths = searchPaths ?? defaultPaths
                var candidates: [URL] = []
                for root in paths {
                    guard let children = try? FileManager.default.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: []
                    ) else { continue }
                    candidates.append(contentsOf: children.filter { $0.pathExtension == "app" })
                }

                let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)
                var measured = [Int: InstalledApp]()
                var nextToEmit = 0
                var nextIndex = 0

                func emitReady() {
                    while let app = measured.removeValue(forKey: nextToEmit) {
                        continuation.yield(.found(app))
                        nextToEmit += 1
                    }
                }

                await withTaskGroup(of: (Int, InstalledApp?).self) { group in
                    while nextIndex < candidates.count && nextIndex < workers {
                        let index = nextIndex
                        group.addTask { (index, Self.makeInstalledApp(from: candidates[index])) }
                        nextIndex += 1
                    }
                    while let (index, app) = await group.next() {
                        if let app { measured[index] = app }
                        emitReady()
                        if nextIndex < candidates.count {
                            let index2 = nextIndex
                            group.addTask { (index2, Self.makeInstalledApp(from: candidates[index2])) }
                            nextIndex += 1
                        }
                    }
                }
                emitReady()

                continuation.yield(.finished(total: nextToEmit))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Versi sinkron (dipakai unit test & refresh cepat).
    public static func installedApps(searchPaths: [URL]? = nil) -> [InstalledApp] {
        let paths = searchPaths ?? defaultPaths
        return paths
            .compactMap { root in
                (try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )) ?? []
            }
            .flatMap { $0 }
            .filter { $0.pathExtension == "app" }
            .compactMap { makeInstalledApp(from: $0) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

public enum LeftoverScanner {
    /// Lokasi-lokasi sisa data — injectable biar unit test pakai fixture home.
    public struct Locations: Sendable {
        public var applicationSupport: URL?
        public var caches: URL?
        public var preferences: URL?
        public var launchAgents: URL?
        public var savedApplicationState: URL?
        public var logs: URL?
        public var httpStorage: URL?
        public var cookies: URL?

        public init(
            applicationSupport: URL? = nil,
            caches: URL? = nil,
            preferences: URL? = nil,
            launchAgents: URL? = nil,
            savedApplicationState: URL? = nil,
            logs: URL? = nil,
            httpStorage: URL? = nil,
            cookies: URL? = nil
        ) {
            self.applicationSupport = applicationSupport
            self.caches = caches
            self.preferences = preferences
            self.launchAgents = launchAgents
            self.savedApplicationState = savedApplicationState
            self.logs = logs
            self.httpStorage = httpStorage
            self.cookies = cookies
        }

        public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Locations {
            let library = home.appendingPathComponent("Library")
            return Locations(
                applicationSupport: library.appendingPathComponent("Application Support"),
                caches: library.appendingPathComponent("Caches"),
                preferences: library.appendingPathComponent("Preferences"),
                launchAgents: library.appendingPathComponent("LaunchAgents"),
                savedApplicationState: library.appendingPathComponent("Saved Application State"),
                logs: library.appendingPathComponent("Logs"),
                httpStorage: library.appendingPathComponent("HTTPStorages"),
                cookies: library.appendingPathComponent("Cookies")
            )
        }
    }

    public static func leftovers(
        for app: InstalledApp,
        locations: Locations = .standard()
    ) -> [LeftoverItem] {
        guard let bundleID = app.bundleID, !bundleID.isEmpty else { return [] }
        let fm = FileManager.default
        var items: [LeftoverItem] = []

        func add(_ url: URL, _ confidence: LeftoverItem.Confidence) {
            guard fm.fileExists(atPath: url.path) else { return }
            items.append(LeftoverItem(
                url: url,
                confidence: confidence,
                sizeBytes: FileTreeSizer.size(of: url)
            ))
        }

        if let preferences = locations.preferences {
            add(preferences.appendingPathComponent("\(bundleID).plist"), .exact)
        }
        if let caches = locations.caches {
            add(caches.appendingPathComponent(bundleID), .exact)
            add(caches.appendingPathComponent(app.name), .fuzzy)
        }
        if let support = locations.applicationSupport {
            add(support.appendingPathComponent(bundleID), .exact)
            add(support.appendingPathComponent(app.name), .fuzzy)
        }
        if let agents = locations.launchAgents {
            add(agents.appendingPathComponent("\(bundleID).plist"), .exact)
        }
        if let state = locations.savedApplicationState {
            add(state.appendingPathComponent("\(bundleID).savedState"), .exact)
        }
        if let logs = locations.logs {
            add(logs.appendingPathComponent(app.name), .fuzzy)
        }
        if let storage = locations.httpStorage {
            add(storage.appendingPathComponent(bundleID), .exact)
        }
        if let cookies = locations.cookies {
            add(cookies.appendingPathComponent("\(bundleID).binarycookies"), .exact)
        }
        return items
    }
}
