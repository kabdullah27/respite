import SwiftUI
import ServiceManagement
import RespiteCore
import DesignKit

/// Startup & Login Items (TRD §4.8): LaunchAgents/LaunchDaemons dengan
/// asal-usul app pemiliknya. Read-only v1 — mematikan item dianter ke
/// System Settings via deep-link resmi SMAppService.
struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var isLoading = true
    @State private var resultMessage: String?
    /// Status enabled per label — dihitung SEKALI di background setelah
    /// scan (bukan per-render: itu spawn launchctl terus-menerus).
    @State private var enabledState: [String: Bool] = [:]

    private let sourceOrder: [StartupItem.Source] = [
        .userLaunchAgent, .systemLaunchAgent, .systemLaunchDaemon,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                HStack(spacing: DKSpacing.md) {
                    Button {
                        Task { await load() }
                    } label: {
                        Label(NSLocalizedString("Pindai Ulang", comment: ""), systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%d item", comment: ""),
                        items.count
                    ))
                    .font(.dkData(12))
                    .foregroundStyle(.secondary)
                    Button {
                        pickApp()
                    } label: {
                        Label(NSLocalizedString("Tambah Aplikasi…", comment: ""), systemImage: "plus")
                    }
                    .controlSize(.small)
                    Button {
                        SMAppService.openSystemSettingsLoginItems()
                    } label: {
                        Label(NSLocalizedString("Buka Pengaturan Login Items", comment: ""), systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }

                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundColor(DKColor.accent)
                }

                if isLoading {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Memuat…", comment: "")).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if items.isEmpty {
                    EmptyStateView(
                        symbol: "person.crop.circle.badge.clock",
                        title: NSLocalizedString("Tidak ada item launchd", comment: ""),
                        message: NSLocalizedString("Tidak ditemukan LaunchAgent/LaunchDaemon di lokasi standar.", comment: "")
                    )
                } else {
                    ForEach(sourceOrder, id: \.rawValue) { source in
                        let rows = items.filter { $0.source == source }
                        if !rows.isEmpty {
                            section(source: source, rows: rows)
                        }
                    }
                }

                Text(NSLocalizedString("Agent milik user bisa dinyalakan/dimatikan langsung dari sini — berlaku saat login berikutnya. Tombol Tambah Aplikasi mendaftarkan app pilihanmu lewat LaunchAgent yang dikelola Respite. Agent SISTEM butuh hak admin: kelola lewat tombol Pengaturan Login Items.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await load() }
    }

    // MARK: Section per sumber

    private func section(source: StartupItem.Source, rows: [StartupItem]) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(sourceName(source)).font(.title3.weight(.semibold))
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
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(alignment: .top, spacing: DKSpacing.md) {
            Image(systemName: item.owner == nil ? "questionmark.square.dashed" : "app.dashed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(item.owner == nil ? DKColor.attention : DKColor.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.owner?.name ?? item.label)
                    .font(.callout.weight(.medium))
                if let owner = item.owner {
                    Text(String(
                        format: NSLocalizedString("dari app %@ (%@)", comment: ""),
                        owner.name, owner.bundleID
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text(NSLocalizedString("Asal tidak diketahui — label tidak cocok dengan app terinstall mana pun", comment: ""))
                        .font(.caption)
                        .foregroundColor(DKColor.attention)
                }
                if let program = item.programPath {
                    Text(program)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if item.source != .systemLaunchDaemon {
                Toggle("", isOn: agentToggle(item))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Text(item.url.lastPathComponent)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160, alignment: .trailing)
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "magnifyingglass")
            }
        }
    }

    private func sourceName(_ source: StartupItem.Source) -> String {
        switch source {
        case .userLaunchAgent: return NSLocalizedString("Launch Agent — user (jalan saat login)", comment: "")
        case .systemLaunchAgent: return NSLocalizedString("Launch Agent — sistem", comment: "")
        case .systemLaunchDaemon: return NSLocalizedString("Launch Daemon — sistem (jalan sejak boot)", comment: "")
        }
    }

    private func load() async {
        isLoading = items.isEmpty
        let result = await Task.detached(priority: .userInitiated) {
            let scanned = StartupItems.scan()
            // Satu print-disabled (ter-cache) untuk SEMUA baris.
            let states = Dictionary(
                uniqueKeysWithValues: scanned.map { ($0.label, StartupManager.isEnabled(plistURL: $0.url)) }
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
            get: { enabledState[item.label] ?? true },
            set: { enabled in
                // Optimistic: UI langsung berubah; launchctl (2-3 proses,
                // ~ratusan ms) jalan di background — JANGAN blok main thread.
                enabledState[item.label] = enabled
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
                            enabledState[label] = !enabled
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
