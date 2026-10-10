import SwiftUI
import ServiceManagement
import RespiteCore
import DesignKit

/// "Aplikasi Saat Login" (TRD §4.8): LaunchAgents/LaunchDaemons dengan
/// asal-usul app pemiliknya. Yang tampil di depan hanya agent milik user
/// (bisa dinyalakan/dimatikan); item sistem disimpan di bagian terlipat.
struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var isLoading = true
    @State private var resultMessage: String?
    /// Status enabled per path plist — dihitung SEKALI di background setelah
    /// scan (bukan per-render: itu spawn launchctl terus-menerus).
    @State private var enabledState: [String: Bool] = [:]
    /// Agent dikelola Respite yang menunggu konfirmasi hapus.
    @State private var pendingRemoval: StartupItem?
    @State private var showSystemItems = false

    private var userItems: [StartupItem] {
        items.filter { $0.source == .userLaunchAgent }
    }

    private var systemItems: [StartupItem] {
        items.filter { $0.source != .userLaunchAgent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: DKSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Aplikasi yang otomatis jalan saat kamu masuk", comment: ""))
                        .font(.headline)
                    Text(NSLocalizedString("Matikan yang tidak kamu butuhkan supaya Mac lebih cepat siap dipakai. Perubahan berlaku saat kamu masuk lagi.", comment: ""))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    pickApp()
                } label: {
                    Label(NSLocalizedString("Tambah Aplikasi…", comment: ""), systemImage: "plus")
                }
                Button {
                    Task { await load() }
                } label: {
                    Label(NSLocalizedString("Pindai ulang", comment: ""), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundColor(Color.respite)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoading {
                HStack(spacing: DKSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(NSLocalizedString("Memuat…", comment: "")).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if userItems.isEmpty {
                    ToolEmptyResult(
                        title: NSLocalizedString("Belum ada aplikasi yang otomatis jalan", comment: ""),
                        message: NSLocalizedString("Mac kamu langsung siap dipakai saat masuk. Tekan \"Tambah Aplikasi…\" kalau ingin ada aplikasi yang otomatis terbuka.", comment: "")
                    )
                } else {
                    itemList(userItems)
                }

                if !systemItems.isEmpty {
                    DisclosureGroup(isExpanded: $showSystemItems) {
                        VStack(alignment: .leading, spacing: DKSpacing.sm) {
                            Text(NSLocalizedString("Bagian ini diatur oleh macOS atau aplikasi yang butuh izin admin. Tidak bisa diubah dari sini — kalau perlu, pakai Pengaturan Sistem.", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            itemList(systemItems)
                            Button {
                                SMAppService.openSystemSettingsLoginItems()
                            } label: {
                                Label(NSLocalizedString("Buka Pengaturan Sistem", comment: ""), systemImage: "gearshape")
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, DKSpacing.xs)
                    } label: {
                        Text(String(
                            format: NSLocalizedString("Bagian sistem (%d) — dikelola macOS", comment: ""),
                            systemItems.count
                        ))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    }
                }
            }

            ToolDetails {
                Text(NSLocalizedString("Agent milik user bisa dinyalakan/dimatikan langsung dari sini — berlaku saat login berikutnya. Tombol Tambah Aplikasi mendaftarkan app pilihanmu lewat LaunchAgent yang dikelola Respite. Agent SISTEM butuh hak admin: kelola lewat tombol Pengaturan Login Items.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("Lokasi yang diperiksa: ~/Library/LaunchAgents (LaunchAgent user), /Library/LaunchAgents (LaunchAgent sistem), dan /Library/LaunchDaemons (LaunchDaemon, jalan sejak boot). \"Asalnya tidak diketahui\" berarti label plist tidak cocok dengan app terinstall mana pun.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(
                    format: NSLocalizedString("Ditemukan %d item launchd. Klik kanan sebuah baris untuk melihat file plist-nya di Finder.", comment: ""),
                    items.count
                ))
                Button {
                    SMAppService.openSystemSettingsLoginItems()
                } label: {
                    Label(NSLocalizedString("Buka Pengaturan Login Items", comment: ""), systemImage: "gearshape")
                }
                .controlSize(.small)
            }
        }
        .task { await load() }
        .alert(
            String(
                format: NSLocalizedString("Hapus %@ dari daftar?", comment: ""),
                pendingRemoval.map(displayName) ?? ""
            ),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Hapus", comment: ""), role: .destructive) {
                if let item = pendingRemoval {
                    removeManaged(item)
                }
                pendingRemoval = nil
            }
        } message: {
            Text(NSLocalizedString("Aplikasinya tidak lagi otomatis jalan saat kamu masuk. Aplikasinya sendiri tidak dihapus, dan kamu bisa menambahkannya lagi kapan saja.", comment: ""))
        }
    }

    // MARK: Daftar

    private func itemList(_ rows: [StartupItem]) -> some View {
        VStack(spacing: DKSpacing.sm) {
            ForEach(rows) { item in
                row(item)
                if item.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    private func isManaged(_ item: StartupItem) -> Bool {
        item.label.hasPrefix(StartupManager.managedPrefix)
    }

    /// Nama yang dikenali orang: app pemilik dulu, baru label mentah.
    private func displayName(_ item: StartupItem) -> String {
        if let owner = item.owner { return owner.name }
        if isManaged(item) {
            let slug = String(item.label.dropFirst(StartupManager.managedPrefix.count))
            return slug.isEmpty ? item.label : slug
        }
        return item.label
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(alignment: .center, spacing: DKSpacing.md) {
            Image(systemName: item.owner == nil && !isManaged(item) ? "questionmark.app.dashed" : "app.badge.checkmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(item.owner == nil && !isManaged(item) ? DKColor.attention : Color.respite)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(item))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isManaged(item) {
                    Text(NSLocalizedString("Ditambahkan lewat Respite", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if item.owner == nil {
                    Text(NSLocalizedString("Asalnya tidak diketahui — matikan kalau kamu tidak mengenalnya", comment: ""))
                        .font(.caption)
                        .foregroundColor(DKColor.attention)
                        .fixedSize(horizontal: false, vertical: true)
                } else if item.source == .systemLaunchDaemon {
                    Text(NSLocalizedString("Jalan sejak Mac dinyalakan", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isManaged(item) && item.source == .userLaunchAgent {
                Button(NSLocalizedString("Hapus", comment: "")) {
                    pendingRemoval = item
                }
                .controlSize(.small)
            }
            // Plist di /Library milik root — tulis gagal setelah launchctl
            // disable sukses → state setengah jadi. Toggle cuma buat agent user.
            if item.source == .userLaunchAgent {
                Toggle("", isOn: agentToggle(item))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "magnifyingglass")
            }
        }
    }

    private func removeManaged(_ item: StartupItem) {
        let name = displayName(item)
        do {
            try StartupManager.removeManagedAgent(plistURL: item.url)
            SafetyLedger.record(LedgerEntry(
                actionType: "startup-remove",
                target: item.label,
                reversible: true,
                detail: "hapus LaunchAgent Respite (app tidak dihapus)"
            ))
            resultMessage = String(
                format: NSLocalizedString("%@ tidak lagi otomatis jalan saat login", comment: ""),
                name
            )
        } catch {
            resultMessage = String(
                format: NSLocalizedString("Gagal mengubah %@", comment: ""),
                name
            )
        }
        Task { await load() }
    }

    private func load() async {
        isLoading = items.isEmpty
        let result = await Task.detached(priority: .userInitiated) {
            let scanned = StartupItems.scan()
            // Satu print-disabled (ter-cache) untuk SEMUA baris.
            // Key = path, bukan label: vendor sering memasang label yang sama
            // di LaunchAgents user & sistem — uniqueKeysWithValues → crash.
            let states = Dictionary(
                scanned.map { ($0.url.path, StartupManager.isEnabled(plistURL: $0.url)) },
                uniquingKeysWith: { first, _ in first }
            )
            return (scanned, states)
        }.value
        items = result.0
        enabledState = result.1
        isLoading = false
    }

    /// Toggle untuk agent user & yang dikelola Respite — berlaku saat login
    /// berikutnya. Agent sistem butuh admin: tombolnya nggak ditampilkan.
    private func agentToggle(_ item: StartupItem) -> Binding<Bool> {
        Binding(
            get: { enabledState[item.url.path] ?? true },
            set: { enabled in
                // Optimistic: UI langsung berubah; launchctl (2-3 proses,
                // ~ratusan ms) jalan di background — JANGAN blok main thread.
                enabledState[item.url.path] = enabled
                let url = item.url
                let label = item.label
                Task.detached(priority: .userInitiated) {
                    do {
                        try StartupManager.setAgentEnabled(plistURL: url, enabled: enabled)
                        SafetyLedger.record(LedgerEntry(
                            actionType: "startup-toggle",
                            target: label,
                            reversible: true,
                            detail: enabled ? "aktifkan saat login" : "nonaktifkan saat login"
                        ))
                    } catch {
                        await MainActor.run {
                            resultMessage = String(
                                format: NSLocalizedString("Gagal mengubah %@", comment: ""),
                                label
                            )
                            enabledState[url.path] = !enabled
                        }
                    }
                }
            }
        )
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.message = NSLocalizedString("Pilih aplikasi yang ingin dijalankan otomatis saat login.", comment: "")
        panel.begin { response in
            guard response == .OK else { return }
            var added = 0
            for url in panel.urls {
                do {
                    try StartupManager.addLoginApp(appPath: url.path)
                    SafetyLedger.record(LedgerEntry(
                        actionType: "startup-add",
                        target: url.lastPathComponent,
                        reversible: true,
                        detail: "jalankan saat login via LaunchAgent Respite"
                    ))
                    added += 1
                } catch {
                    resultMessage = String(
                        format: NSLocalizedString("Gagal mendaftarkan %@", comment: ""),
                        url.lastPathComponent
                    )
                }
            }
            if added > 0 {
                resultMessage = String(
                    format: NSLocalizedString("%d aplikasi ditambahkan — berjalan saat login berikutnya", comment: ""),
                    added
                )
            }
            Task { await load() }
        }
    }
}
