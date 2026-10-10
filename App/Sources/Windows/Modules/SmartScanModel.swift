import SwiftUI
import RespiteCore
import DesignKit

/// State Pindai Cerdas sebagai model bersama — scan TETAP JALAN saat user
/// pindah modul dan hasilnya tetap ada saat kembali (kebijakan yang sama
/// dengan LargeFilesModel; dulu @State di view = hilang saat pindah tab).
@MainActor
final class SmartScanModel: ObservableObject {
    static let shared = SmartScanModel()
    static let dryRunKey = "app.respite.dryRunConfirmed.smartScan"

    struct CategoryProgress {
        enum Status { case pending, running, done }
        var status: Status = .pending
        var count: Int = 0
        var bytes: Int64 = 0
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaned(Int64)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var results: [ScanResult] = []
    @Published var selected: Set<UUID> = []
    @Published private(set) var progress: [ScanCategory: CategoryProgress] = [:]
    @Published private(set) var failureCount = 0
    @Published private(set) var failedItems: [CleanExecutor.FailedItem] = []
    @Published private(set) var isScanning: Bool = false

    private var scanTask: Task<Void, Never>?
    /// Buffer anti render-storm (lihat flushPending).
    private var pendingResults: [ScanResult] = []

    func startScan() {
        results = []
        selected = []
        failureCount = 0
        failedItems = []
        progress = Dictionary(
            uniqueKeysWithValues: ScanCategory.allCases.map { ($0, CategoryProgress()) }
        )
        phase = .scanning
        isScanning = true
        let scanner = SmartScanner()
        scanTask = Task {
            do {
                for try await event in scanner.scan() {
                    handle(event)
                }
            } catch {
                // Dibatalkan user → tampilkan apa yang udah kekumpul.
            }
            for key in progress.keys {
                progress[key]?.status = .done
            }
            flushPending()
            phase = .results
            isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Buang satu hasil (dipakai "Selalu kecualikan" dari context menu).
    func exclude(_ result: ScanResult) {
        pendingResults.removeAll { $0.id == result.id }
        results.removeAll { $0.id == result.id }
        selected.remove(result.id)
    }

    /// Hasil di-buffer — scanner paralel me-yield satu kategori dalam burst;
    /// append @Published per item = render-storm. Flush di tiap
    /// categoryFinished (angkanya authoritative) + sisa di akhir.
    private func flushPending() {
        guard !pendingResults.isEmpty else { return }
        results.append(contentsOf: pendingResults)
        selected.formUnion(
            pendingResults.filter(\.isSelectedByDefault).map(\.id)
        )
        pendingResults = []
    }

    private func handle(_ event: ScanEvent) {
        switch event {
        case .categoryStarted(let category):
            progress[category] = CategoryProgress(status: .running)
        case .found(let result):
            pendingResults.append(result)
        case .categoryFinished(let category, let count, let totalBytes):
            progress[category] = CategoryProgress(status: .done, count: count, bytes: totalBytes)
            flushPending()
        case .finished:
            flushPending()
        }
    }

    func requestClean() -> Bool {
        /// true = langsung bersih; false = view harus tampilkan pratinjau
        /// dry-run dulu (consent pertama).
        if UserDefaults.standard.bool(forKey: Self.dryRunKey) {
            performClean()
            return true
        }
        return false
    }

    func performClean() {
        let chosen = results.filter { selected.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let outcome = CleanExecutor.moveToTrash(chosen)
        failureCount = outcome.failed.count
        failedItems = outcome.failed
        let cleanedURLs = Set(outcome.cleaned.map(\.url))
        results.removeAll { cleanedURLs.contains($0.url) }
        // Pertahankan pilihan user (minus yang sudah bersih) — reset ke
        // default bakal mencentang lagi item yang sengaja di-uncheck.
        selected.formIntersection(results.map(\.id))
        let categoryByURL = Dictionary(
            chosen.map { ($0.url, $0.category) },
            uniquingKeysWith: { first, _ in first }
        )
        for cleaned in outcome.cleaned {
            if let category = categoryByURL[cleaned.url] {
                progress[category]?.count = max(0, (progress[category]?.count ?? 1) - 1)
                progress[category]?.bytes = max(0, (progress[category]?.bytes ?? 0) - cleaned.bytes)
            }
        }
        phase = .cleaned(outcome.freedBytes)
    }
}
