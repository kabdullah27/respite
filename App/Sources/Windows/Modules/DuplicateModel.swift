import SwiftUI
import RespiteCore
import DesignKit

/// State Pencari Duplikat sebagai model bersama — duplikat scan-nya paling
/// lama (hash jutaan byte); pindah modul TIDAK boleh membuang progres.
@MainActor
final class DuplicateModel: ObservableObject {
    static let shared = DuplicateModel()
    static let dryRunKey = "app.respite.dryRunConfirmed.duplicateFinder"

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaned(Int64)
    }

    /// Folder terpilih user — persist antar kunjungan modul.
    @Published var root: URL?
    @Published var minBytes: Int64 = 1_000_000
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published var selected: Set<UUID> = []
    @Published private(set) var scannedCount = 0
    @Published private(set) var failureCount = 0
    @Published private(set) var isScanning = false

    private var scanTask: Task<Void, Never>?

    func startScan() {
        guard let root else { return }
        groups = []
        selected = []
        scannedCount = 0
        failureCount = 0
        phase = .scanning
        isScanning = true
        let scanner = DuplicateScanner(config: .init(root: root, minBytes: minBytes))
        scanTask = Task {
            var buffer: [DuplicateGroup] = []
            do {
                for try await event in scanner.scan() {
                    switch event {
                    case .progress(let filesScanned):
                        scannedCount = filesScanned
                    case .found(let group):
                        buffer.append(group)
                        if buffer.count >= 20 {
                            let chunk = buffer
                            buffer = []
                            groups.append(contentsOf: chunk)
                            selected.formUnion(chunk.flatMap { g in g.files.filter(\.isSelectedByDefault).map(\.id) })
                        }
                    case .finished:
                        break
                    }
                }
            } catch {
                // Dibatalkan → tampilkan yang sudah terkumpul.
            }
            if !buffer.isEmpty {
                groups.append(contentsOf: buffer)
                selected.formUnion(buffer.flatMap { g in g.files.filter(\.isSelectedByDefault).map(\.id) })
            }
            phase = .results
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// true = bersih langsung; false = pratinjau dry-run dulu.
    func requestClean() -> Bool {
        if UserDefaults.standard.bool(forKey: Self.dryRunKey) {
            performClean()
            return true
        }
        return false
    }

    func performClean() {
        var chosen: [CleanExecutor.TrashItem] = []
        for group in groups {
            // Minimal satu salinan per grup WAJIB tersisa. Kalau semua
            // dicentang, yang disarankan disimpan (atau yang pertama) dilewati.
            let keepID = group.files.allSatisfy({ selected.contains($0.id) })
                ? (group.files.first(where: \.isSuggestedKeep) ?? group.files.first)?.id
                : nil
            for file in group.files where selected.contains(file.id) && file.id != keepID {
                chosen.append(CleanExecutor.TrashItem(
                    url: file.url,
                    bytes: file.sizeBytes,
                    label: file.url.lastPathComponent
                ))
            }
        }
        guard !chosen.isEmpty else { return }
        let outcome = CleanExecutor.move(chosen, module: "Duplicate Finder")
        failureCount = outcome.failed.count
        let deletedIDs = Set(outcome.cleaned.map(\.url))
        groups = groups.compactMap { group in
            let remaining = group.files.filter { !deletedIDs.contains($0.url) }
            if remaining.count < 2 { return nil }
            return DuplicateGroup(sizeBytes: group.sizeBytes, files: remaining)
        }
        // Pertahankan pilihan user (minus yang sudah bersih) — reset ke
        // default bakal mencentang lagi item yang sengaja di-uncheck.
        selected.formIntersection(groups.flatMap { $0.files.map(\.id) })
        phase = .cleaned(outcome.freedBytes)
    }
}
