import Foundation

/// Satu target cache developer yang bisa dibersihin.
public struct DevCacheTarget: Identifiable, Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable, Equatable {
        case xcodeDerivedData
        case xcodeArchives
        case cocoapodsCache
        case spmCache
        case homebrewCache
        case nodeModules
        case composerCache
        case goBuildCache
        case goModCache
        case cargoRegistry
        case cargoGitCache
        /// Log aplikasi AI lokal (Ollama, LM Studio) — LOG doang,
        /// model (GB-an, mahal diunduh ulang) TIDAK PERNAH jadi target.
        case aiLogs
    }

    public let id: UUID
    public let kind: Kind
    public let url: URL
    /// Nama project/app pemilik (untuk label UI).
    public let title: String
    public let sizeBytes: Int64
    public let lastModified: Date
    public let isSelectedByDefault: Bool

    public init(
        kind: Kind,
        url: URL,
        title: String,
        sizeBytes: Int64,
        lastModified: Date,
        isSelectedByDefault: Bool
    ) {
        self.id = UUID()
        self.kind = kind
        self.url = url
        self.title = title
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public enum DevCacheEvent: Sendable {
    case found(DevCacheTarget)
    case finished(count: Int, totalBytes: Int64)
}

/// Deteksi tool yang keinstall DULU (TRD §4.6) — jangan nawarin bersih-bersih
/// Docker kalau Docker-nya nggak ada. Path injectable buat test.
public enum DevTools {
    public struct Tool: Identifiable, Sendable, Equatable {
        public enum Kind: String, Sendable, Equatable {
            case xcode, homebrew, docker, node, composer, go, rust
        }

        public let kind: Kind
        public let isInstalled: Bool
        public var id: String { kind.rawValue }

        public init(kind: Kind, isInstalled: Bool) {
            self.kind = kind
            self.isInstalled = isInstalled
        }
    }

    public static func detect(
        xcodePaths: [URL] = [URL(fileURLWithPath: "/Applications/Xcode.app")],
        brewPaths: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            URL(fileURLWithPath: "/usr/local/bin/brew"),
        ],
        dockerPaths: [URL] = [
            URL(fileURLWithPath: "/usr/local/bin/docker"),
            URL(fileURLWithPath: "/opt/homebrew/bin/docker"),
            URL(fileURLWithPath: "/Applications/Docker.app"),
        ],
        nodePaths: [URL] = [
            URL(fileURLWithPath: "/usr/local/bin/node"),
            URL(fileURLWithPath: "/opt/homebrew/bin/node"),
        ],
        composerPaths: [URL] = [
            URL(fileURLWithPath: "/usr/local/bin/composer"),
            URL(fileURLWithPath: "/opt/homebrew/bin/composer"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".composer/composer.phar"),
            // Cache-nya sendiri juga jadi sinyal "pernah dipakai".
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".composer/cache"),
        ],
        goPaths: [URL] = [
            URL(fileURLWithPath: "/usr/local/go/bin/go"),
            URL(fileURLWithPath: "/opt/homebrew/bin/go"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/go-build"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("go/pkg/mod"),
        ],
        rustPaths: [URL] = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/cargo"),
            URL(fileURLWithPath: "/opt/homebrew/bin/cargo"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/registry"),
        ]
    ) -> [Tool] {
        func installed(_ paths: [URL]) -> Bool {
            paths.contains { FileManager.default.fileExists(atPath: $0.path) }
        }
        return [
            Tool(kind: .xcode, isInstalled: installed(xcodePaths)),
            Tool(kind: .homebrew, isInstalled: installed(brewPaths)),
            Tool(kind: .docker, isInstalled: installed(dockerPaths)),
            Tool(kind: .node, isInstalled: installed(nodePaths)),
            Tool(kind: .composer, isInstalled: installed(composerPaths)),
            Tool(kind: .go, isInstalled: installed(goPaths)),
            Tool(kind: .rust, isInstalled: installed(rustPaths)),
        ]
    }
}

/// Scanner cache developer — semua target filesystem (tanpa shell out;
/// pembacaan `docker system df` & `brew cleanup` nyusul bareng eksekusi
/// command yang di-gate). Roots injectable buat unit test.
public struct DevCacheScanner {
    public struct Roots: Sendable {
        public var derivedData: URL?
        public var archives: URL?
        public var cocoapodsCache: URL?
        public var spmCache: URL?
        public var homebrewCache: URL?
        /// Folder project yang user pilih buat dicari node_modules-nya.
        public var nodeModulesSearchRoots: [URL]
        public var composerCache: URL?
        public var goBuildCache: URL?
        public var goModCache: URL?
        /// Registry + git deps Cargo — `~/.cargo/bin` (toolchain) TIDAK PERNAH
        /// jadi target.
        public var cargoRegistry: URL?
        public var cargoGitCache: URL?
        /// Log Ollama & LM Studio (muncul di hasil kalau foldernya ada).
        public var aiLogsRoots: [(title: String, url: URL)] = []

        public init(
            derivedData: URL? = nil,
            archives: URL? = nil,
            cocoapodsCache: URL? = nil,
            spmCache: URL? = nil,
            homebrewCache: URL? = nil,
            nodeModulesSearchRoots: [URL] = [],
            composerCache: URL? = nil,
            goBuildCache: URL? = nil,
            goModCache: URL? = nil,
            cargoRegistry: URL? = nil,
            cargoGitCache: URL? = nil,
            aiLogsRoots: [(title: String, url: URL)] = []
        ) {
            self.derivedData = derivedData
            self.archives = archives
            self.cocoapodsCache = cocoapodsCache
            self.spmCache = spmCache
            self.homebrewCache = homebrewCache
            self.nodeModulesSearchRoots = nodeModulesSearchRoots
            self.composerCache = composerCache
            self.goBuildCache = goBuildCache
            self.goModCache = goModCache
            self.cargoRegistry = cargoRegistry
            self.cargoGitCache = cargoGitCache
            self.aiLogsRoots = aiLogsRoots
        }

        public static func standard(
            home: URL = FileManager.default.homeDirectoryForCurrentUser,
            nodeRoots: [URL] = []
        ) -> Roots {
            let dev = home.appendingPathComponent("Library/Developer/Xcode")
            let caches = home.appendingPathComponent("Library/Caches")
            return Roots(
                derivedData: dev.appendingPathComponent("DerivedData"),
                archives: dev.appendingPathComponent("Archives"),
                cocoapodsCache: caches.appendingPathComponent("CocoaPods"),
                spmCache: caches.appendingPathComponent("org.swift.swiftpm"),
                homebrewCache: caches.appendingPathComponent("Homebrew"),
                nodeModulesSearchRoots: nodeRoots,
                composerCache: home.appendingPathComponent(".composer/cache"),
                goBuildCache: caches.appendingPathComponent("go-build"),
                goModCache: home.appendingPathComponent("go/pkg/mod"),
                cargoRegistry: home.appendingPathComponent(".cargo/registry"),
                cargoGitCache: home.appendingPathComponent(".cargo/git"),
                aiLogsRoots: [
                    ("Ollama — log", home.appendingPathComponent(".ollama/logs")),
                    ("Ollama — log", home.appendingPathComponent("Library/Logs/Ollama")),
                    ("LM Studio — log", home.appendingPathComponent(".lmstudio/logs")),
                    ("LM Studio — log", home.appendingPathComponent("Library/Logs/LM Studio")),
                ]
            )
        }
    }

    public let roots: Roots
    public let whitelist: UserWhitelist
    public let recencyDays: Int

    public init(
        roots: Roots = .standard(),
        whitelist: UserWhitelist = .load(),
        recencyDays: Int = RecencyGuard.thresholdDays()
    ) {
        self.roots = roots
        self.whitelist = whitelist
        self.recencyDays = recencyDays
    }

    public func scan() -> AsyncThrowingStream<DevCacheEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Kumpulkan SEMUA job dulu (listing top-level murah), urutan
                // dipertahankan; yang mahal (deep size) dihitung PARALEL.
                struct Job: Sendable {
                    let url: URL?
                    let kind: DevCacheTarget.Kind
                    let recencyDays: Int
                    let titleOverride: String?
                }
                var jobs: [Job] = []

                // Xcode DerivedData: per project.
                if let derivedData = roots.derivedData {
                    for child in topLevelChildren(derivedData) {
                        jobs.append(Job(url: child, kind: .xcodeDerivedData, recencyDays: recencyDays, titleOverride: nil))
                    }
                }
                // Xcode Archives: Recency Guard 90 hari — arsip build
                // terakhir jangan ikut kehapus (TRD §4.6).
                if let archives = roots.archives {
                    for child in topLevelChildren(archives) {
                        jobs.append(Job(url: child, kind: .xcodeArchives, recencyDays: 90, titleOverride: nil))
                    }
                }
                // Cache satuan (CocoaPods / SPM / Homebrew / Composer / Go / Cargo).
                jobs.append(contentsOf: [
                    Job(url: roots.cocoapodsCache, kind: .cocoapodsCache, recencyDays: recencyDays, titleOverride: "CocoaPods"),
                    Job(url: roots.spmCache, kind: .spmCache, recencyDays: recencyDays, titleOverride: "Swift Package Manager"),
                    Job(url: roots.homebrewCache, kind: .homebrewCache, recencyDays: recencyDays, titleOverride: "Homebrew"),
                    Job(url: roots.composerCache, kind: .composerCache, recencyDays: recencyDays, titleOverride: "Composer (PHP)"),
                    Job(url: roots.goBuildCache, kind: .goBuildCache, recencyDays: recencyDays, titleOverride: "Go — build cache"),
                    Job(url: roots.goModCache, kind: .goModCache, recencyDays: recencyDays, titleOverride: "Go — module cache"),
                    Job(url: roots.cargoRegistry, kind: .cargoRegistry, recencyDays: recencyDays, titleOverride: "Cargo — registry"),
                    Job(url: roots.cargoGitCache, kind: .cargoGitCache, recencyDays: recencyDays, titleOverride: "Cargo — dependensi git"),
                ])
                // node_modules: cuma di folder yang user pilih (TRD §4.6 —
                // jangan full-disk otomatis), jangan turun ke dalam
                // node_modules lain (nested).
                for searchRoot in roots.nodeModulesSearchRoots {
                    for found in findNodeModules(under: searchRoot) {
                        jobs.append(Job(url: found, kind: .nodeModules, recencyDays: recencyDays, titleOverride: nil))
                    }
                }
                // Log aplikasi AI lokal — LOG saja, model tidak pernah disentuh.
                for aiRoot in roots.aiLogsRoots {
                    jobs.append(Job(url: aiRoot.url, kind: .aiLogs, recencyDays: recencyDays, titleOverride: aiRoot.title))
                }

                // Bounded pool: deep size tiap target = IO-bound, paralel
                // lumayan ngejar DerivedData/SPM yang isinya ratusan ribu file.
                let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)
                var measured = [Int: DevCacheTarget?]()
                var nextIndex = 0
                await withTaskGroup(of: (Int, DevCacheTarget?).self) { group in
                    while nextIndex < jobs.count && nextIndex < workers {
                        let index = nextIndex
                        let job = jobs[index]
                        group.addTask { (index, self.measure(job.url, kind: job.kind, recencyDays: job.recencyDays, titleOverride: job.titleOverride)) }
                        nextIndex += 1
                    }
                    while let (index, target) = await group.next() {
                        measured[index] = target
                        if nextIndex < jobs.count {
                            let index2 = nextIndex
                            let job2 = jobs[index2]
                            group.addTask { (index2, self.measure(job2.url, kind: job2.kind, recencyDays: job2.recencyDays, titleOverride: job2.titleOverride)) }
                            nextIndex += 1
                        }
                    }
                }

                var count = 0
                var totalBytes: Int64 = 0
                for index in jobs.indices {
                    if Task.isCancelled { break }
                    guard let target = measured[index] ?? nil else { continue }
                    count += 1
                    totalBytes += target.sizeBytes
                    continuation.yield(.found(target))
                }

                continuation.yield(.finished(count: count, totalBytes: totalBytes))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Bantu

    /// "MyProject-abcdefghij" → "MyProject" (hash Xcode dibuang); kalau
    /// formatnya nggak cocok, kembalikan apa adanya.
    static func prettyDerivedDataName(_ name: String) -> String {
        guard let dash = name.range(of: "-", options: .backwards) else { return name }
        let suffix = String(name[dash.upperBound...])
        if suffix.count >= 10, suffix.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return String(name[..<dash.lowerBound])
        }
        return name
    }

    private func topLevelChildren(_ root: URL) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter { !whitelist.isExcluded($0) }
    }

    /// Cache murni yang murah dibangun ulang — selalu masuk rekomendasi.
    static let alwaysRecommendedKinds: Set<DevCacheTarget.Kind> = [
        .cocoapodsCache, .spmCache, .homebrewCache, .goBuildCache, .aiLogs,
    ]

    private func measure(
        _ url: URL?,
        kind: DevCacheTarget.Kind,
        recencyDays: Int,
        titleOverride: String? = nil
    ) -> DevCacheTarget? {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              !ProtectedList.isProtected(url) else { return nil }
        let measured = FileTreeSizer.sizeAndLatestModified(of: url)
        guard measured.sizeBytes > 0 else { return nil }
        // Cache murni yang murah dibangun ulang → SELALU direkomendasikan.
        // Recency Guard cuma buat yang mahal kalau masih aktif dipakai:
        // DerivedData project aktif, arsip, node_modules, dan cache
        // dependensi yang harus diunduh ulang (Go mod / Cargo / Composer).
        let isSelectedByDefault = Self.alwaysRecommendedKinds.contains(kind)
            ? true
            : RecencyGuard.shouldSelectByDefault(
                lastModified: measured.lastModified, days: recencyDays
            )
        // Folder DerivedData bentuknya "NamaProject-hash10karakter" —
        // hash-nya noise buat user, dibuang biar keliatan nama projectnya.
        let title: String
        if kind == .xcodeDerivedData, titleOverride == nil {
            title = Self.prettyDerivedDataName(url.lastPathComponent)
        } else {
            title = titleOverride ?? url.lastPathComponent
        }
        return DevCacheTarget(
            kind: kind,
            url: url,
            title: title,
            sizeBytes: measured.sizeBytes,
            lastModified: measured.lastModified,
            isSelectedByDefault: isSelectedByDefault
        )
    }

    /// Cari folder node_modules maksimal 4 level — tidak turun ke dalam
    /// node_modules (nested), skip folder hidden biar cepat.
    private func findNodeModules(under root: URL, depth: Int = 0) -> [URL] {
        guard depth <= 4 else { return [] }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for child in children {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if child.lastPathComponent == "node_modules" {
                results.append(child)
            } else if child.lastPathComponent != "Library" {
                results += findNodeModules(under: child, depth: depth + 1)
            }
        }
        return results
    }
}
