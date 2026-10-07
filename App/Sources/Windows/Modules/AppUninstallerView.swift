import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// App Uninstaller (TRD §4.2): pilih app → deteksi sisa data (bundle ID =
/// exact tercentang, nama = "Perkiraan" nggak tercentang) → uninstall =
/// pindah semuanya ke Trash.
struct AppUninstallerView: View {
    private static let dryRunKey = "app.respite.dryRunConfirmed.appUninstaller"

    @ObservedObject private var model = UninstallerModel.shared
    @State private var search = ""

    @State private var selectedApp: InstalledApp?
    @State private var isLoadingLeftovers = false
    @State private var leftovers: [LeftoverItem] = []
    @State private var selectedLeftovers: Set<UUID> = []

    @State private var cleanedMessage: String?
    @State private var failureCount = 0
    @State private var showConfirm = false

    @State private var showOrphanConfirm = false

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
            case .largest: return NSLocalizedString("Terbesar", comment: "")
            case .oldest: return NSLocalizedString("Terlama", comment: "")
            case .name: return NSLocalizedString("Nama", comment: "")
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

    var body: some View {
        VStack(spacing: 0) {
            if let app = selectedApp {
                detailSection(app)
            } else {
                List {
                    listContent
                    orphanSection
                }
                .listStyle(.inset)
            }
        }
        .frame(minHeight: 420)
        .task {
            model.loadAppsIfNeeded()
        }
        .alert(
            NSLocalizedString("Konfirmasi uninstall", comment: ""),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: ""), role: .destructive) {
                UserDefaults.standard.set(true, forKey: Self.dryRunKey)
                performUninstall()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "%@ beserta %d item sisa data (%@) akan dipindah ke Trash — bisa dikembalikan dari sana.",
                    comment: ""
                ),
                selectedApp?.name ?? "",
                leftovers.filter { selectedLeftovers.contains($0.id) }.count,
                ByteFormat.string(from: selectedTotalBytes)
            ))
        }
        .alert(
            NSLocalizedString("Pindahkan sisa data ke Trash?", comment: ""),
            isPresented: $showOrphanConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: ""), role: .destructive) {
                // Paritas pola uninstaller: konfirmasi eksplisit = consent
                // pertama, dicatat ke dry-run gate modul ini. (Key-nya masih
                // "app.respite.dryRun.orphanFinder" — data consent user yang
                // sudah ada jangan dibuang.)
                UserDefaults.standard.set(true, forKey: "app.respite.dryRun.orphanFinder")
                model.performOrphanClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "%d item (%@) akan dipindah ke Trash. Respite hanya menghapus yang tercentang — bisa dikembalikan dari Trash.",
                    comment: ""
                ),
                model.selectedOrphans.count,
                ByteFormat.string(from: selectedOrphanBytes)
            ))
        }
    }

    /// Whitelist permanen + buang dari hasil (context menu Orphan).
    private func whitelistAndExclude(_ item: OrphanItem) {
        var whitelist = UserWhitelist.load()
        whitelist.add(item.url.path)
        whitelist.save()
        model.excludeOrphan(item)
    }

    // MARK: Daftar aplikasi

    private var listSection: some View {
        List {
            listContent
            orphanSection
        }
        .listStyle(.inset)
    }

    /// Header pencarian — Section biar nempel di List.
    private var listContent: some View {
        Section {
            if !model.isLoadingApps && filteredApps.isEmpty {
                Text(NSLocalizedString("Tidak ada aplikasi yang cocok.", comment: ""))
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredApps) { app in
                    HStack(spacing: DKSpacing.md) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 28, height: 28)
                        ReadoutRow(
                            value: ByteFormat.string(from: app.sizeBytes),
                            label: app.name,
                            detail: app.bundleID
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { select(app) }
                    }
                    .padding(.vertical, DKSpacing.xs)
                    .contentShape(Rectangle())
                    .onTapGesture { select(app) }
                }
            }
        } header: {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(NSLocalizedString("Cari aplikasi…", comment: ""), text: $search)
                    .textFieldStyle(.plain)
                if model.isLoadingApps {
                    ProgressView().controlSize(.small)
                    Text(model.apps.isEmpty
                         ? NSLocalizedString("Memuat aplikasi…", comment: "")
                         : String(format: NSLocalizedString("Memuat… %d aplikasi", comment: ""), model.apps.count)
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, DKSpacing.xs)
        }
    }

    // MARK: Orphan Finder — sisa data tanpa pemilik

    private var orphanSection: some View {
        Section {
            if model.orphans.isEmpty {
                if model.isScanningOrphans {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Memindai Library…", comment: ""))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(NSLocalizedString("Belum dipindai — mulai untuk mencari sisa data aplikasi yang sudah tidak terpasang.", comment: ""))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: DKSpacing.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(
                        NSLocalizedString("Cari nama atau folder…", comment: ""),
                        text: $orphanSearch
                    )
                    .textFieldStyle(.roundedBorder)
                    if !orphanSearch.isEmpty {
                        Button {
                            orphanSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("Bersihkan pencarian", comment: ""))
                    }
                    Picker("", selection: $orphanSort) {
                        ForEach(OrphanSort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                ForEach(visibleOrphans) { item in
                    HStack(spacing: DKSpacing.md) {
                        Toggle("", isOn: Binding(
                            get: { model.selectedOrphans.contains(item.id) },
                            set: { on in
                                if on { model.selectedOrphans.insert(item.id) }
                                else { model.selectedOrphans.remove(item.id) }
                            }
                        ))
                        .labelsHidden()
                        ReadoutRow(
                            value: ByteFormat.string(from: item.sizeBytes),
                            label: item.url.lastPathComponent,
                            detail: "\(item.locationName) · \(URL(fileURLWithPath: item.url.path).deletingLastPathComponent().path)"
                        )
                        .lineLimit(1)
                        .contextMenu {
                            Button {
                                QuickLookCoordinator.shared.show(item.url)
                            } label: {
                                Label(NSLocalizedString("Pratinjau", comment: ""), systemImage: "eye")
                            }
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "magnifyingglass")
                            }
                            Divider()
                            Button(NSLocalizedString("Selalu kecualikan folder ini", comment: "")) {
                                whitelistAndExclude(item)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        QuickLookCoordinator.shared.show(item.url)
                    }
                }
                if let orphanMessage = model.orphanMessage {
                    Label(orphanMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    showOrphanConfirm = true
                } label: {
                    Label(
                        String(
                            format: NSLocalizedString("Pindahkan %d item terpilih (%@) ke Trash", comment: ""),
                            model.selectedOrphans.count,
                            ByteFormat.string(from: selectedOrphanBytes)
                        ),
                        systemImage: "arrow.down.trash"
                    )
                }
                .disabled(model.selectedOrphans.isEmpty)
            }
        } header: {
            HStack {
                Label(NSLocalizedString("Sisa Data Tanpa Pemilik", comment: ""), systemImage: "questionmark.folder")
                    .font(.headline)
                Spacer()
                Text(model.orphans.isEmpty
                     ? ""
                     : ByteFormat.string(from: model.orphanTotalBytes)
                )
                .font(.dkData(12))
                .foregroundColor(.secondary)
                Button {
                    Task { await model.scanOrphans() }
                } label: {
                    Label(NSLocalizedString("Pindai", comment: ""), systemImage: "magnifyingglass")
                }
                .controlSize(.small)
                .disabled(model.isScanningOrphans)
            }
        } footer: {
            Text(NSLocalizedString("Item di Library yang tidak cocok dengan aplikasi mana pun yang masih terpasang. Matching ketat — kalau ragu, biarkan tidak tercentang.", comment: ""))
                .font(.caption2)
        }
    }

    private var selectedOrphanBytes: Int64 {
        model.orphans
            .filter { model.selectedOrphans.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }


    // MARK: Detail app terpilih

    private func detailSection(_ app: InstalledApp) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                HStack(spacing: DKSpacing.md) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: DKSpacing.xs) {
                        Text(app.name).font(.title2.weight(.semibold))
                        Text(app.bundleID ?? "—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        selectedApp = nil
                        leftovers = []
                        selectedLeftovers = []
                    } label: {
                        Label(NSLocalizedString("Kembali ke daftar", comment: ""), systemImage: "chevron.left")
                    }
                }

                HStack {
                    Text(String(
                        format: NSLocalizedString("Aplikasi (%@) — selalu ikut dihapus", comment: ""),
                        ByteFormat.string(from: app.sizeBytes)
                    ))
                    .font(.callout.weight(.medium))
                    Spacer()
                    Image(systemName: "trash")
                        .foregroundStyle(DKColor.accent)
                }
                .padding(DKSpacing.md)
                .background(DKColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))

                VStack(alignment: .leading, spacing: DKSpacing.md) {
                    Text(NSLocalizedString("Sisa data yang ditemukan", comment: ""))
                        .font(.title3.weight(.semibold))
                    Text(NSLocalizedString("Dicocokkan dari bundle ID aplikasi. Item berlabel Perkiraan dicocokkan dari nama dan perlu diperiksa dulu sebelum ikut dihapus.", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLoadingLeftovers {
                        HStack(spacing: DKSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text(NSLocalizedString("Memuat sisa data…", comment: ""))
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    } else if leftovers.isEmpty {
                        Text(NSLocalizedString("Tidak ada sisa data yang ditemukan.", comment: ""))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: DKSpacing.sm) {
                            ForEach(leftovers) { item in
                                HStack {
                                    ReadoutRow(
                                        value: ByteFormat.string(from: item.sizeBytes),
                                        label: item.url.lastPathComponent,
                                        detail: item.url.deletingLastPathComponent().lastPathComponent,
                                        badge: item.confidence == .fuzzy
                                            ? NSLocalizedString("Perkiraan", comment: "")
                                            : nil
                                    )
                                    Spacer(minLength: DKSpacing.sm)
                                    Toggle("", isOn: Binding(
                                        get: { selectedLeftovers.contains(item.id) },
                                        set: { isChecked in
                                            if isChecked {
                                                selectedLeftovers.insert(item.id)
                                            } else {
                                                selectedLeftovers.remove(item.id)
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                }
                                .padding(.vertical, DKSpacing.xs)
                            }
                        }
                        .padding(DKSpacing.md)
                        .background(DKColor.surfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                    }
                }

                if let cleanedMessage {
                    Label(cleanedMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DKColor.accent)
                    if failureCount > 0 {
                        Text(String(
                            format: NSLocalizedString("%d item gagal dibersihkan", comment: ""),
                            failureCount
                        ))
                        .font(.caption)
                        .foregroundColor(DKColor.attention)
                    }
                }

                HStack(spacing: DKSpacing.md) {
                    // Uninstall selalu lewat konfirmasi eksplisit — tier risiko
                    // lebih tinggi dari clean cache (guardrails poin 5).
                    Button {
                        showConfirm = true
                    } label: {
                        Label(
                            String(format: NSLocalizedString("Uninstall %@", comment: ""), app.name),
                            systemImage: "trash"
                        )
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%@ terpilih", comment: ""),
                        ByteFormat.string(from: selectedTotalBytes)
                    ))
                    .font(.dkData(13))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Aksi

    private func select(_ app: InstalledApp) {
        selectedApp = app
        leftovers = []
        selectedLeftovers = []
        cleanedMessage = nil
        isLoadingLeftovers = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { [app] in
                LeftoverScanner.leftovers(for: app)
            }.value
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
        failureCount = outcome.failed.count
        cleanedMessage = String(
            format: NSLocalizedString("%@ berhasil di-uninstall", comment: ""),
            app.name
        )
        selectedApp = nil
        leftovers = []
        selectedLeftovers = []
        // Refresh daftar (app barusan ilang).
        model.refreshApps()
    }

}
