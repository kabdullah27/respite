import Foundation
import ObjectiveC

/// Target path Smart Scan — injectable biar unit test bisa pakai fixture
/// di temp directory (TRD §8), produksi pakai path standard.
public struct ScanTargets: Sendable {
    public var userCaches: URL?
    public var userLogs: URL?
    public var trash: URL?

    public init(userCaches: URL?, userLogs: URL?, trash: URL?) {
        self.userCaches = userCaches
        self.userLogs = userLogs
        self.trash = trash
    }

    public static var standard: ScanTargets {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScanTargets(
            userCaches: home.appendingPathComponent("Library/Caches"),
            userLogs: home.appendingPathComponent("Library/Logs"),
            trash: home.appendingPathComponent(".Trash")
        )
    }

    var roots: [(category: ScanCategory, root: URL)] {
        [
            (category: .userCaches, root: userCaches),
            (category: .userLogs, root: userLogs),
            (category: .trash, root: trash),
        ]
        .compactMap { category, root in root.map { (category, $0) } }
    }
}

/// Smart Scan (TRD §4.1): enumerasi per kategori, hasil di-level owner folder.
/// Memory tetap datar: file tree NGGAK disimpan — tiap folder owner cuma
/// nyimpen akumulasi angka (size + tanggal terbaru), dibuang setelah batch
/// di-yield (PRD §5 backpressure).
public struct SmartScanner: ScannableModule {
    public let targets: ScanTargets
    public let whitelist: UserWhitelist

    public init(
        targets: ScanTargets = .standard,
        whitelist: UserWhitelist = .load()
    ) {
        self.targets = targets
        self.whitelist = whitelist
    }

    public func scan() -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var grandCount = 0
                var grandBytes: Int64 = 0
                for (category, root) in targets.roots {
                    continuation.yield(.categoryStarted(category))
                    // Ukur owner folder PARALEL (deep enumeration tiap folder
                    // = IO-bound) tapi yield-nya seurutan anak top-level —
                    // hasil deterministik, tes & UI nggak kena race order.
                    let children = eligibleChildren(of: root)
                    let measured = await Self.measureInParallel(children) { child in
                        measure(child, category: category)
                    }
                    var count = 0
                    var bytes: Int64 = 0
                    for result in measured {
                        if Task.isCancelled { break }
                        guard let result else { continue }
                        count += 1
                        bytes += result.sizeBytes
                        grandCount += 1
                        grandBytes += result.sizeBytes
                        continuation.yield(.found(result))
                    }
                    continuation.yield(.categoryFinished(category, count: count, totalBytes: bytes))
                    if Task.isCancelled { break }
                }
                continuation.yield(.finished(ScanSummary(resultCount: grandCount, totalBytes: grandBytes)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Bounded parallel pool di atas measure() — index dipertahankan biar
    /// urutan hasil = urutan input walau selesai kapan pun.
    private static func measureInParallel(
        _ children: [URL],
        measure: @escaping @Sendable (URL) -> ScanResult?
    ) async -> [ScanResult?] {
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount)
        var results = [Int: ScanResult?]()
        var nextIndex = 0
        await withTaskGroup(of: (Int, ScanResult?).self) { group in
            while nextIndex < children.count && nextIndex < workers {
                let index = nextIndex
                group.addTask { (index, measure(children[index])) }
                nextIndex += 1
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if nextIndex < children.count {
                    let index2 = nextIndex
                    group.addTask { (index2, measure(children[index2])) }
                    nextIndex += 1
                }
            }
        }
        return (0..<children.count).map { results[$0] ?? nil }
    }

    /// Anak top-level root kategori yang lolos whitelist + Protected List.
    private func eligibleChildren(of root: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }
        return children.filter { !whitelist.isExcluded($0) && !ProtectedList.isProtected($0) }
    }

    /// Ukur satu folder owner → hasil scan (nil kalau kosong/gagal).
    /// Cache/log/trash selalu direkomendasikan (PRD: Recency Guard nggak
    /// berlaku buat Smart Scan — "baru dipakai" bukan alasan nahan cache).
    private func measure(_ child: URL, category: ScanCategory) -> ScanResult? {
        let (size, latest) = deepSizeAndLatestModified(child)
        guard size > 0 else { return nil }
        return ScanResult(
            url: child,
            category: category,
            ownerName: child.lastPathComponent,
            sizeBytes: size,
            lastModified: latest,
            isSelectedByDefault: true
        )
    }

    /// Akumulasi size + tanggal modifikasi terbaru dari satu folder deep —
    /// enumerasi streaming, cek cancel tiap 128 file biar responsif di-interupt.
    private func deepSizeAndLatestModified(_ folder: URL) -> (Int64, Date) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else {
            let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (0, date)
        }

        var size: Int64 = 0
        var latest = Date.distantPast
        var seen = 0
        while let item = enumerator.nextObject() {
            // Pool per item — jangan tumpuk objek bridge ObjC (lihat LargeFilesScanner).
            let step: (Int64, Date) = autoreleasepool {
                guard let url = item as? URL else { return (size, latest) }
                guard
                    let values = try? url.resourceValues(
                        forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                    ),
                    values.isRegularFile == true
                else { return (size, latest) }
                var stepSize = size
                var stepLatest = latest
                stepSize += Int64(values.fileSize ?? 0)
                if let date = values.contentModificationDate, date > stepLatest {
                    stepLatest = date
                }
                return (stepSize, stepLatest)
            }
            size = step.0
            latest = step.1
            seen += 1
            if seen % 128 == 0, Task.isCancelled { return (size, latest) }
        }
        return (size, latest)
    }
}
