import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Settings (⌘,) — tiga tab: Umum (bahasa + Recency Guard), Whitelist,
/// dan Riwayat (log viewer Safety Ledger).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(NSLocalizedString("Umum", comment: ""), systemImage: "gearshape") }
            WhitelistSettingsView()
                .tabItem { Label(NSLocalizedString("Whitelist", comment: ""), systemImage: "line.3.horizontal.decrease.circle") }
            HistorySettingsView()
                .tabItem { Label(NSLocalizedString("Riwayat", comment: ""), systemImage: "clock.arrow.circlepath") }
            IntegrationsSettingsView()
                .tabItem { Label(NSLocalizedString("Integrasi", comment: ""), systemImage: "bolt.horizontal") }
            UpdateSettingsView()
                .tabItem { Label(NSLocalizedString("Pembaruan", comment: ""), systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 400)
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
                        Text(NSLocalizedString("Menghubungi server rilis…", comment: ""))
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
                                Label(NSLocalizedString("Buka Halaman Rilis", comment: ""), systemImage: "safari")
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
                Text(NSLocalizedString("Pemeriksaan hanya berjalan saat kamu menekan tombol — tidak ada pemeriksaan otomatis di latar belakang, tidak ada data yang dikirim selain permintaan halaman rilis. Pemasangan otomatis (Sparkle) akan tersedia setelah aplikasi ditandatangani.", comment: ""))
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let langs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
            guard let first = langs.first else { return .system }
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
    /// Binding langsung ke model bersama — perubahan langsung efektif.
    private var scheduledBinding: Binding<Bool> {
        Binding(
            get: { SystemStatsModel.shared.scheduledMaintenanceEnabled },
            set: { SystemStatsModel.shared.scheduledMaintenanceEnabled = $0 }
        )
    }

    var body: some View {
        Form {
            Picker(NSLocalizedString("Bahasa", comment: ""), selection: $language) {
                ForEach(LanguageSetting.allCases) { setting in
                    Text(setting.label).tag(setting)
                }
            }
            Text(NSLocalizedString("Efektif setelah aplikasi dibuka ulang.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Toggle(NSLocalizedString("Pemeliharaan terjadwal", comment: ""), isOn: scheduledBinding)
            Text(NSLocalizedString("Selama Respite berjalan, kondisi sistem diperiksa berkala — kalau Maintenance Sweep disarankan, kamu mendapat notifikasi. (Versi jadwal penuh via launchd menyusul bersama infra signing.)", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(NSLocalizedString("Jalankan Respite saat login", comment: ""), isOn: $launchAtLogin)
            Text(NSLocalizedString("Daftarkan LaunchAgent kecil yang membuka Respite setiap Mac dinyalakan. Kelola juga dari modul Aplikasi Saat Login.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Stepper(value: $recencyDays, in: 1...30) {
                HStack {
                    Text(NSLocalizedString("Masa Recency Guard", comment: ""))
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%d hari", comment: ""),
                        recencyDays
                    ))
                    .font(.dkData(13))
                    .foregroundColor(.secondary)
                }
            }
            Text(String(
                format: NSLocalizedString("Item yang disentuh dalam %d hari terakhir tidak tercentang secara bawaan.", comment: ""),
                recencyDays
            ))
            .font(.caption)
            .foregroundColor(.secondary)
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
            do {
                try StartupManager.setRespiteAutoStart(enabled)
            } catch {
                launchAtLogin.toggle() // rollback
            }
        }
    }
}

// MARK: - Whitelist

private struct WhitelistSettingsView: View {
    @State private var patterns: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(NSLocalizedString("Folder yang dikecualikan dari hasil scan.", comment: ""))
                    .font(.callout)
                Text(NSLocalizedString("Whitelist tidak dapat mengubah Protected List — folder sistem dan dokumen pribadi tetap terlindungi.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DKSpacing.md)

            Divider()

            if patterns.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: NSLocalizedString("Belum ada pengecualian", comment: ""),
                    message: NSLocalizedString("Tambahkan folder yang tidak ingin discan, misalnya disk image yang selalu ter-mount.", comment: "")
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
                            Button(NSLocalizedString("Hapus", comment: "")) {
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
        panel.message = NSLocalizedString("Pilih folder yang tidak ingin dimasukkan ke hasil scan Respite.", comment: "")
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
                Text(NSLocalizedString("Setiap aksi pembersihan tercatat sebelum dieksekusi — untuk audit dan pemulihan.", comment: ""))
                    .font(.callout)
                Text(NSLocalizedString("Menghapus riwayat tidak memengaruhi file yang sudah ada di Trash.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DKSpacing.md)

            Divider()

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: NSLocalizedString("Belum ada riwayat.", comment: ""),
                    message: NSLocalizedString("Aksi pembersihan, penghentian proses, dan Maintenance Sweep akan tercatat di sini.", comment: "")
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
                    format: NSLocalizedString("%d entri", comment: ""),
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
            Text(NSLocalizedString("Riwayat adalah jejak audit aksi yang sudah dilakukan. File di Trash tidak terpengaruh.", comment: ""))
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
        case "kill-process": return NSLocalizedString("Hentikan proses", comment: "")
        case "restart-process": return NSLocalizedString("Restart proses", comment: "")
        default: return actionType
        }
    }
}


// MARK: - Integrasi (Quick Launcher)

/// Respite:// URL scheme dari Raycast/Alfred — aksinya cuma membuka modul,
/// tidak ada auto-execute (TRD §4.13.2).
private struct IntegrationsSettingsView: View {
    private let actions: [(name: String, url: String, symbol: String)] = [
        ("Monitor Memori", "respite://action/free-memory", "memorychip"),
        ("Diagnosis Performa", "respite://action/run-diagnostic", "waveform.path.ecg"),
        ("Maintenance Sweep", "respite://action/maintenance-sweep", "gauge.with.dots.needle.67percent"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Pemicu cepat dari Raycast atau Alfred lewat skema URL respite:// — Respite harus sedang berjalan. Semua aksi hanya membuka modul terkait, tidak ada yang dieksekusi otomatis.", comment: ""))
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
