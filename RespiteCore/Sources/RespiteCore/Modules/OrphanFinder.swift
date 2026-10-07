import Foundation

/// Satu item sisa data tanpa pemilik (aplikasinya sudah tidak terpasang).
public struct OrphanItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    /// Lokasi Library-nya (mis. "Application Support") buat ditampilkan.
    public let locationName: String
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Recency Guard: data yang barusan tersentuh → default tidak tercentang.
    public let isSelectedByDefault: Bool

    public init(
        url: URL,
        locationName: String,
        sizeBytes: Int64,
        lastModified: Date,
        isSelectedByDefault: Bool
    ) {
        self.id = UUID()
        self.url = url
        self.locationName = locationName
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public enum OrphanEvent: Sendable {
    case found(OrphanItem)
    case finished(count: Int, totalBytes: Int64)
}

/// Orphan Finder (inspirasi PureMac, implementasi sendiri): jalan-jalan di
/// lokasi standar ~/Library, cocokkan tiap item dengan aplikasi TERPASANG —
/// yang tidak punya pemilik = kandidat sisa data aplikasi yang sudah dihapus.
///
/// Matching sengaja KETAT (false positive lebih mahal daripada false
/// negative — ini menawarkan penghapusan):
/// 1. Nama item == bundle ID aplikasi, atau bundleID + "." (container varian).
/// 2. File Preferences: "com.vendor.app.plist" → bundle ID.
/// 3. Salah satu komponen path == nama aplikasi (normalized: lowercase tanpa
///    spasi) — nangkap "Google/Chrome" di Application Support.
///
/// Item milik Apple (com.apple.*) SELALU dianggap punya pemilik — sistem,
/// bukan yatim. Whitelist & Protected List dihormati seperti modul lain.
public struct OrphanFinder {
    public struct Locations: Sendable {
        public var applicationSupport: URL?
        public var caches: URL?
        public var preferences: URL?
        public var savedApplicationState: URL?
        public var logs: URL?
        public var httpStorage: URL?
        public var cookies: URL?
        public var containers: URL?
        public var groupContainers: URL?

        public init(
            applicationSupport: URL? = nil,
            caches: URL? = nil,
            preferences: URL? = nil,
            savedApplicationState: URL? = nil,
            logs: URL? = nil,
            httpStorage: URL? = nil,
            cookies: URL? = nil,
            containers: URL? = nil,
            groupContainers: URL? = nil
        ) {
            self.applicationSupport = applicationSupport
            self.caches = caches
            self.preferences = preferences
            self.savedApplicationState = savedApplicationState
            self.logs = logs
            self.httpStorage = httpStorage
            self.cookies = cookies
            self.containers = containers
            self.groupContainers = groupContainers
        }

        /// Lokasi standar di ~/Library (injectable buat unit test).
        public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Locations {
            let library = home.appendingPathComponent("Library")
            return Locations(
                applicationSupport: library.appendingPathComponent("Application Support"),
                caches: library.appendingPathComponent("Caches"),
                preferences: library.appendingPathComponent("Preferences"),
                savedApplicationState: library.appendingPathComponent("Saved Application State"),
                logs: library.appendingPathComponent("Logs"),
                httpStorage: library.appendingPathComponent("HTTPStorages"),
                cookies: library.appendingPathComponent("Cookies"),
                containers: library.appendingPathComponent("Containers"),
                groupContainers: library.appendingPathComponent("Group Containers")
            )
        }

        var entries: [(name: String, root: URL, deepScan: Bool)] {
            [
                ("Application Support", applicationSupport, true),
                ("Caches", caches, true),
                ("Preferences", preferences, false),
                ("Saved Application State", savedApplicationState, true),
                ("Logs", logs, true),
                ("HTTPStorages", httpStorage, true),
                ("Cookies", cookies, true),
                ("Containers", containers, true),
                ("Group Containers", groupContainers, true),
            ]
            .compactMap { name, root, deep in root.map { (name, $0, deep) } }
        }
    }

    public struct Config: Sendable {
        public var minBytes: Int64
        public var recencyDays: Int
        public var homeDirectory: URL

        public init(
            minBytes: Int64 = 1_000_000,
            recencyDays: Int = RecencyGuard.defaultDays,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) {
            self.minBytes = minBytes
            self.recencyDays = recencyDays
            self.homeDirectory = homeDirectory
        }
    }

    public let locations: Locations
    public let config: Config
    public let apps: [AppRef]
    public let whitelist: UserWhitelist

    public init(
        locations: Locations = .standard(),
        config: Config = .init(),
        apps: [AppRef] = AppCatalog.quickCatalog(),
        whitelist: UserWhitelist = .load()
    ) {
        self.locations = locations
        self.config = config
        self.apps = apps
        self.whitelist = whitelist
    }

    public func scan() -> AsyncThrowingStream<OrphanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var count = 0
                var totalBytes: Int64 = 0

                // Anak-anak tiap lokasi diukur paralel (bounded pool,
                // pola scanner lain); urutan emit = urutan input.
                struct Job: Sendable {
                    let url: URL
                    let locationName: String
                    let deep: Bool
                }
                var jobs: [Job] = []
                for (name, root, deep) in locations.entries {
                    guard let children = try? FileManager.default.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: nil,
                        options: []
                    ) else { continue }
                    for child in children {
                        jobs.append(Job(url: child, locationName: name, deep: deep))
                    }
                }

                let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)
                var results = [Int: OrphanItem?]()
                var nextIndex = 0
                await withTaskGroup(of: (Int, OrphanItem?).self) { group in
                    while nextIndex < jobs.count && nextIndex < workers {
                        let index = nextIndex
                        let job = jobs[index]
                        group.addTask { (index, Self.evaluate((url: job.url, locationName: job.locationName, deep: job.deep), finder: self)) }
                        nextIndex += 1
                    }
                    while let (index, item) = await group.next() {
                        results[index] = item
                        if nextIndex < jobs.count {
                            let index2 = nextIndex
                            let job2 = jobs[index2]
                            group.addTask { (index2, Self.evaluate((url: job2.url, locationName: job2.locationName, deep: job2.deep), finder: self)) }
                            nextIndex += 1
                        }
                    }
                }

                for index in jobs.indices {
                    if Task.isCancelled { break }
                    guard let item = results[index] ?? nil else { continue }
                    count += 1
                    totalBytes += item.sizeBytes
                    continuation.yield(.found(item))
                }

                continuation.yield(.finished(count: count, totalBytes: totalBytes))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Evaluasi satu kandidat → item yatim (nil kalau bukan yatim / kekecilan
    /// / terlindungi). Pure enough buat unit test.
    static func evaluate(_ job: (url: URL, locationName: String, deep: Bool), finder: OrphanFinder) -> OrphanItem? {
        let url = job.url
        let name = url.lastPathComponent

        // Item Apple selalu "punya pemilik" — bukan urusan kita.
        if name.lowercased().hasPrefix("com.apple.") || name == "Apple" { return nil }
        if name.hasPrefix(".") { return nil } // hidden/scratch system
        if finder.whitelist.isExcluded(url) { return nil }
        if ProtectedList.isProtected(url, homeDirectory: finder.config.homeDirectory) { return nil }

        if hasOwner(name: name, path: url.path, apps: finder.apps) { return nil }

        let measured = FileTreeSizer.sizeAndLatestModified(of: url)
        guard measured.sizeBytes >= finder.config.minBytes else { return nil }

        return OrphanItem(
            url: url,
            locationName: job.locationName,
            sizeBytes: measured.sizeBytes,
            lastModified: measured.lastModified,
            isSelectedByDefault: RecencyGuard.shouldSelectByDefault(
                lastModified: measured.lastModified,
                days: finder.config.recencyDays
            )
        )
    }

    /// Matching pemilik — strict (lihat catatan doc di atas). Pure & teruji.
    static func hasOwner(name: String, path: String, apps: [AppRef]) -> Bool {
        // Preferences: "com.vendor.app.plist" → bundle ID.
        let bundleCandidate = name.hasSuffix(".plist")
            ? String(name.dropLast(".plist".count))
            : name

        for app in apps {
            if bundleCandidate == app.bundleID { return true }
            if bundleCandidate.hasPrefix(app.bundleID + ".") { return true }
            // Containers varian: "group.<teamid>.x" — cek komponen setelah group.
            if bundleCandidate.hasPrefix("group."),
               bundleCandidate.contains("." + app.bundleID) { return true }
        }

        // Komponen path vs nama aplikasi (normalized) — nangkap vendor folder
        // seperti "Google/Chrome": komponen "Chrome" match nama app "Chrome".
        for app in apps {
            let appNorm = Self.normalize(app: app.name)
            guard appNorm.count >= 3 else { continue } // nama pendek = terlalu mudah cocok
            for component in path.split(separator: "/") {
                let compNorm = Self.normalize(app: String(component))
                if compNorm == appNorm { return true }
            }
        }
        return false
    }

    /// lowercase, buang spasi & tanda baca ringan.
    static func normalize(app name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}
