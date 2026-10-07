import SwiftUI
import RespiteCore
import DesignKit

/// Dashboard utama — sidebar modul (dikelompokkan per section) + detail pane
/// dengan hero header (Design Spec §8.3). Default ke Diagnostic agar langsung
/// ada konten live saat aplikasi dibuka.
struct DashboardView: View {
    @ObservedObject var model: SystemStatsModel
    @ObservedObject private var largeFiles = LargeFilesModel.shared
    @ObservedObject private var smartScanModel = SmartScanModel.shared
    @ObservedObject private var devCacheModel = DevCacheModel.shared
    @ObservedObject private var duplicateModel = DuplicateModel.shared
    @ObservedObject private var similarModel = SimilarPhotosModel.shared
    @ObservedObject private var uninstallerModel = UninstallerModel.shared
    @ObservedObject private var browserModel = BrowserCleanerModel.shared
    @State private var selectedModule: Module?
    @State private var expandedSections: Set<ModuleSection> = Set(ModuleSection.allCases)

    private func sectionExpandBinding(_ section: ModuleSection) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }

    private func sectionSymbol(_ section: ModuleSection) -> String {
        switch section {
        case .cleaning: return "sparkles"
        case .monitoring: return "stethoscope"
        case .misc: return "switch.2"
        case .support: return "heart"
        }
    }
    @State private var showOnboarding = false
    @Environment(\.openWindow) private var openWindow
    @State private var fdaGranted: Bool? = FullDiskAccess.likelyGranted()
    @State private var fdaRefreshAttempts = 0

    private static let onboardingDoneKey = "app.respite.onboardingCompleted"

    /// "1.0" buat chip sidebar — major.minor dari versi bundle.
    private static var sidebarVersion: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let parts = raw.split(separator: ".")
        return parts.prefix(2).joined(separator: ".")
    }
    private static let fdaPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        SidebarDetailScaffold {
            VStack(spacing: 0) {
                List(selection: $selectedModule) {
                    // Branding — identitas app langsung keliatan di window.
                    HStack(spacing: DKSpacing.sm + 2) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.respite)
                    Text("Respite")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    // Chip versi = jendela About (pola umum di Mac).
                    // Versi dibaca dari bundle — nggak pernah boleh nyelisih
                    // sama CFBundleShortVersionString.
                    Button {
                        RespiteApp.openAboutWindow()
                    } label: {
                        Text(Self.sidebarVersion)
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .padding(.horizontal, DKSpacing.sm)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Capsule())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("Tentang Respite", comment: ""))
                    }
                    .padding(.vertical, 8)

                    // Beranda selalu keliatan — pintu masuk gaya PureMac.
                    sidebarRow(.home)
                        .padding(.bottom, DKSpacing.xs)

                    // Submenu per kategori — bisa dilipat, nggak numpuk 15 baris.
                    ForEach(ModuleSection.allCases) { section in
                        DisclosureGroup(isExpanded: sectionExpandBinding(section)) {
                            ForEach(Module.allCases.filter { $0.section == section && $0 != .home }) { module in
                                sidebarRow(module)
                            }
                        } label: {
                            Label(section.title, systemImage: sectionSymbol(section))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Kartu status sebagai footer tetap — di luar List supaya
                // tombolnya nggak ketelen click-select row.
                sidebarStatusCard
                    .padding(DKSpacing.md)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
            .navigationTitle("Respite")
        } detail: {
            VStack(spacing: 0) {
                // Scan Large Files jalan terus walau pindah modul —
                // statusnya selalu keliatan dari sini + bisa distop.
                if largeFiles.isScanning {
                    scanStatusBanner
                }
                if !activeScans.isEmpty {
                    backgroundScansBanner
                }
                if let module = selectedModule {
                    if module == .home {
                        HomeView(model: model, selectedModule: $selectedModule)
                    } else {
                        ModuleDetailView(module: module, model: model)
                    }
                } else {
                    EmptyStateView(
                        symbol: "waveform.path.ecg",
                        title: NSLocalizedString("Pilih modul dari daftar", comment: ""),
                        message: NSLocalizedString("Semua yang ditampilkan Respite bersifat baca-saja sampai seluruh safety guardrail aktif.", comment: "")
                    )
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            if selectedModule == nil { selectedModule = .home }
            // Tangkap action openWindow resmi buat dipanggil dari menu bar
            // (AppKit) saat window lagi nggak ada.
            MainWindowOpener.open = { openWindow(id: "main") }
            AboutWindowOpener.open = { openWindow(id: "about") }
            if !UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
                showOnboarding = false
            }
            .onDisappear {
                // Ditutup paksa (Esc) juga dianggap selesai — jangan spam tiap launch.
                UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .respiteOpenModule)) { note in
            if let module = note.object as? Module {
                selectedModule = module
            }
        }
        // Balik dari System Settings setelah ngasih FDA → cek ulang otomatis,
        // biar tombol refresh nggak jadi satu-satunya jalan.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fdaGranted = FullDiskAccess.likelyGranted()
        }
    }

    /// Baris modul: icon tile warna kategori (gaya PureMac) + judul.
    private func sidebarRow(_ module: Module) -> some View {
        HStack(spacing: DKSpacing.sm + 2) {
            module.iconTile
            Text(module.title)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .tag(module)
    }

    /// Footer status: Akses Disk Penuh — tombol buka Pengaturan + refresh.
    /// PENTING: tinggi kartu HARUS konstan — kartu nempel di batas bawah
    /// window; kalau klik refresh bikin kartu "tumbuh" (baris hint baru),
    /// bawahnya kepotong batas window di layar pendek (terproduksi & fix
    /// 2026-09-21). Makanya hint MENGGANTIKAN caption, bukan nambah baris.
    private var sidebarStatusCard: some View {
        HStack(spacing: DKSpacing.md) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("Akses Disk Penuh", comment: ""))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(displayCaption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DKSpacing.xs)
            statusIconButton(
                icon: "gearshape",
                help: NSLocalizedString("Buka Pengaturan System Settings", comment: "")
            ) {
                NSWorkspace.shared.open(Self.fdaPaneURL)
            }
            .layoutPriority(1)
            statusIconButton(
                icon: "arrow.clockwise",
                help: NSLocalizedString("Periksa ulang status akses", comment: "")
            ) {
                refreshFDA()
            }
            .layoutPriority(1)
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .overlay(
            // Hairline biar kartu kebaca sebagai kartu di mode gelap juga.
            RoundedRectangle(cornerRadius: DKRadius.card)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    private func statusIconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }

    private func refreshFDA() {
        fdaGranted = FullDiskAccess.likelyGranted()
        fdaRefreshAttempts += 1
    }

    private var showRelaunchHint: Bool {
        fdaGranted == .some(false) && fdaRefreshAttempts > 0
    }

    /// Caption yang dipakai kartu: setelah user nyoba refresh tapi status masih
    /// Nonaktif, caption BERGANTI jadi hint relaunch — tinggi kartu tetap.
    private var displayCaption: String {
        // Hint sengaja PENDEK + lineLimit(2) di Text-nya: tinggi kartu harus
        // identik sebelum & sesudah klik refresh, sekecil apa pun window-nya.
        if showRelaunchHint {
            return NSLocalizedString("Sudah diizinkan? Buka ulang Respite.", comment: "")
        }
        return statusCaption
    }

    private var statusDotColor: Color {
        switch fdaGranted {
        case .some(true): return Color.respite
        case .some(false): return DKColor.attention
        case nil: return Color.secondary
        }
    }

    private var statusCaption: String {
        switch fdaGranted {
        case .some(true):
            return NSLocalizedString("Aktif — semua area bisa dipindai", comment: "")
        case .some(false):
            return NSLocalizedString("Nonaktif — beberapa area terlewati", comment: "")
        case nil:
            return NSLocalizedString("Status tidak dapat ditentukan", comment: "")
        }
    }

    /// Scan yang lagi jalan di modul LAIN — sekarang lanjut di background,
    /// jadi user perlu tahu & bisa lompat ke sana (pola banner Large Files).
    private var activeScans: [Module] {
        var modules: [Module] = []
        if smartScanModel.isScanning { modules.append(.smartScan) }
        if devCacheModel.isScanning { modules.append(.devCacheCleanup) }
        if duplicateModel.isScanning { modules.append(.duplicateFinder) }
        if similarModel.isScanning { modules.append(.similarPhotos) }
        if uninstallerModel.isScanningOrphans { modules.append(.appUninstaller) }
        if browserModel.isLoading { modules.append(.browserCleaner) }
        return modules
    }

    private var backgroundScansBanner: some View {
        HStack(spacing: DKSpacing.md) {
            ProgressView().controlSize(.small)
            Text(NSLocalizedString("Memindai di latar belakang:", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
            ForEach(activeScans) { module in
                Button(module.title) {
                    selectedModule = module
                }
                .controlSize(.small)
                .buttonStyle(.link)
            }
            Spacer()
        }
        .padding(.horizontal, DKSpacing.lg)
        .padding(.vertical, DKSpacing.sm)
        .background(DKColor.surfaceSecondary)
    }

    private var scanStatusBanner: some View {
        HStack(spacing: DKSpacing.md) {
            ProgressView().controlSize(.small)
            Text(String(
                format: NSLocalizedString("Memindai file besar — %d file · %@", comment: ""),
                largeFiles.hits.count,
                ByteFormat.string(from: largeFiles.scannedBytes)
            ))
            .font(.callout)
            .foregroundColor(.secondary)
            Spacer()
            Button(NSLocalizedString("Hentikan pemindaian", comment: "")) {
                largeFiles.cancelScan()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, DKSpacing.lg)
        .padding(.vertical, DKSpacing.sm)
        .background(DKColor.surfaceSecondary)
    }
}

// MARK: - Detail per modul

private struct ModuleDetailView: View {
    let module: Module
    @ObservedObject var model: SystemStatsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.xl) {
                hero

                switch module {
                case .smartScan:
                    SmartScanView()
                case .largeOldFiles:
                    LargeFilesView()
                case .appUninstaller:
                    AppUninstallerView()
                case .memoryMonitor:
                    MemoryMonitorView(model: model)
                case .diagnostic:
                    diagnosticSection
                case .devCacheCleanup:
                    DevCacheView()
                case .shredder:
                    ShredderView()
                case .duplicateFinder:
                    DuplicateView()
                case .similarPhotos:
                    SimilarPhotosView()
                case .batteryHealth:
                    BatteryHealthView(model: model)
                case .startupItems:
                    StartupItemsView()
                case .browserCleaner:
                    BrowserCleanerView()
                case .thermalDetector:
                    ThermalDetectorView(model: model)
                case .keyboardLock:
                    KeyboardLockView()
                case .powerLid:
                    PowerLidView()
                case .donation:
                    DonationDetailView()
                default:
                    comingSoon
                }
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Hero: icon di squircle tinted + judul + respitean — warna ikut
    /// kategori modul (identitas tiap alat, gaya PureMac).
    private var hero: some View {
        HStack(alignment: .top, spacing: DKSpacing.lg) {
            Image(systemName: module.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(module.tintColor)
                .frame(width: 52, height: 52)
                .background(module.tintColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(module.title)
                    .font(.title2.weight(.semibold))
                Text(module.summary)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Diagnostic (live)

    private var diagnosticSection: some View {
        let score = model.healthScore
        let band = HealthScore.Band.band(for: score)
        return VStack(alignment: .leading, spacing: DKSpacing.lg) {
            HStack(spacing: DKSpacing.xl) {
                HealthRing(score: score, color: bandColor(band))

                VStack(alignment: .leading, spacing: DKSpacing.md) {
                    StatusPill(bandLabel(band), color: bandColor(band))
                    Text(headline(band))
                        .font(.title3.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: DKSpacing.md) {
                Text(NSLocalizedString("Faktor penyusun", comment: "")).font(.title3.weight(.semibold))
                factorRow(
                    label: NSLocalizedString("CPU", comment: ""),
                    fraction: model.cpuUsageFraction ?? 0,
                    value: model.cpuUsageFraction
                        .map { String(format: NSLocalizedString("%d%% dipakai", comment: ""), Int($0 * 100)) }
                        ?? NSLocalizedString("mengukur…", comment: ""),
                    note: weightLabel(20)
                )
                factorRow(
                    label: NSLocalizedString("Memori", comment: ""),
                    fraction: model.snapshot.memory.usedFraction,
                    value: String(
                        format: NSLocalizedString("%@ dipakai", comment: ""),
                        ByteFormat.string(from: model.snapshot.memory.usedBytes)
                    ),
                    note: weightLabel(30)
                )
                factorRow(
                    label: NSLocalizedString("Disk", comment: ""),
                    fraction: 1 - model.snapshot.disk.availableFraction,
                    value: String(
                        format: NSLocalizedString("%@ tersedia", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    ),
                    note: weightLabel(25)
                )
                thermalRow
            }

            findingsSection

            Text(NSLocalizedString("Bobot skor: memori 30%, disk 25%, thermal 25%, CPU 20%.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Temuan explanation engine — diagnosis akar masalah, bukan "Clean Now".
    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Temuan", comment: "")).font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                ForEach(model.diagnosticFindings) { finding in
                    HStack(alignment: .top, spacing: DKSpacing.sm) {
                        Image(systemName: severityIcon(finding.severity))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(severityColor(finding.severity))
                            .padding(.top, 2)
                        Text(findingText(finding.kind))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DKSpacing.md)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    private func severityIcon(_ severity: DiagnosticFinding.Severity) -> String {
        switch severity {
        case .info: return "checkmark.circle"
        case .attention: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private func severityColor(_ severity: DiagnosticFinding.Severity) -> Color {
        switch severity {
        case .info: return DKColor.accent
        case .attention: return DKColor.attention
        case .critical: return DKColor.irreversible
        }
    }

    private func findingText(_ kind: DiagnosticFinding.Kind) -> String {
        switch kind {
        case .thermalCritical:
            return NSLocalizedString("Suhu tinggi terdeteksi — macOS sedang menurunkan performa (throttling) untuk mendinginkan sistem.", comment: "")
        case .thermalFair:
            return NSLocalizedString("Suhu mulai meninggi. Tutup aplikasi berat dan pastikan ventilasi tidak tertutup.", comment: "")
        case .cpuHigh(let percent):
            return String(
                format: NSLocalizedString("Beban CPU %d%% — ada proses berat yang sedang berjalan; hentikan atau tutup jika tidak diperlukan.", comment: ""),
                percent
            )
        case .memoryPressure(let percent):
            return String(
                format: NSLocalizedString("Memori terpakai %d%% — tutup aplikasi yang tidak digunakan untuk meredakan tekanan memori.", comment: ""),
                percent
            )
        case .diskLow(let percent):
            return String(
                format: NSLocalizedString("Ruang disk tersisa %d%% — ruang yang sangat terbatas mulai memengaruhi performa.", comment: ""),
                percent
            )
        case .allHealthy:
            return NSLocalizedString("Tidak ditemukan penyebab kelambanan saat ini. Sistem dalam kondisi baik.", comment: "")
        }
    }

    // MARK: Modul yang belum jalan

    private var comingSoon: some View {
        EmptyStateView(
            symbol: module.symbol,
            title: NSLocalizedString("Segera tersedia", comment: ""),
            message: module.summary
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: Baris faktor (dipakai beberapa modul)

    private func factorRow(label: String, fraction: Double, value: String, note: String? = nil) -> some View {
        VStack(spacing: DKSpacing.xs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value).font(.dkData(12))
                if let note {
                    Text("· \(note)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            UsageBar(fraction: fraction, color: fraction >= 0.85 ? DKColor.attention : DKColor.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var thermalRow: some View {
        HStack {
            Text(NSLocalizedString("Thermal", comment: "")).font(.callout)
            Spacer()
            Text(thermalText)
                .font(.dkData(12))
                .foregroundColor(model.snapshot.thermalState == .nominal ? Color.primary : DKColor.attention)
            Text("· \(weightLabel(25))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func weightLabel(_ weight: Int) -> String {
        String(format: NSLocalizedString("bobot %d%%", comment: ""), weight)
    }

    private var thermalText: String {
        switch model.snapshot.thermalState {
        case .nominal: return NSLocalizedString("Nominal — tanpa throttling", comment: "")
        case .fair: return NSLocalizedString("Fair — suhu meninggi", comment: "")
        case .serious: return NSLocalizedString("Serious — throttling aktif", comment: "")
        case .critical: return NSLocalizedString("Critical", comment: "")
        @unknown default: return "?"
        }
    }

    private func bandColor(_ band: HealthScore.Band) -> Color {
        switch band {
        case .neutral: return DKColor.accent
        case .attention: return DKColor.attention
        case .critical: return DKColor.irreversible
        }
    }

    private func bandLabel(_ band: HealthScore.Band) -> String {
        switch band {
        case .neutral: return NSLocalizedString("Sehat", comment: "")
        case .attention: return NSLocalizedString("Perlu perhatian", comment: "")
        case .critical: return NSLocalizedString("Perlu tindakan", comment: "")
        }
    }

    private func headline(_ band: HealthScore.Band) -> String {
        switch band {
        case .neutral:
            return NSLocalizedString("Semua indikator utama dalam kondisi baik.", comment: "")
        case .attention:
            return NSLocalizedString("Satu atau lebih indikator mulai mendekati batas wajar. Periksa faktor penyusun di bawah.", comment: "")
        case .critical:
            return NSLocalizedString("Beberapa indikator berada di tingkat kritis. Periksa faktor penyusun — biasanya satu tindakan cukup untuk memperbaikinya.", comment: "")
        }
    }
}

// MARK: - Halaman Dukungan

/// Modul biasa (row selection kayak modul lain — rendering dijamin identik),
/// isinya ucapan terima kasih + tombol ke Ko-fi.
private struct DonationDetailView: View {
    var body: some View {
        VStack(spacing: DKSpacing.lg) {
            Image(systemName: "heart.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(DKColor.accent)
                .frame(width: 72, height: 72)
                .background(DKColor.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            Text(NSLocalizedString("Respite gratis. Selamanya.", comment: ""))
                .font(.title2.weight(.semibold))
            Text(NSLocalizedString("Tanpa langganan, tanpa fitur terkunci, tanpa iklan, tanpa telemetri — semua proses berjalan di Mac kamu.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            VStack(spacing: DKSpacing.xs) {
                Text(NSLocalizedString("Bayar sekali, sesukamu", comment: ""))
                    .font(.headline)
                Text(NSLocalizedString("Kalau Respite membantu, dukung pengembangannya satu kali dengan nominal berapa pun.", comment: ""))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(DKSpacing.lg)
            .frame(maxWidth: 440)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))

            Button {
                NSWorkspace.shared.open(DonationConfig.donationURL)
            } label: {
                Label(NSLocalizedString("Bayar Sekali", comment: ""), systemImage: "heart")
                    .frame(maxWidth: 240)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Text(NSLocalizedString("Sekali bayar bukan langganan — tidak ada tagihan berulang, tidak ada data pembayaran yang disimpan Respite.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ring Health Score// MARK: - Ring Health Score

/// Ring kecil (bukan gauge raksasa ala CleanMyMac) — angka di tengah,
/// warna band. Tanpa animasi: angka update instan (Design Spec §6).
private struct HealthRing: View {
    let score: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.dkData(30, weight: .semibold))
                    .foregroundColor(color)
                Text(NSLocalizedString("dari 100", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score) dari 100")
    }
}
