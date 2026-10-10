import SwiftUI
import RespiteCore
import DesignKit

/// State Sisa Pengembang sebagai model bersama — scan lanjut di background
/// saat user pindah modul, hasil + pilihan folder node_modules tetap ada
/// saat kembali (pola LargeFilesModel/SmartScanModel).
@MainActor
final class DevCacheModel: ObservableObject {
    static let shared = DevCacheModel()
    static let dryRunKey = "app.respite.dryRunConfirmed.devCache"

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaned(Int64)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var tools: [DevTools.Tool] = []
    @Published private(set) var targets: [DevCacheTarget] = []
    @Published var selected: Set<UUID> = []
    /// Folder project pilihan user buat pencarian node_modules — persist.
    @Published var nodeRoots: [URL] = []
    @Published private(set) var failureCount = 0
    @Published private(set) var failedItems: [CleanExecutor.FailedItem] = []
    @Published private(set) var isScanning = false

    private var scanTask: Task<Void, Never>?

    func detectToolsIfNeeded() {
        guard tools.isEmpty else { return }
        tools = DevTools.detect()
    }

    func startScan() {
        targets = []
        selected = []
        failureCount = 0
        failedItems = []
        phase = .scanning
        isScanning = true
        let scanner = DevCacheScanner(roots: .standard(nodeRoots: nodeRoots))
        scanTask = Task {
            do {
                var buffer: [DevCacheTarget] = []
                for try await event in scanner.scan() {
                    if case .found(let target) = event {
                        buffer.append(target)
                        // Flush per 20 — anti render-storm (pola Large Files).
                        if buffer.count >= 20 {
                            targets.append(contentsOf: buffer)
                            selected.formUnion(buffer.filter(\.isSelectedByDefault).map(\.id))
                            buffer = []
                        }
                    }
                }
                if !buffer.isEmpty {
                    targets.append(contentsOf: buffer)
                    selected.formUnion(buffer.filter(\.isSelectedByDefault).map(\.id))
                }
            } catch {
                // Dibatalkan → tampilkan yang sudah terkumpul.
            }
            phase = .results
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func addNodeRoots(_ urls: [URL]) {
        // Folder sama / bersarang di root yang sudah ada → target dobel
        // (UUID beda, dua-duanya tercentang, pindah kedua pasti gagal).
        func covers(_ root: URL, _ url: URL) -> Bool {
            let r = root.standardizedFileURL.path, u = url.standardizedFileURL.path
            return u == r || u.hasPrefix(r + "/")
        }
        for url in urls where !nodeRoots.contains(where: { covers($0, url) }) {
            nodeRoots.removeAll { covers(url, $0) }
            nodeRoots.append(url)
        }
        if phase != .scanning { startScan() }
    }

    /// Buang satu target ("Selalu kecualikan" dari context menu).
    func exclude(_ target: DevCacheTarget) {
        targets.removeAll { $0.id == target.id }
        selected.remove(target.id)
    }

    /// true = bersih langsung; false = tampilkan pratinjau dry-run dulu.
    func requestClean() -> Bool {
        if UserDefaults.standard.bool(forKey: Self.dryRunKey) {
            performClean()
            return true
        }
        return false
    }

    func performClean() {
        let chosen = targets.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let outcome = CleanExecutor.move(
            chosen.map {
                CleanExecutor.TrashItem(url: $0.url, bytes: $0.sizeBytes, label: $0.title)
            },
            module: "Developer Cache"
        )
        failureCount = outcome.failed.count
        failedItems = outcome.failed
        let cleanedURLs = Set(outcome.cleaned.map(\.url))
        targets.removeAll { cleanedURLs.contains($0.url) }
        // Pertahankan pilihan user (minus yang sudah bersih) — reset ke
        // default bakal mencentang lagi item yang sengaja di-uncheck.
        selected.formIntersection(targets.map(\.id))
        phase = .cleaned(outcome.freedBytes)
    }
}
