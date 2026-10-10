import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Copot Aplikasi: pilih app → cari file sisanya (cocok ID aplikasi =
/// tercentang, cocok nama = "Mungkin milik" tidak tercentang) → semuanya
/// dipindah ke Trash. Di bawahnya: sisa dari aplikasi yang sudah dihapus.
/// Pola halaman mengikuti ToolPage (mulai → mencari → hasil → selesai).
struct AppUninstallerView: View {
    private static let dryRunKey = "app.respite.dryRunConfirmed.appUninstaller"

    @ObservedObject private var model = UninstallerModel.shared
    @State private var search = ""

    @State private var selectedApp: InstalledApp?
    @State private var isLoadingLeftovers = false
    @State private var leftovers: [LeftoverItem] = []
    @State private var selectedLeftovers: Set<UUID> = []
    @State private var leftoverTask: Task<Void, Never>?

    @State private var cleanedMessage: String?
    @State private var failureCount = 0
    @State private var showConfirm = false

    @State private var showOrphanConfirm = false
    /// Membedakan "belum pernah dipindai" dari "dipindai, hasilnya kosong".
    @State private var orphanScanStarted = false

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return model.apps }
        return model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    @State private var orphanSearch = ""
    @State private var orphanSort: OrphanSort = .largest

    enum OrphanSort: String, CaseIterable, Identifiable {
        case largest, oldest, name
        var id: String { rawValue }

        var label: String {
            switch self {
            case .largest: return NSLocalizedString("Terbesar dulu", comment: "")
            case .oldest: return NSLocalizedString("Terlama dulu", comment: "")
            case .name: return NSLocalizedString("Nama (A–Z)", comment: "")
            }
        }
    }

    /// Orphan yang lolos pencarian + urutan terpilih.
    private var visibleOrphans: [OrphanItem] {
        let query = orphanSearch.trimmingCharacters(in: .whitespaces)
        let base = query.isEmpty
            ? model.orphans
            : model.orphans.filter { $0.url.path.localizedCaseInsensitiveContains(query) }
        switch orphanSort {
        case .largest: return base.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest: return base.sorted { $0.lastModified < $1.lastModified }
        case .name: return base.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        }
    }

    private var selectedTotalBytes: Int64 {
        guard let app = selectedApp else { return 0 }
        let leftoverBytes = leftovers
            .filter { selectedLeftovers.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
        return app.sizeBytes + leftoverBytes
    }

    private var selectedLeftoverCount: Int {
        leftovers.filter { selectedLeftovers.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            if let app = selectedApp {
                detailSection(app)
            } else {
                if let cleanedMessage {
                    resultBanner(cleanedMessage, isFailure: false)
                }
                appList
                Divider().padding(.vertical, DKSpacing.sm)
                orphanSection
            }
        }
        .task {
            model.loadAppsIfNeeded()
        }
        .alert(
            ToolConfirm.title(count: 1 + selectedLeftoverCount, bytes: selectedTotalBytes),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Hapus Aplikasi", comment: "")) {
                UserDefaults.standard.set(true, forKey: Self.dryRunKey)
                performUninstall()
            }
        } message: {
            Text(String(
                format: NSLocalizedString("%@ dan %d file sisanya akan dipindahkan ke Trash.", comment: ""),
                selectedApp?.name ?? "",
                selectedLeftoverCount
            ) + " " + ToolConfirm.message)
        }
        .alert(
            ToolConfirm.title(count: model.selectedOrphans.count, bytes: selectedOrphanBytes),
            isPresented: $showOrphanConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                // Paritas pola uninstaller: konfirmasi eksplisit = consent
                // pertama, dicatat ke gate modul ini. (Key-nya masih
                // "app.respite.dryRun.orphanFinder" — data consent user yang
                // sudah ada jangan dibuang.)
                UserDefaults.standard.set(true, forKey: "app.respite.dryRun.orphanFinder")
                model.performOrphanClean()
            }
        } message: {
            Text(ToolConfirm.message)
        }
    }

    // MARK: Daftar aplikasi

    @ViewBuilder
    private var appList: some View {
        if model.isLoadingApps && model.apps.isEmpty {
            ToolProgressCard(
                title: NSLocalizedString("Memuat aplikasi…", comment: ""),
                detail: NSLocalizedString("Sedang menghitung ukuran tiap aplikasi.", comment: "")
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d aplikasi terpasang", comment: ""),
                    model.apps.count
                ),
                subtitle: NSLocalizedString("Klik aplikasi yang ingin kamu hapus. File sisanya akan dicarikan sekalian.", comment: "")
            ) {
                HStack(spacing: DKSpacing.md) {
                    TextField(NSLocalizedString("Cari aplikasi…", comment: ""), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    if model.isLoadingApps {
                        ProgressView().controlSize(.small)
                        Text(String(
                            format: NSLocalizedString("Memuat… %d aplikasi", comment: ""),
                            model.apps.count
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }

            if !model.isLoadingApps && filteredApps.isEmpty {
                Text(NSLocalizedString("Tidak ada aplikasi yang cocok.", comment: ""))
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                List(filteredApps) { app in
                    appRow(app)
                }
                .listStyle(.inset)
                .frame(height: 360)
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: DKSpacing.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            Text(app.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: DKSpacing.sm)
            Text(ByteFormat.string(from: app.sizeBytes))
                .font(.dkData(12))
                .foregroundColor(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { select(app) }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
            }
        }
    }

    // MARK: Sisa dari aplikasi yang sudah dihapus

    @ViewBuilder
    private var orphanSection: some View {
        if model.isScanningOrphans {
            ToolProgressCard(
                title: NSLocalizedString("Mencari sisa aplikasi lama…", comment: ""),
                detail: String(
                    format: NSLocalizedString("%d item ditemukan · %@", comment: ""),
                    model.orphans.count,
                    ByteFormat.string(from: model.orphanTotalBytes)
                )
            )
        } else if model.orphans.isEmpty && model.orphanMessage == nil && !orphanScanStarted {
            ToolStartCard(
                headline: NSLocalizedString("Sisa dari aplikasi yang sudah dihapus", comment: ""),
                points: [
                    NSLocalizedString("Mencari file yang ditinggalkan aplikasi yang sudah tidak ada di Mac kamu.", comment: ""),
                    NSLocalizedString("Yang tidak yakin milik siapa tidak dicentang otomatis.", comment: ""),
                    NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
                ],
                action: startOrphanScan
            )
        } else {
            if let orphanMessage = model.orphanMessage {
                ToolDoneCard(title: orphanMessage, onRescan: startOrphanScan)
            }
            if model.orphans.isEmpty {
                if model.orphanMessage == nil {
                    ToolEmptyResult(
                        message: NSLocalizedString("Tidak ada sisa dari aplikasi yang sudah dihapus.", comment: ""),
                        onRescan: startOrphanScan
                    )
                }
            } else {
                orphanResults
            }
        }
    }

    @ViewBuilder
    private var orphanResults: some View {
        ToolResultHeader(
            title: String(
                format: NSLocalizedString("Sisa aplikasi lama · %@", comment: ""),
                ByteFormat.string(from: model.orphanTotalBytes)
            ),
            subtitle: NSLocalizedString("File ini milik aplikasi yang sudah tidak terpasang. Kalau ragu, biarkan tidak dicentang.", comment: ""),
            onRescan: startOrphanScan
        ) {
            HStack(spacing: DKSpacing.md) {
                Picker("", selection: $orphanSort) {
                    ForEach(OrphanSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .labelsHidden()
                .fixedSize()
                TextField(NSLocalizedString("Cari nama atau folder…", comment: ""), text: $orphanSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
            }
        }

        List(visibleOrphans) { item in
            ToolResultRow(
                title: item.url.lastPathComponent,
                subtitle: String(
                    format: NSLocalizedString("%@ · terakhir diubah %@", comment: ""),
                    item.locationName,
                    FriendlyDate.string(item.lastModified)
                ),
                size: item.sizeBytes,
                isOn: Binding(
                    get: { model.selectedOrphans.contains(item.id) },
                    set: { on in
                        if on { model.selectedOrphans.insert(item.id) }
                        else { model.selectedOrphans.remove(item.id) }
                    }
                )
            )
            .help(item.url.path)
            .onTapGesture(count: 2) {
                QuickLookCoordinator.shared.show(item.url)
            }
            .contextMenu {
                Button {
                    QuickLookCoordinator.shared.show(item.url)
                } label: {
                    Label(NSLocalizedString("Lihat isi", comment: ""), systemImage: "eye")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
                }
                Divider()
                Button {
                    whitelistAndExclude(item)
                } label: {
                    Label(NSLocalizedString("Jangan tampilkan folder ini lagi", comment: ""), systemImage: "hand.raised")
                }
            }
        }
        .listStyle(.inset)
        .frame(height: 300)

        ToolActionBar(
            selectedCount: model.selectedOrphans.count,
            selectedBytes: selectedOrphanBytes,
            action: { showOrphanConfirm = true }
        )
    }

    private func startOrphanScan() {
        orphanScanStarted = true
        model.scanOrphans()
    }

    private var selectedOrphanBytes: Int64 {
        model.orphans
            .filter { model.selectedOrphans.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    /// Whitelist permanen + buang dari hasil (context menu sisa aplikasi lama).
    private func whitelistAndExclude(_ item: OrphanItem) {
        var whitelist = UserWhitelist.load()
        whitelist.add(item.url.path)
        whitelist.save()
        model.excludeOrphan(item)
    }

    // MARK: Detail app terpilih

    @ViewBuilder
    private func detailSection(_ app: InstalledApp) -> some View {
        Button {
            leftoverTask?.cancel()
            selectedApp = nil
            leftovers = []
            selectedLeftovers = []
        } label: {
            Label(NSLocalizedString("Kembali ke daftar", comment: ""), systemImage: "chevron.left")
        }

        HStack(spacing: DKSpacing.md) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(app.name).font(.title2.weight(.semibold))
            Spacer()
        }

        if let cleanedMessage {
            resultBanner(cleanedMessage, isFailure: true)
        }

        if isLoadingLeftovers {
            ToolProgressCard(
                title: NSLocalizedString("Mencari file sisa…", comment: ""),
                detail: NSLocalizedString("Biasanya hanya beberapa detik.", comment: "")
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("Aplikasi ini + %d file sisa · %@", comment: ""),
                    leftovers.count,
                    ByteFormat.string(from: app.sizeBytes + leftovers.reduce(0) { $0 + $1.sizeBytes })
                ),
                subtitle: leftovers.isEmpty
                    ? NSLocalizedString("Tidak ada file sisa — hanya aplikasinya yang akan dihapus.", comment: "")
                    : NSLocalizedString("Aplikasinya selalu ikut dihapus. Centang file sisa yang mau ikut dibuang.", comment: "")
            )

            List {
                HStack(spacing: DKSpacing.md) {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.callout.weight(.medium))
                        Text(NSLocalizedString("Aplikasinya — selalu ikut dihapus", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: DKSpacing.sm)
                    Text(ByteFormat.string(from: app.sizeBytes))
                        .font(.dkData(12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)

                ForEach(leftovers) { item in
                    ToolResultRow(
                        title: item.url.lastPathComponent,
                        subtitle: confidenceLabel(item.confidence),
                        size: item.sizeBytes,
                        badge: item.confidence == .fuzzy
                            ? NSLocalizedString("Periksa dulu", comment: "")
                            : nil,
                        isOn: Binding(
                            get: { selectedLeftovers.contains(item.id) },
                            set: { isChecked in
                                if isChecked {
                                    selectedLeftovers.insert(item.id)
                                } else {
                                    selectedLeftovers.remove(item.id)
                                }
                            }
                        )
                    )
                    .help(item.url.path)
                    .contextMenu {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: min(300, CGFloat(leftovers.count + 1) * 48 + 16))

            ToolDetails {
                Text(String(
                    format: NSLocalizedString("ID aplikasi (bundle ID): %@", comment: ""),
                    app.bundleID ?? "—"
                ))
                Text(String(format: NSLocalizedString("Lokasi: %@", comment: ""), app.url.path))
                Text(NSLocalizedString("\"Pasti milik aplikasi ini\" = nama filenya cocok persis dengan ID aplikasi. \"Mungkin milik aplikasi ini\" = hanya cocok dari nama aplikasi, jadi periksa dulu sebelum ikut dihapus.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Uninstall selalu lewat konfirmasi eksplisit — tier risiko lebih
        // tinggi dari clean cache (guardrails poin 5).
        ToolActionBar(
            selectedCount: 1 + selectedLeftoverCount,
            selectedBytes: selectedTotalBytes,
            buttonTitle: NSLocalizedString("Hapus Aplikasi", comment: ""),
            action: { showConfirm = true }
        )
    }

    private func confidenceLabel(_ confidence: LeftoverItem.Confidence) -> String {
        switch confidence {
        case .exact: return NSLocalizedString("Pasti milik aplikasi ini", comment: "")
        case .fuzzy: return NSLocalizedString("Mungkin milik aplikasi ini", comment: "")
        }
    }

    // MARK: Aksi

    private func select(_ app: InstalledApp) {
        leftoverTask?.cancel()
        selectedApp = app
        leftovers = []
        selectedLeftovers = []
        cleanedMessage = nil
        failureCount = 0
        isLoadingLeftovers = true
        leftoverTask = Task {
            let found = await Task.detached(priority: .userInitiated) { [app] in
                LeftoverScanner.leftovers(for: app)
            }.value
            // Scan lama yang selesai belakangan JANGAN menimpa daftar app
            // yang sekarang dipilih — bisa bikin data app A ikut terhapus
            // saat uninstall app B.
            guard !Task.isCancelled, selectedApp?.id == app.id else { return }
            leftovers = found
            selectedLeftovers = Set(found.filter(\.isSelectedByDefault).map(\.id))
            isLoadingLeftovers = false
        }
    }

    private func performUninstall() {
        guard let app = selectedApp else { return }
        var items: [CleanExecutor.TrashItem] = [
            CleanExecutor.TrashItem(url: app.url, bytes: app.sizeBytes, label: app.name)
        ]
        items += leftovers
            .filter { selectedLeftovers.contains($0.id) }
            .map { CleanExecutor.TrashItem(url: $0.url, bytes: $0.sizeBytes, label: $0.url.lastPathComponent) }

        let outcome = CleanExecutor.move(items, module: "App Uninstaller")
        let movedURLs = Set(outcome.cleaned.map(\.url))
        failureCount = items.count - outcome.cleaned.count
        guard movedURLs.contains(app.url) else {
            // .app gagal dipindah (milik root / terlindungi) — tetap di detail,
            // jangan klaim berhasil. Sisa yang sudah terpindah dibuang dari list.
            cleanedMessage = String(
                format: NSLocalizedString("%@ tidak bisa dihapus", comment: ""),
                app.name
            )
            leftovers.removeAll { movedURLs.contains($0.url) }
            selectedLeftovers = selectedLeftovers.filter { id in leftovers.contains { $0.id == id } }
            return
        }
        cleanedMessage = String(
            format: NSLocalizedString("%@ sudah dipindahkan ke Trash", comment: ""),
            app.name
        )
        selectedApp = nil
        leftovers = []
        selectedLeftovers = []
        // Buang dari daftar — tanpa rescan penuh (deep size semua app).
        model.removeApp(app.url)
    }

    /// Banner hasil uninstall. Di daftar = berhasil; di detail = .app gagal
    /// dipindah (performUninstall hanya tetap di detail saat gagal).
    private func resultBanner(_ message: String, isFailure: Bool) -> some View {
        ToolCard {
            HStack(alignment: .top, spacing: DKSpacing.md) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isFailure ? DKColor.attention : Color.respite)
                VStack(alignment: .leading, spacing: DKSpacing.xs) {
                    Text(message)
                        .font(.title3.weight(.semibold))
                    Text(isFailure
                         ? NSLocalizedString("Aplikasi ini mungkin dilindungi sistem atau sedang dibuka. Tutup aplikasinya lalu coba lagi.", comment: "")
                         : NSLocalizedString("File ada di Trash. Berubah pikiran? Buka Trash lalu pilih \"Kembalikan\".", comment: "")
                    )
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if failureCount > 0 {
                        Text(String(
                            format: NSLocalizedString("%d item gagal dibersihkan", comment: ""),
                            failureCount
                        ))
                        .font(.caption)
                        .foregroundColor(DKColor.attention)
                    }
                }
                Spacer()
            }
        }
    }
}
