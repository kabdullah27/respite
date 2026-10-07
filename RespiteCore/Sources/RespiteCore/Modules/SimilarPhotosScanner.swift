import Foundation
import ObjectiveC
import ImageIO
import CoreGraphics

/// Metadata satu foto hasil scan.
public struct PhotoItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Average hash 8×8 grayscale (aHash) — 64 bit sidik jari visual.
    public let phash: UInt64

    public init(url: URL, sizeBytes: Int64, lastModified: Date, phash: UInt64) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.phash = phash
    }
}

/// Grup foto mirip — file-nya pakai tipe Duplicate Finder (bentuk data sama:
/// keep suggestion + Recency Guard), biar UI-nya bisa reuse pola.
public struct SimilarPhotoGroup: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let files: [DuplicateFile]

    public init(files: [DuplicateFile]) {
        self.id = UUID()
        self.files = files
    }
}

public enum SimilarPhotosEvent: Sendable {
    case progress(filesScanned: Int)
    case found(SimilarPhotoGroup)
    case finished(groups: Int)
}

/// Similar Photos (TRD §4.15): aHash ringan (downscale 8×8 grayscale →
/// threshold mean → 64 bit), BUKAN ML. Dua foto dianggap mirip kalau jarak
/// Hamming ≤ threshold (default 6 dari 64). Duplikat persis (jarak 0) otomatis
/// ikut kegrup di sini.
public struct SimilarPhotosScanner {
    public struct Config: Sendable {
        public var root: URL
        public var hammingThreshold: Int
        public var minBytes: Int64
        public var homeDirectory: URL

        public init(
            root: URL,
            hammingThreshold: Int = 6,
            minBytes: Int64 = 50_000,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        ) {
            self.root = root
            self.hammingThreshold = hammingThreshold
            self.minBytes = minBytes
            self.homeDirectory = homeDirectory
        }
    }

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "bmp", "webp",
    ]

    public let config: Config
    public let whitelist: UserWhitelist

    public init(config: Config, whitelist: UserWhitelist = .load()) {
        self.config = config
        self.whitelist = whitelist
    }

    public func scan() -> AsyncThrowingStream<SimilarPhotosEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Fase 1: kumpulkan kandidat dari metadata (murah).
                var candidates: [(url: URL, size: Int64, modified: Date)] = []
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
                        Self.imageExtensions.contains(url.pathExtension.lowercased()),
                        let values = try? url.resourceValues(
                            forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                        ),
                        values.isRegularFile == true,
                        let size = values.fileSize,
                        Int64(size) >= config.minBytes,
                        !whitelist.isExcluded(url),
                        !ProtectedList.isProtected(url, homeDirectory: config.homeDirectory)
                    else { return }
                    candidates.append((
                        url: url,
                        size: Int64(size),
                        modified: values.contentModificationDate ?? .distantPast
                    ))
                    }
                }

                // Fase 2: hitung aHash paralel — decode gambar itu bagian
                // paling mahal (CPU + IO), serial bisa 8× lebih lambat.
                let workerCount = max(2, ProcessInfo.processInfo.activeProcessorCount)
                var items = [Int: PhotoItem]()
                var nextIndex = 0
                var decoded = 0
                await withTaskGroup(of: (Int, PhotoItem?).self) { group in
                    while nextIndex < candidates.count && nextIndex < workerCount {
                        let index = nextIndex
                        group.addTask { (index, Self.hashCandidate(candidates[index])) }
                        nextIndex += 1
                    }
                    while let (index, item) = await group.next() {
                        if let item { items[index] = item }
                        decoded += 1
                        if decoded % 64 == 0 {
                            continuation.yield(.progress(filesScanned: decoded))
                        }
                        if Task.isCancelled { group.cancelAll(); break }
                        if nextIndex < candidates.count {
                            let index2 = nextIndex
                            group.addTask { (index2, Self.hashCandidate(candidates[index2])) }
                            nextIndex += 1
                        }
                    }
                }

                let photos = items.sorted { $0.key < $1.key }.map(\.value)

                var groupCount = 0
                for cluster in Self.cluster(items: photos, hammingThreshold: config.hammingThreshold) {
                    // Suggested keep = file TERBESAR (biasanya kualitas tertinggi).
                    let sorted = cluster.sorted { $0.sizeBytes > $1.sizeBytes }
                    let files = sorted.enumerated().map { index, photo in
                        DuplicateFile(
                            url: photo.url,
                            sizeBytes: photo.sizeBytes,
                            lastModified: photo.lastModified,
                            isSuggestedKeep: index == 0,
                            isSelectedByDefault: index > 0 && RecencyGuard.shouldSelectByDefault(
                                lastModified: photo.lastModified,
                                days: RecencyGuard.defaultDays
                            )
                        )
                    }
                    groupCount += 1
                    continuation.yield(.found(SimilarPhotoGroup(files: files)))
                }

                continuation.yield(.finished(groups: groupCount))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func hashCandidate(
        _ candidate: (url: URL, size: Int64, modified: Date)
    ) -> PhotoItem? {
        guard let hash = averageHash(candidate.url) else { return nil }
        return PhotoItem(
            url: candidate.url,
            sizeBytes: candidate.size,
            lastModified: candidate.modified,
            phash: hash
        )
    }

    // MARK: aHash

    /// Downscale ke 8×8 grayscale via ImageIO (HEIC juga kebaca native),
    /// bandingkan tiap pixel dengan mean → 64 bit.
    static func averageHash(_ url: URL) -> UInt64? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 8,
            // Hormati orientasi EXIF — foto iPhone yang sama dengan tag
            // orientasi beda harus menghasilkan hash yang sama.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: 64)
        let context = CGContext(
            data: &pixels,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        guard let context else { return nil }
        context.interpolationQuality = .medium
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: 8, height: 8))

        let mean = Double(pixels.reduce(0) { $0 + Int($1) }) / 64.0
        var hash: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where Double(pixel) > mean {
            hash |= (1 << UInt64(index))
        }
        return hash
    }

    // MARK: Clustering (pure — diuji unit test)

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Union-find: dua foto satu klaster kalau jarak Hamming-nya ≤ threshold.
    /// O(n²) tapi operasinya cuma XOR+popcount 64-bit — murah.
    static func cluster(items: [PhotoItem], hammingThreshold: Int) -> [[PhotoItem]] {
        var parent = Array(items.indices)
        func find(_ x: Int) -> Int {
            if parent[x] == x { return x }
            parent[x] = find(parent[x])
            return parent[x]
        }

        for i in items.indices {
            for j in (i + 1)..<items.count {
                if hamming(items[i].phash, items[j].phash) <= hammingThreshold {
                    let rootI = find(i)
                    let rootJ = find(j)
                    if rootI != rootJ {
                        parent[rootI] = rootJ
                    }
                }
            }
        }

        var groups: [Int: [PhotoItem]] = [:]
        for index in items.indices {
            groups[find(index), default: []].append(items[index])
        }
        return groups.values.filter { $0.count > 1 }
    }
}
