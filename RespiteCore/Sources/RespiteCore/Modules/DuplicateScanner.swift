import Foundation
import ObjectiveC
import CryptoKit

/// Satu file dalam grup duplikat.
public struct DuplicateFile: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Salinan pertama (terlama) — disarankan disimpan (TRD §4.7).
    public let isSuggestedKeep: Bool
    /// Recency Guard: file < N hari → default tidak tercentang.
    public let isSelectedByDefault: Bool

    public init(
        url: URL,
        sizeBytes: Int64,
        lastModified: Date,
        isSuggestedKeep: Bool,
        isSelectedByDefault: Bool
    ) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSuggestedKeep = isSuggestedKeep
        self.isSelectedByDefault = isSelectedByDefault
    }
}

/// Grup file yang terbukti identik byte-per-byte (full hash sama).
public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Ukuran per file (semua anggota identik).
    public let sizeBytes: Int64
    public let files: [DuplicateFile]

    /// Potensi hemat kalau semua kecuali satu dihapus.
    public var reclaimableBytes: Int64 {
        Int64(max(0, files.count - 1)) * sizeBytes
    }

    public init(sizeBytes: Int64, files: [DuplicateFile]) {
        self.id = UUID()
        self.sizeBytes = sizeBytes
        self.files = files
    }
}

public enum DuplicateEvent: Sendable {
    case progress(filesScanned: Int)
    case found(DuplicateGroup)
    case finished(groups: Int, reclaimableBytes: Int64)
}

/// Duplicate Finder (TRD §4.7) — tiga fase biar nggak baca seluruh disk:
/// 1. Kelompokkan per ukuran (gratis dari metadata).
/// 2. Kandidat ukuran sama → hash 4 KB pertama.
/// 3. Partial sama → full SHA-256 baru dinyatakan duplikat.
///
/// Deteksi ini byte-identik — berlaku untuk SEMUA jenis file termasuk foto.
/// Foto "mirip" (beda byte) itu ranah Similar Photos (P2, perceptual hash).
public struct DuplicateScanner {
    struct Candidate: Sendable {
        let url: URL
        let modified: Date
        let size: Int64
        /// Identitas fisik file (inode). Hard link = path beda, inode SAMA —
        /// menghapus salah satunya TIDAK membebaskan ruang (data tetap ada
        /// lewat path lain). Dipakai buat nyaring duplikat palsu.
        let resourceID: Data?
    }

    public struct Config: Sendable {
        public var root: URL
        public var minBytes: Int64
        public var recencyDays: Int
        public var homeDirectory: URL

        public init(
            root: URL,
            minBytes: Int64 = 1_000_000,
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

    /// Batas worker hashing — IO-bound, jadi jumlah core cukup buat jadi
    /// proxy concurrency yang wajar tanpa membanjiri disk dengan ribuan FD.
    private static let hashWorkers = max(2, ProcessInfo.processInfo.activeProcessorCount)

    public func scan() -> AsyncThrowingStream<DuplicateEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Fase 1: kelompokkan per ukuran (tanpa baca isi file).
                var bySize: [Int64: [Candidate]] = [:]
                var scanned = 0
                let enumerator = FileManager.default.enumerator(
                    at: config.root,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsPackageDescendants]
                )
                while let item = enumerator?.nextObject() {
                    if Task.isCancelled { break }
                    autoreleasepool {
                    guard
                        let url = item as? URL,
                        let values = try? url.resourceValues(
                            forKeys: [
                                .fileSizeKey, .contentModificationDateKey,
                                .isRegularFileKey, .fileResourceIdentifierKey,
                            ]
                        ),
                        values.isRegularFile == true,
                        let size = values.fileSize
                    else { return }

                    scanned += 1
                    if scanned % 512 == 0 {
                        continuation.yield(.progress(filesScanned: scanned))
                    }
                    guard Int64(size) >= config.minBytes else { return }
                    if whitelist.isExcluded(url) { return }
                    if ProtectedList.isProtected(url, homeDirectory: config.homeDirectory) { return }
                    bySize[Int64(size), default: []].append(Candidate(
                        url: url,
                        modified: values.contentModificationDate ?? .distantPast,
                        size: Int64(size),
                        resourceID: values.fileResourceIdentifier as? Data
                    ))
                    }
                }

                var groupCount = 0
                var reclaimable: Int64 = 0

                // Grup terbesar (potensi hemat terbesar) dulu — user lihat
                // hasil yang paling ngaruh di awal, bukan alphabet acak dict.
                let orderedBuckets = bySize
                    .filter { $0.value.count > 1 }
                    .sorted { lhs, rhs in
                        let lhsGain = Int64(lhs.value.count - 1) * lhs.key
                        let rhsGain = Int64(rhs.value.count - 1) * rhs.key
                        return lhsGain > rhsGain
                    }

                for (_, candidates) in orderedBuckets {
                    if Task.isCancelled { break }

                    // Fase 2: partial hash 4 KB pertama + 4 KB terakhir,
                    // paralel. Head-only bikin file media yang headernya
                    // sama (MP4/JPEG dari device sama) lolos semua ke
                    // fase 3 yang mahal — tail memangkas itu drastis.
                    let partials = await Self.hashInParallel(candidates) { candidate in
                        Self.partialHash(candidate.url, size: candidate.size).map { (candidate, $0) }
                    }

                    var byPartial: [String: [Candidate]] = [:]
                    for (candidate, hash) in partials {
                        byPartial[hash, default: []].append(candidate)
                    }

                    // Fase 3: full hash buat yang partial-nya sama, paralel.
                    for (_, partialMatches) in byPartial where partialMatches.count > 1 {
                        if Task.isCancelled { break }
                        let fulls = await Self.hashInParallel(partialMatches) { candidate in
                            Self.fullHash(candidate.url).map { (candidate, $0) }
                        }

                        var byFull: [String: [Candidate]] = [:]
                        for (candidate, hash) in fulls {
                            byFull[hash, default: []].append(candidate)
                        }

                        for (_, identical) in byFull where identical.count > 1 {
                            // Hard link: seluruh path menunjuk file fisik yang sama
                            // → bukan duplikat beneran, hapusnya nggak membebaskan
                            // apa pun. Saring (inode sama persis satu-atu pun tidak).
                            let distinctInodes = Set(identical.compactMap(\.resourceID))
                            if distinctInodes.count == 1, distinctInodes.first != nil {
                                continue
                            }
                            // Terlama duluan — itu yang disarankan disimpan.
                            let sorted = identical.sorted { $0.modified < $1.modified }
                            let files = sorted.enumerated().map { index, candidate in
                                DuplicateFile(
                                    url: candidate.url,
                                    sizeBytes: candidate.size,
                                    lastModified: candidate.modified,
                                    isSuggestedKeep: index == 0,
                                    isSelectedByDefault: index > 0 && RecencyGuard.shouldSelectByDefault(
                                        lastModified: candidate.modified,
                                        days: config.recencyDays
                                    )
                                )
                            }
                            let group = DuplicateGroup(sizeBytes: sorted[0].size, files: files)
                            groupCount += 1
                            reclaimable += group.reclaimableBytes
                            continuation.yield(.found(group))
                        }
                    }
                }

                continuation.yield(.finished(groups: groupCount, reclaimableBytes: reclaimable))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Hashing

    /// Jalankan operasi hash di TaskGroup dengan concurrency dibatasi —
    /// hasil dikembalikan seurutan input biar output deterministik.
    private static func hashInParallel(
        _ candidates: [Candidate],
        _ hashOne: @escaping @Sendable (Candidate) -> (Candidate, String)?
    ) async -> [(Candidate, String)] {
        var results = [Int: (Candidate, String)]()
        var nextIndex = 0
        await withTaskGroup(of: (Int, (Candidate, String)?).self) { group in
            // Isi worker sampai penuh, jalan satu → isi lagi (bounded pool).
            while nextIndex < candidates.count && nextIndex < hashWorkers {
                let index = nextIndex
                group.addTask { (index, hashOne(candidates[index])) }
                nextIndex += 1
            }
            while let (index, result) = await group.next() {
                if let result { results[index] = result }
                if nextIndex < candidates.count {
                    let index2 = nextIndex
                    group.addTask { (index2, hashOne(candidates[index2])) }
                    nextIndex += 1
                }
            }
        }
        return results.sorted { $0.key < $1.key }.map(\.value)
    }

    /// Hash 4 KB pertama + 4 KB terakhir (kalau file > 8 KB). Ukuran sudah
    /// diketahui dari fase 1 — jadi seek ke ekor nggak butuh stat ulang.
    static func partialHash(_ url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var data = (try? handle.read(upToCount: 4096)) ?? Data()
        if size > 8192 {
            let tailOffset = UInt64(max(0, size - 4096))
            if (try? handle.seek(toOffset: tailOffset)) != nil,
               let tail = try? handle.read(upToCount: 4096) {
                data.append(tail)
            }
        }
        return SHA256.hash(data: data).description
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().description
    }
}
