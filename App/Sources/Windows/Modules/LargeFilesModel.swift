import Foundation
import RespiteCore

/// State scan Large Files hidup di model bersama — BUKAN @State view —
/// biar pindah modul tidak mematikan scan (state view ke-destroy saat
/// `switch module` berganti, task unstructured tetap jalan di background).
/// Dashboard menampilkan banner + tombol stop selama scan berjalan.
@MainActor
final class LargeFilesModel: ObservableObject {
    static let shared = LargeFilesModel()

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaned(Int64)
    }

    static let thresholdKey = "app.respite.largeFilesMinBytes"

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hits: [FileHit] = []
    @Published private(set) var selected: Set<UUID> = []
    @Published private(set) var failureCount = 0
    @Published private(set) var failedItems: [CleanExecutor.FailedItem] = []
    @Published var minBytes: Int64

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool { phase == .scanning }

    var scannedBytes: Int64 {
        hits.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedBytes: Int64 {
        hits.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.thresholdKey) as? Int64
        self.minBytes = stored ?? 250 * 1_000_000
    }

    func startScan() {
        hits = []
        selected = []
        failureCount = 0
        failedItems = []
        UserDefaults.standard.set(minBytes, forKey: Self.thresholdKey)
        phase = .scanning
        let scanner = LargeFilesScanner(config: .init(
            root: FileManager.default.homeDirectoryForCurrentUser,
            minBytes: minBytes
        ))
        scanTask = Task { [weak self] in
            // Batching: flush ke @Published maksimal tiap 120 item / 400 ms
            // — append per-item bikin render storm (penyebab RAM bengkak).
            var buffer: [FileHit] = []
            var lastFlush = Date()
            func takeChunk() -> [FileHit]? {
                guard !buffer.isEmpty else { return nil }
                let chunk = buffer
                buffer.removeAll(keepingCapacity: true)
                lastFlush = Date()
                return chunk
            }
            do {
                for try await event in scanner.scan() {
                    if case .found(let hit) = event {
                        buffer.append(hit)
                        if buffer.count >= 120 || Date().timeIntervalSince(lastFlush) >= 0.4 {
                            if let chunk = takeChunk() { self?.appendChunk(chunk) }
                        }
                    }
                }
            } catch {
                // Dibatalkan → hasil yang sudah terkumpul tetap ditampilkan.
            }
            if let chunk = takeChunk() { self?.appendChunk(chunk) }
            self?.phase = .results
        }
    }

    private func appendChunk(_ chunk: [FileHit]) {
        hits.append(contentsOf: chunk)
        selected.formUnion(chunk.filter(\.isSelectedByDefault).map(\.id))
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Buang satu hasil dari daftar (dipakai "Selalu kecualikan").
    func remove(_ id: UUID) {
        hits.removeAll { $0.id == id }
        selected.remove(id)
    }

    func toggle(_ id: UUID, isOn: Bool) {
        if isOn {
            selected.insert(id)
        } else {
            selected.remove(id)
        }
    }

    func performClean(dryRunKey: String) {
        let chosen = hits.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let outcome = CleanExecutor.move(
            chosen.map {
                CleanExecutor.TrashItem(url: $0.url, bytes: $0.sizeBytes, label: $0.url.lastPathComponent)
            },
            module: "Large Files"
        )
        failureCount = outcome.failed.count
        failedItems = outcome.failed
        let cleanedURLs = Set(outcome.cleaned.map(\.url))
        hits.removeAll { cleanedURLs.contains($0.url) }
        selected = Set(hits.filter(\.isSelectedByDefault).map(\.id))
        UserDefaults.standard.set(true, forKey: dryRunKey)
        phase = .cleaned(outcome.freedBytes)
    }
}
