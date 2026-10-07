import SwiftUI
import RespiteCore
import DesignKit

/// State Foto Mirip sebagai model bersama — decode ribuan foto itu paling
/// lambat; pindah modul tidak boleh membuang progres (pola model lain).
@MainActor
final class SimilarPhotosModel: ObservableObject {
    static let shared = SimilarPhotosModel()
    static let dryRunKey = "app.respite.dryRunConfirmed.similarPhotos"

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaned(Int64)
    }

    @Published var root: URL?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var groups: [SimilarPhotoGroup] = []
    @Published var selected: Set<UUID> = []
    @Published private(set) var scannedCount = 0
    @Published private(set) var isScanning = false

    private var scanTask: Task<Void, Never>?

    func startScan() {
        guard let root else { return }
        groups = []
        selected = []
        scannedCount = 0
        phase = .scanning
        isScanning = true
        let scanner = SimilarPhotosScanner(config: .init(root: root))
        scanTask = Task {
            var buffer: [SimilarPhotoGroup] = []
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
            for file in group.files where selected.contains(file.id) {
                chosen.append(CleanExecutor.TrashItem(
                    url: file.url,
                    bytes: file.sizeBytes,
                    label: file.url.lastPathComponent
                ))
            }
        }
        guard !chosen.isEmpty else { return }
        let outcome = CleanExecutor.move(chosen, module: "Similar Photos")
        let deletedURLs = Set(outcome.cleaned.map(\.url))
        groups = groups.compactMap { group in
            let remaining = group.files.filter { !deletedURLs.contains($0.url) }
            if remaining.count < 2 { return nil }
            return SimilarPhotoGroup(files: remaining)
        }
        selected = []
        for group in groups {
            selected.formUnion(group.files.filter(\.isSelectedByDefault).map(\.id))
        }
        phase = .cleaned(outcome.freedBytes)
    }
}
