import SwiftUI
import RespiteCore
import DesignKit

/// State Pembersih Peramban sebagai model bersama — deep-size cache browser
/// bisa GB-an dan detik-detik lamanya; hasil scan bertahan saat pindah
/// modul dan TIDAK di-scan ulang tiap kali view dibuka lagi (pola model lain).
@MainActor
final class BrowserCleanerModel: ObservableObject {
    static let shared = BrowserCleanerModel()
    static let dryRunKey = "app.respite.dryRunConfirmed.browserCleaner"

    @Published private(set) var results: [BrowserScanResult] = []
    @Published var selected: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var cleanedBytes: Int64?
    @Published private(set) var failureCount = 0

    private var loadTask: Task<Void, Never>?

    /// Browser yang sedang jalan — datanya butuh NSWorkspace (AppKit).
    var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Scan sekali per sesi — buka-tutup modul tidak memicu ulang.
    func loadIfNeeded() {
        guard results.isEmpty, !isLoading else { return }
        rescan()
    }

    func rescan() {
        guard !isLoading else { return }
        isLoading = true
        loadTask = Task {
            // Paralel per browser — deep size cache Chromium bisa GB-an.
            let scanned = await BrowserCacheScanner.scanAsync()
            let running = runningBundleIDs
            var defaults: Set<String> = []
            for result in scanned where !running.contains(result.bundleID) && result.totalCacheBytes > 0 {
                // Default hanya CACHE — riwayat & cookie lebih sensitif.
                defaults.insert("\(result.bundleID)|cache")
            }
            results = scanned
            selected = defaults
            isLoading = false
        }
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
        var items: [CleanExecutor.TrashItem] = []
        let running = runningBundleIDs
        for result in results where !running.contains(result.bundleID) {
            for type in BrowserDataType.allCases {
                guard selected.contains("\(result.bundleID)|\(type.rawValue)") else { continue }
                for url in result.urls(for: type) {
                    items.append(CleanExecutor.TrashItem(
                        url: url,
                        bytes: FileTreeSizer.size(of: url),
                        label: "\(result.name) \(type.rawValue)"
                    ))
                }
            }
        }
        guard !items.isEmpty else { return }
        let outcome = CleanExecutor.move(items, module: "Browser Cleaner")
        failureCount = outcome.failed.count
        cleanedBytes = outcome.freedBytes
        rescan()
    }
}
