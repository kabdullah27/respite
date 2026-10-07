import SwiftUI
import RespiteCore
import DesignKit

/// State Copot Aplikasi sebagai model bersama — pengukuran seluruh .app
/// (deep size, bisa belasan detik) dan scan orphan jalan sekali per sesi,
/// hasilnya bertahan saat pindah modul (pola model scan lain).
@MainActor
final class UninstallerModel: ObservableObject {
    static let shared = UninstallerModel()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoadingApps = true

    // Orphan Finder — sisa data aplikasi yang sudah tidak terpasang.
    @Published private(set) var orphans: [OrphanItem] = []
    @Published var selectedOrphans: Set<UUID> = []
    @Published private(set) var isScanningOrphans = false
    @Published private(set) var orphanTotalBytes: Int64 = 0
    @Published var orphanMessage: String?

    private var appsTask: Task<Void, Never>?
    private var orphanTask: Task<Void, Never>?

    /// Streaming: tiap app keukur langsung masuk list (nggak blank saat load).
    /// Sekali per sesi — buka-tutup modul tidak mengukur ulang.
    func loadAppsIfNeeded() {
        guard apps.isEmpty || isLoadingApps else { return }
        guard !(appsTask?.isCancelled == false && isLoadingApps) else { return }
        refreshApps()
    }

    func refreshApps() {
        apps = []
        isLoadingApps = true
        appsTask = Task {
            do {
                for try await event in AppCatalog.scanApps() {
                    if case .found(let app) = event {
                        apps.append(app)
                        apps.sort { $0.sizeBytes > $1.sizeBytes }
                    }
                }
            } catch {
                // Dibatalkan → tampilkan yang udah ada.
            }
            isLoadingApps = false
        }
    }

    /// Buang app yang barusan di-uninstall dari daftar.
    func removeApp(_ url: URL) {
        apps.removeAll { $0.url == url }
    }

    func scanOrphans() {
        isScanningOrphans = true
        orphans = []
        selectedOrphans = []
        orphanTotalBytes = 0
        orphanMessage = nil
        let scanner = OrphanFinder()
        orphanTask = Task {
            var buffer: [OrphanItem] = []
            do {
                for try await event in scanner.scan() {
                    if case .found(let item) = event {
                        buffer.append(item)
                        orphanTotalBytes += item.sizeBytes
                        if buffer.count >= 20 {
                            let chunk = buffer; buffer = []
                            orphans.append(contentsOf: chunk)
                            selectedOrphans.formUnion(chunk.filter(\.isSelectedByDefault).map(\.id))
                        }
                    }
                }
            } catch {
                // Dibatalkan → tampilkan yang sudah terkumpul.
            }
            if !buffer.isEmpty {
                orphans.append(contentsOf: buffer)
                selectedOrphans.formUnion(buffer.filter(\.isSelectedByDefault).map(\.id))
            }
            isScanningOrphans = false
        }
    }

    /// Buang satu item yatim ("Selalu kecualikan" dari context menu).
    func excludeOrphan(_ item: OrphanItem) {
        orphans.removeAll { $0.id == item.id }
        selectedOrphans.remove(item.id)
        orphanTotalBytes -= item.sizeBytes
    }

    func performOrphanClean() {
        let targets = orphans.filter { selectedOrphans.contains($0.id) }
        guard !targets.isEmpty else { return }
        let outcome = CleanExecutor.move(
            targets.map { CleanExecutor.TrashItem(
                url: $0.url, bytes: $0.sizeBytes, label: $0.locationName
            ) },
            module: "Orphan Finder"
        )
        let done = targets.filter { t in
            outcome.cleaned.contains(where: { $0.url == t.url })
        }
        orphanMessage = String(
            format: NSLocalizedString("%d item dipindah ke Trash (%@).", comment: ""),
            done.count,
            ByteFormat.string(from: done.reduce(0) { $0 + $1.sizeBytes })
        )
        let ids = Set(done.map(\.id))
        orphans.removeAll { ids.contains($0.id) }
        selectedOrphans.subtract(ids)
    }
}
