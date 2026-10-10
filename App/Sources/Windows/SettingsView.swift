import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Settings (⌘,) — tab: Umum (bahasa, login, pemeriksaan berkala +
/// Keamanan file / Recency Guard), Pengecualian (whitelist), Riwayat (log
/// Safety Ledger), Pintasan (URL scheme), dan Pembaruan.
struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general, exclusions, history, shortcuts, updates

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return NSLocalizedString("Umum", comment: "")
            case .exclusions: return NSLocalizedString("Pengecualian", comment: "")
            case .history: return NSLocalizedString("Riwayat", comment: "")
            case .shortcuts: return NSLocalizedString("Pintasan", comment: "")
            case .updates: return NSLocalizedString("Pembaruan", comment: "")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .exclusions: return "line.3.horizontal.decrease.circle"
            case .history: return "clock.arrow.circlepath"
            case .shortcuts: return "bolt.horizontal"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }

        @MainActor @ViewBuilder
        var content: some View {
            switch self {
            case .general: GeneralSettingsView()
            case .exclusions: WhitelistSettingsView()
            case .history: HistorySettingsView()
            case .shortcuts: IntegrationsSettingsView()
            case .updates: UpdateSettingsView()
            }
        }
    }

    /// true = tampil di dalam window utama (halaman "Pengaturan" di sidebar),
    /// false = window Settings standar macOS (⌘,).
    var embedded = false
    @State private var selectedTab: Tab = .general

    var body: some View {
        if embedded {
            // Di dalam halaman ScrollView standar (sama seperti alat lain);
            // Form/List butuh tinggi eksplisit supaya nggak kolaps.
            VStack(alignment: .leading, spacing: DKSpacing.md) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbol).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
                selectedTab.content
                    .frame(maxWidth: 720)
                    .frame(height: 540, alignment: .top)
                    .background(DKColor.surfaceSecondary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 2))
            }
        } else {
            TabView {
                ForEach(Tab.allCases) { tab in
                    tab.content
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                }
            }
            .frame(width: 560, height: 440)
        }
    }
}

// MARK: - Pembaruan

/// Cek pembaruan MANUAL — tidak ada polling background (satu-satunya fitur
/// yang menyentuh jaringan; jalan hanya saat user minta).
struct UpdateSettingsView: View {
    @State private var isChecking = false
    @State private var info: UpdateInfo?
    @State private var errorMessage: String?
    @State private var lastChecked: Date?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(NSLocalizedString("Versi terpasang", comment: ""))
                    Spacer()
                    Text(Self.installedVersion)
                        .font(.dkData(12))
                }
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    Label(
                        NSLocalizedString("Periksa Pembaruan…", comment: ""),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(isChecking)

                if isChecking {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Sedang memeriksa…", comment: ""))
                            .foregroundColor(.secondary)
                    }
                }

                if let info {
                    if info.isUpdateAvailable {
                        Label(
                            String(
                                format: NSLocalizedString("Pembaruan tersedia: %@ → %@", comment: ""),
                                info.currentVersion, info.latestVersion
                            ),
                            systemImage: "arrow.up.circle.fill"
                        )
                        .foregroundColor(Color.respite)
                        if let page = info.releasePageURL {
                            Button {
                                NSWorkspace.shared.open(page)
                            } label: {
                                Label(NSLocalizedString("Lihat & Unduh Versi Baru", comment: ""), systemImage: "safari")
                            }
                        }
                    } else {
                        Label(
                            NSLocalizedString("Respite sudah versi terbaru.", comment: ""),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundColor(Color.respite)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundColor(DKColor.attention)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let lastChecked {
                    Text(String(
                        format: NSLocalizedString("Terakhir diperiksa %@", comment: ""),
                        lastChecked.formatted(date: .omitted, time: .shortened)
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } footer: {
                Text(NSLocalizedString("Respite hanya memeriksa saat kamu menekan tombol ini. Tidak ada pemeriksaan otomatis dan tidak ada data pribadi yang dikirim.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Tanpa .grouped, Form macOS jadi dua kolom rata tepi (konten
        // menempel ke pinggir window & versi terpotong).
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private func check() async {
        isChecking = true
        errorMessage = nil
        info = nil
        do {
            info = try await UpdateChecker.check()
        } catch {
            errorMessage = error.localizedDescription
        }
        lastChecked = Date()
        isChecking = false
    }
}

// MARK: - Umum

private struct GeneralSettingsView: View {
    /// Override bahasa via `AppleLanguages` scoped ke app ini (TRD §4.19) —
    /// efektif setelah relaunch, bukan hot-swap.
    private enum LanguageSetting: String, CaseIterable, Identifiable {
        case system = ""
        case indonesian = "id"
        case english = "en"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return NSLocalizedString("Ikut Sistem", comment: "")
            case .indonesian: return "Bahasa Indonesia"
            case .english: return "English"
            }
        }

        static func current() -> LanguageSetting {
            // Baca domain app saja — AppleLanguages global (bahasa sistem)
            // bukan pilihan user di Respite.
            guard let first = AppLanguage.appDomainLanguages()?.first else { return .system }
            return LanguageSetting(rawValue: first) ?? .system
        }

        func apply() {
            let defaults = UserDefaults.standard
            switch self {
            case .system: defaults.removeObject(forKey: "AppleLanguages")
            case .indonesian: defaults.set(["id"], forKey: "AppleLanguages")
            case .english: defaults.set(["en"], forKey: "AppleLanguages")
            }
        }
    }

    @State private var language: LanguageSetting = .system
    @State private var recencyDays: Int = RecencyGuard.thresholdDays()
    @State private var launchAtLogin = false
    /// Cermin @State dari model bersama — Binding polos ke singleton nggak
    /// memicu re-render, toggle bisa kelihatan nggak berubah. (Observe model
    /// langsung = re-render Settings tiap 2 detik.)
    @State private var scheduledMaintenance = SystemStatsModel.shared.scheduledMaintenanceEnabled
    private var scheduledBinding: Binding<Bool> {
        Binding(
            get: { scheduledMaintenance },
            set: {
                scheduledMaintenance = $0
                SystemStatsModel.shared.scheduledMaintenanceEnabled = $0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(NSLocalizedString("Bahasa", comment: ""), selection: $language) {
                    ForEach(LanguageSetting.allCases) { setting in
                        Text(setting.label).tag(setting)
                    }
                }
                helper(NSLocalizedString("Berlaku setelah Respite dibuka ulang.", comment: ""))

                Toggle(NSLocalizedString("Buka Respite otomatis saat kamu masuk ke Mac", comment: ""), isOn: $launchAtLogin)
                helper(NSLocalizedString("Bisa juga diatur di alat Aplikasi Saat Login.", comment: ""))

                Toggle(NSLocalizedString("Ingatkan saya kalau Mac perlu dibersihkan", comment: ""), isOn: scheduledBinding)
                helper(NSLocalizedString("Selama Respite berjalan, kondisi Mac dicek sesekali. Kamu dapat notifikasi kalau ada yang bisa dibersihkan — tidak ada yang dihapus otomatis.", comment: ""))
            } header: {
                Text(NSLocalizedString("Umum", comment: ""))
            }

            Section {
                Stepper(value: $recencyDays, in: 1...30) {
                    Text(String(
                        format: NSLocalizedString("Jangan centang otomatis file yang dipakai dalam %d hari terakhir", comment: ""),
                        recencyDays
                    ))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                }
                helper(NSLocalizedString("File yang baru saja kamu pakai tidak dicentang dulu, jadi tidak ikut terbuang tanpa sengaja. Kamu tetap bisa mencentangnya sendiri.", comment: ""))
            } header: {
                Text(NSLocalizedString("Keamanan file", comment: ""))
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            language = LanguageSetting.current()
            recencyDays = RecencyGuard.thresholdDays()
            launchAtLogin = StartupManager.isRespiteAutoStartEnabled()
        }
        .onChange(of: language) { newValue in
            newValue.apply()
        }
        .onChange(of: recencyDays) { newValue in
            UserDefaults.standard.set(newValue, forKey: RecencyGuard.defaultsKey)
        }
        .onChange(of: launchAtLogin) { enabled in
            // onAppear menyetel nilai dari sistem → onChange ikut terpicu.
            // Jangan daftar ulang (atau, kalau gagal, malah mematikan)
            // auto-start cuma karena Settings dibuka.
            guard enabled != StartupManager.isRespiteAutoStartEnabled() else { return }
            do {
                try StartupManager.setRespiteAutoStart(enabled)
            } catch {
                launchAtLogin.toggle() // rollback
            }
        }
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Whitelist

private struct WhitelistSettingsView: View {
    @State private var patterns: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(NSLocalizedString("Folder di sini tidak akan pernah diperiksa atau disarankan untuk dibersihkan.", comment: ""))
                    .font(.callout)
                Text(NSLocalizedString("Folder sistem dan dokumen pribadi selalu dilindungi, apa pun isi daftar ini.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DKSpacing.md)

            Divider()

            if patterns.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: NSLocalizedString("Belum ada pengecualian", comment: ""),
                    message: NSLocalizedString("Tambahkan folder yang tidak ingin disentuh Respite.", comment: "")
                )
            } else {
                List {
                    ForEach(patterns, id: \.self) { pattern in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(pattern)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(NSLocalizedString("Keluarkan", comment: "")) {
                                var whitelist = UserWhitelist.load()
                                whitelist.remove(pattern)
                                whitelist.save()
                                patterns = whitelist.patterns
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    addFolder()
                } label: {
                    Label(NSLocalizedString("Tambah Folder…", comment: ""), systemImage: "plus")
                }
            }
            .padding(DKSpacing.md)
        }
        .onAppear {
            patterns = UserWhitelist.load().patterns
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("Pilih folder yang tidak ingin diperiksa Respite.", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            var whitelist = UserWhitelist.load()
            whitelist.add(url.path)
            whitelist.save()
            patterns = whitelist.patterns
        }
    }
}

// MARK: - Riwayat (Safety Ledger viewer)

/// Log viewer Safety Ledger — setiap aksi destructive tercatat SEBELUM
/// eksekusi (TRD §7); ini jalurnya user lihat jejak itu.
private struct HistorySettingsView: View {
    @State private var entries: [LedgerEntry] = []
    @State private var showClearConfirm = false
    @State private var exportFormat = 0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(NSLocalizedString("Semua yang pernah dibersihkan Respite tercatat di sini.", comment: ""))
                    .font(.callout)
                Text(NSLocalizedString("Menghapus catatan ini tidak mengubah file yang ada di Trash.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DKSpacing.md)

            Divider()

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: NSLocalizedString("Belum ada riwayat.", comment: ""),
                    message: NSLocalizedString("Setiap kali kamu membersihkan atau menutup aplikasi, catatannya muncul di sini.", comment: "")
                )
            } else {
                List(entries.reversed()) { entry in
                    ReadoutRow(
                        value: Self.timeFormatter.string(from: entry.timestamp),
                        label: actionName(entry.actionType),
                        detail: entry.detail
                    )
                    .padding(.vertical, DKSpacing.xs)
                }
                .listStyle(.plain)
            }

            Divider()

            HStack(spacing: DKSpacing.md) {
                Text(String(
                    format: NSLocalizedString("%d catatan", comment: ""),
                    entries.count
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $exportFormat) {
                    Text("JSON").tag(0)
                    Text("CSV").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .disabled(entries.isEmpty)
                Button(NSLocalizedString("Ekspor Riwayat…", comment: "")) {
                    exportHistory()
                }
                .disabled(entries.isEmpty)
                Button(NSLocalizedString("Hapus Riwayat", comment: ""), role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(entries.isEmpty)
            }
            .padding(DKSpacing.md)
        }
        .onAppear { reload() }
        .alert(
            NSLocalizedString("Hapus semua riwayat aksi?", comment: ""),
            isPresented: $showClearConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Hapus Riwayat", comment: ""), role: .destructive) {
                SafetyLedger.clear()
                reload()
            }
        } message: {
            Text(NSLocalizedString("Catatan riwayat akan dihapus. File di Trash tidak terpengaruh.", comment: ""))
        }
    }

    private func reload() {
        entries = SafetyLedger.load()
    }

    private func exportHistory() {
        let isJSON = exportFormat == 0
        let panel = NSSavePanel()
        panel.allowedContentTypes = isJSON ? [.json] : [.commaSeparatedText]
        panel.nameFieldStringValue = "riwayat-respite.\(isJSON ? "json" : "csv")"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let data = isJSON
                ? ReportExporter.jsonData(from: entries)
                : ReportExporter.csv(from: entries).data(using: .utf8)
            guard let data else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func actionName(_ actionType: String) -> String {
        switch actionType {
        case "move-to-trash": return NSLocalizedString("Pindah ke Trash", comment: "")
        case "kill-process": return NSLocalizedString("Tutup aplikasi", comment: "")
        case "restart-process": return NSLocalizedString("Mulai ulang aplikasi", comment: "")
        case "delete-permanent": return NSLocalizedString("Dihapus permanen", comment: "")
        case "archive": return NSLocalizedString("Dirapikan ke arsip", comment: "")
        case "startup-add": return NSLocalizedString("Ditambahkan ke Aplikasi Saat Login", comment: "")
        case "startup-remove": return NSLocalizedString("Dihapus dari Aplikasi Saat Login", comment: "")
        case "startup-toggle": return NSLocalizedString("Aplikasi Saat Login diubah", comment: "")
        default: return actionType
        }
    }
}


// MARK: - Integrasi (Quick Launcher)

/// Respite:// URL scheme dari Raycast/Alfred — aksinya cuma membuka modul,
/// tidak ada auto-execute (TRD §4.13.2).
private struct IntegrationsSettingsView: View {
    private let actions: [(name: String, url: String, symbol: String)] = [
        (Module.memoryMonitor.title, "respite://action/free-memory", "memorychip"),
        (Module.diagnostic.title, "respite://action/run-diagnostic", "waveform.path.ecg"),
        (NSLocalizedString("Pembersihan rutin", comment: ""), "respite://action/maintenance-sweep", "gauge.with.dots.needle.67percent"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Untuk pengguna Raycast atau Alfred: buka alat Respite lewat pintasan. Pintasan hanya membuka alatnya — tidak ada yang dijalankan atau dihapus otomatis. Respite harus sedang berjalan.", comment: ""))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DKSpacing.sm) {
                ForEach(actions, id: \.name) { action in
                    HStack(spacing: DKSpacing.md) {
                        Image(systemName: action.symbol)
                            .foregroundStyle(DKColor.accent)
                            .frame(width: 20)
                        Text(action.name).font(.callout)
                        Spacer()
                        Text(action.url)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, DKSpacing.xs)
                }
            }
            .padding(DKSpacing.md)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))

            Button {
                revealScriptsFolder()
            } label: {
                Label(NSLocalizedString("Buka Folder Skrip", comment: ""), systemImage: "folder")
            }

            Text(NSLocalizedString("Folder berisi skrip Raycast siap pakai dan petunjuk Alfred (Workflow: Keyword → Open URL).", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(DKSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func revealScriptsFolder() {
        // scripts/ di-bundle sebagai folder reference di Resources.
        if let scripts = Bundle.main.resourceURL?.appendingPathComponent("scripts") {
            NSWorkspace.shared.activateFileViewerSelecting([scripts])
        }
    }
}
