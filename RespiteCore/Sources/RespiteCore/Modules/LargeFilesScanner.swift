import Foundation
import ObjectiveC

/// Satu file besar/lama hasil scan (level file, bukan folder owner).
public struct FileHit: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Recency Guard: file yang disentuh < N hari → false (badge "Baru").
    public let isSelectedByDefault: Bool

    public init(url: URL, sizeBytes: Int64, lastModified: Date, isSelectedByDefault: Bool) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public enum LargeFilesEvent: Sendable {
    case found(FileHit)
    case finished(count: Int, totalBytes: Int64)
}

/// Large & Old Files Finder (TRD §4.3): enumerasi home directory, file dengan
/// ukuran ≥ threshold. Anak top-level di-scan **paralel** (TaskGroup) — SSD
/// concurrent jauh lebih cepat daripada satu enumerator serial.
/// Protected List & whitelist dikecualikan; Trash sendiri nggak ikut.
public struct LargeFilesScanner {
    public struct Config: Sendable {
        public var root: URL
        public var minBytes: Int64
        public var recencyDays: Int
        /// Inject fake home buat unit test (match ProtectedList).
        public var homeDirectory: URL

        public init(
            root: URL,
            minBytes: Int64 = 250 * 1000 * 1000,
            recencyDays: Int = RecencyGuard.defaultDays,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) {
            self.root = root
            self.minBytes = minBytes
            self.recencyDays = recencyDays
            self.homeDirectory = homeDirectory
        }
    }

    public let config: Config
    public let whitelist: UserWhitelist

    public init(config: Config, whitelist: UserWhitelist = .load()) {
        self.config = config
        self.whitelist = whitelist
    }

    public func scan() -> AsyncThrowingStream<LargeFilesEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let trashPath = config.homeDirectory
                    .appendingPathComponent(".Trash")
                    .standardizedFileURL.path
                // Prefix match harus exact di path-component — hasPrefix polos
                // bakal ikut nge-skip sibling kayak ".TrashEkstra".
                func isInTrash(_ url: URL) -> Bool {
                    let path = url.standardizedFileURL.path
                    return path == trashPath || path.hasPrefix(trashPath + "/")
                }

                // Prefilter top-level: buat unit paralel sekaligus buang
                // Trash/protected/whitelist dari awal.
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: config.root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )) ?? []
                let scanRoots = children.filter { child in
                    if isInTrash(child) { return false }
                    if whitelist.isExcluded(child) { return false }
                    if ProtectedList.isProtected(child, homeDirectory: config.homeDirectory) {
                        return false
                    }
                    return true
                }

                var totalCount = 0
                var totalBytes: Int64 = 0

                await withTaskGroup(of: (Int, Int64).self) { group in
                    for scanRoot in scanRoots {
                        group.addTask { [config, whitelist] in
                            // FileManager fresh per task — enumerator thread-safe.
                            let fileManager = FileManager()
                            // Anak top-level yang berupa file: enumerator(at:) untuk
                            // file biasa nggak yield apa-apa — cek langsung.
                            let isDir = (try? scanRoot.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                            if !isDir {
                                guard let hit = Self.hit(for: scanRoot, config: config) else { return (0, 0) }
                                continuation.yield(.found(hit))
                                return (1, hit.sizeBytes)
                            }
                            guard let enumerator = fileManager.enumerator(
                                at: scanRoot,
                                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                                options: [.skipsPackageDescendants]
                            ) else { return (0, 0) }

                            var count = 0
                            var bytes: Int64 = 0
                            while let item = enumerator.nextObject() {
                                if Task.isCancelled { break }
                                // Pool per item: objek bridge ObjC (resourceValues,
                                // standardizedFileURL) nggak numpuk jadi high-water
                                // ratusan MB setelah scan besar (bug 2026-09-22).
                                autoreleasepool {
                                guard let url = item as? URL else { return }

                                if isInTrash(url)
                                    || whitelist.isExcluded(url)
                                    || ProtectedList.isProtected(url, homeDirectory: config.homeDirectory) {
                                    // Jangan jalan ke dalam subtree yang dikecualikan.
                                    enumerator.skipDescendants()
                                    return
                                }
                                guard let hit = Self.hit(for: url, config: config) else { return }
                                count += 1
                                bytes += hit.sizeBytes
                                continuation.yield(.found(hit))
                                }
                            }
                            return (count, bytes)
                        }
                    }
                    for await (count, bytes) in group {
                        totalCount += count
                        totalBytes += bytes
                    }
                }

                continuation.yield(.finished(count: totalCount, totalBytes: totalBytes))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    /// FileHit kalau `url` file biasa ≥ minBytes, selain itu nil.
    private static func hit(for url: URL, config: Config) -> FileHit? {
        guard
            let values = try? url.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            ),
            values.isRegularFile == true,
            let size = values.fileSize,
            Int64(size) >= config.minBytes
        else { return nil }

        let modified = values.contentModificationDate ?? .distantPast
        return FileHit(
            url: url,
            sizeBytes: Int64(size),
            lastModified: modified,
            isSelectedByDefault: RecencyGuard.shouldSelectByDefault(
                lastModified: modified, days: config.recencyDays
            )
        )
    }
}
