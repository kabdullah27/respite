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
    @State private var expandedSections: Set<ModuleSection> = Set(ModuleSection.allCases.filter(\.isExpandedByDefault))

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
        case .cleaning: return "externaldrive"
        case .monitoring: return "heart.text.square"
        case .misc: return "wrench.and.screwdriver"
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
                        title: NSLocalizedString("Pilih alat dari menu di kiri", comment: ""),
                        message: NSLocalizedString("Tidak ada yang dihapus tanpa persetujuanmu.", comment: "")
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
                Text(NSLocalizedString("Izin akses file", comment: ""))
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
                help: NSLocalizedString("Buka Pengaturan Sistem untuk memberi izin", comment: "")
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
            return NSLocalizedString("Diizinkan — semua folder bisa diperiksa", comment: "")
        case .some(false):
            return NSLocalizedString("Belum diizinkan — beberapa folder dilewati", comment: "")
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
            Text(NSLocalizedString("Masih mencari di:", comment: ""))
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
                format: NSLocalizedString("Mencari file besar — %d file · %@", comment: ""),
                largeFiles.hits.count,
                ByteFormat.string(from: largeFiles.scannedBytes)
            ))
            .font(.callout)
            .foregroundColor(.secondary)
            Spacer()
            Button(NSLocalizedString("Hentikan", comment: "")) {
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
        scrollingPage
    }

    private var scrollingPage: some View {
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
                    DiagnosticView(model: model)
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
                case .settings:
                    SettingsView(embedded: true)
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

    /// Judul halaman: nama alat + satu kalimat "alat ini buat apa".
    private var hero: some View {
        HStack(alignment: .center, spacing: DKSpacing.md) {
            Image(systemName: module.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(module.tintColor)
                .frame(width: 40, height: 40)
                .background(module.tintColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.title.weight(.bold))
                Text(module.summary)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
