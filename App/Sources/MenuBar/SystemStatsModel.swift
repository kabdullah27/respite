import Combine
import Foundation
import AppKit
import RespiteCore

/// Sumber data live buat menu bar & dashboard. Interval 2 detik pakai Timer
/// ringan (TRD §4.4) — bukan DispatchSourceTimer, ini cuma buat display.
/// CPU dihitung dari delta tick antar refresh, jadi nilainya baru ada
/// mulai refresh kedua.
@MainActor
final class SystemStatsModel: ObservableObject {
    /// Satu instance dipakai menu bar + dashboard (sumber data yang sama,
    /// satu timer) — dibuat pas pertama diakses dari main thread.
    static let shared = SystemStatsModel()

    @Published private(set) var snapshot: SystemSnapshot
    @Published private(set) var cpuUsageFraction: Double?
    /// CPU yang dihaluskan (EMA) — buat Health Score & diagnosis biar spike
    /// sesaat nggak menggelembungkan angka.
    @Published private(set) var smoothedCPUFraction: Double?
    /// Jejak memori Respite sendiri (PRD G2) — ditampilkan jujur di UI.
    @Published private(set) var ownFootprintBytes: UInt64 = 0
    /// Pemakai CPU terbesar (delta antar tick) — live tiap 2 detik.
    @Published private(set) var topCPUGroups: [CPUConsumers.Group] = []
    /// Baterai (nil di Mac desktop — modul auto-hide).
    @Published private(set) var battery: BatteryInfo?
    /// Suhu CPU (°C) dari sensor SMC — nil kalau mesin mengunci sensornya
    /// (umum di Apple Silicon modern). Back-off: mesin yang terkunci
    /// di-cek ulang tiap 15 tick (30 dtk), bukan tiap 2 dtk.
    @Published private(set) var cpuCelsius: Double?
    private var celsiusMissStreak = 0
    private var hiddenTick = 0
    /// Proses liar (CPU tinggi sustain) — diisi watchdog tiap tick.
    @Published private(set) var runaway: [RunawayVerdict] = []
    /// Scheduled Maintenance in-app (P1): selama Respite berjalan, kondisi
    /// Uptime Guardian dievaluasi terus — notifikasi rising-edge + cooldown.
    @Published var scheduledMaintenanceEnabled: Bool {
        didSet { UserDefaults.standard.set(scheduledMaintenanceEnabled, forKey: Self.scheduleKey) }
    }

    /// Bobot sampel baru pada EMA — 0.3: cukup responsif tanpa ikut spike.
    private let cpuSmoothing: Double = 0.3

    private var timerCancellable: AnyCancellable?
    private var wakeCancellable: AnyCancellable?
    private var lifetimeCancellables: [AnyCancellable] = []
    private var previousCPULoad: CPULoad?
    private var previousCPUSample: [CPUConsumers.Sample] = []
    private var previousCPUSampleClock: UInt64 = 0
    private var watchdogHistory: [WatchdogSample] = []
    private var notifiedRunawayNames: Set<String> = []
    private var sweepNotified = false
    private var sweepLastNotifiedAt: Date?

    static let scheduleKey = "app.respite.scheduledMaintenance.enabled"

    init() {
        scheduledMaintenanceEnabled = UserDefaults.standard.bool(forKey: Self.scheduleKey)
        self.snapshot = SystemStats.snapshot()
        self.previousCPULoad = CPUSampler.sample()
        self.cpuUsageFraction = nil
        self.smoothedCPUFraction = nil
        // Run loop mode .common biar tetap update pas menu bar dropdown lagi
        // kebuka (mode tracking), bukan cuma pas idle.
        timerCancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
        // Bangun dari sleep: thermal & uptime langsung dicek ulang —
        // nilainya paling sering stale tepat setelah wake.
        // didWakeNotification HANYA diposting di notification center NSWorkspace.
        wakeCancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.refresh()
            }
        // Window dibuka / popover menu bar muncul → data langsung segar
        // (selama hidden kita skip refresh).
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshNow()
            }
            .store(in: &lifetimeCancellables)
        NotificationCenter.default
            .publisher(for: NSPopover.didShowNotification)
            .sink { [weak self] _ in
                self?.refreshNow()
            }
            .store(in: &lifetimeCancellables)
        previousCPUSample = CPUConsumers.sample()
        previousCPUSampleClock = CPUConsumers.clock()
    }

    /// Health Score dengan CPU terhaluskan sebagai input keempat.
    var healthScore: Int {
        HealthScore.compute(
            memoryUsedFraction: snapshot.memory.usedFraction,
            diskAvailableFraction: snapshot.disk.availableFraction,
            thermalState: snapshot.thermalState,
            cpuLoadFraction: smoothedCPUFraction
        )
    }

    /// Temuan diagnosis saat ini (rule-based, TRD §4.5.2).
    var diagnosticFindings: [DiagnosticFinding] {
        DiagnosticEngine.diagnose(
            thermalState: snapshot.thermalState,
            cpuLoadFraction: smoothedCPUFraction,
            memoryUsedFraction: snapshot.memory.usedFraction,
            diskAvailableFraction: snapshot.disk.availableFraction
        )
    }

    /// Paksa refresh sekarang (dipanggil tombol Segarkan di UI).
    func refreshNow() {
        refresh()
    }

    /// Watchdog in-app (TRD §4.11): rolling window 10 menit; notif sekali
    /// per kejadian sampai kondisi beres. Versi launchd-agent menyusul.
    private func updateWatchdog(now: Date) {
        watchdogHistory += topCPUGroups.map {
            WatchdogSample(date: now, name: $0.name, fraction: $0.fraction)
        }
        watchdogHistory.removeAll { $0.date < now.addingTimeInterval(-12 * 60) }

        let verdicts = RunawayWatchdog.evaluate(history: watchdogHistory, now: now)
        runaway = verdicts

        for verdict in verdicts where !notifiedRunawayNames.contains(verdict.name) {
            notifiedRunawayNames.insert(verdict.name)
            Notifier.post(
                title: NSLocalizedString("Ada aplikasi yang bekerja terlalu keras", comment: ""),
                body: String(
                    format: NSLocalizedString(
                        "%1$@ memakai banyak tenaga prosesor (rata-rata %2$d%%) selama ±%3$d menit. Buka Respite → Aplikasi Berat untuk melihat atau menutupnya.",
                        comment: ""
                    ),
                    verdict.name,
                    Int(verdict.averageFraction * 100),
                    Int(verdict.sustainedMinutes)
                )
            )
        }
        // Yang sudah beres boleh dinotifikasi lagi lain waktu.
        notifiedRunawayNames.formIntersection(Set(verdicts.map(\.name)))
        updateScheduledMaintenance(now: now)
    }

    /// Scheduled Maintenance: evaluasi verdict sweep + notifikasi sekali
    /// per kejadian (rising-edge, cooldown 1 jam).
    private func updateScheduledMaintenance(now: Date) {
        guard scheduledMaintenanceEnabled else {
            sweepNotified = false
            return
        }
        let verdict = UptimeGuardian.evaluate(
            uptime: snapshot.uptime,
            swapUsedBytes: snapshot.swap?.usedBytes ?? 0,
            memoryAvailableFraction: snapshot.memory.availableFraction,
            uptimeDays: UptimeGuardian.uptimeDaysThreshold(),
            swapThresholdBytes: UptimeGuardian.swapThresholdBytes()
        )
        let recommended = verdict.kind == .sweepRecommended
        if MaintenanceReminder.shouldNotify(
            previousNotified: sweepNotified,
            recommendedNow: recommended,
            lastNotifiedAt: sweepLastNotifiedAt,
            now: now
        ) {
            sweepNotified = true
            sweepLastNotifiedAt = now
            Notifier.post(
                title: NSLocalizedString("Mac kamu perlu disegarkan", comment: ""),
                body: String(
                    format: NSLocalizedString(
                        "Mac sudah lama menyala dan memorinya mulai penuh. Buka Respite → Aplikasi Berat untuk menyegarkannya tanpa restart.",
                        comment: ""
                    )
                )
            )
        }
        if !recommended {
            sweepNotified = false
        }
    }

    /// Ada main window terlihat ATAU popover/panel menu bar terbuka?
    private var anythingVisible: Bool {
        NSApp.windows.contains { window in
            window.isVisible && (window.canBecomeMain || window is NSPanel)
        }
    }

    private func refreshCelsiusIfNeeded() {
        // Mesin terkunci: coba ulang tiap 15 tick (jangan spam syscall).
        // Streak tetap naik saat di-skip — kalau nggak, nyangkut di 3 dan
        // sensor nggak pernah dicek ulang.
        if celsiusMissStreak >= 3 {
            celsiusMissStreak += 1
            if celsiusMissStreak % 15 != 0 { return }
        }
        if let c = SMCReader.cpuCelsius() {
            cpuCelsius = c
            celsiusMissStreak = 0
        } else {
            cpuCelsius = nil
            celsiusMissStreak += 1
        }
    }

    private func refresh() {
        // Hemat CPU (profil 2026-09-25: 5.2% rata-rata — layout SwiftUI
        // dominan, bukan pengukuran): kalau TIDAK ADA tampilan yang terlihat
        // (main window hidden + popover tertutup), refresh cuma tiap 15 tick
        // = 30 dtk. Tetap ambil sample BARU — skor menu bar, watchdog, dan
        // Uptime Guardian butuh data segar justru saat app di background
        // (dulu watchdog mengulang data CPU beku → notifikasi runaway palsu).
        let visible = anythingVisible
        if !visible {
            hiddenTick += 1
            guard hiddenTick % 15 == 0 else { return }
        }
        snapshot = SystemStats.snapshot()
        if visible {
            ownFootprintBytes = SelfMemory.footprintBytes()
            battery = BatteryMonitor.read()
            refreshCelsiusIfNeeded()
        }
        sampleCPU()
        updateWatchdog(now: Date())
    }

    private func sampleCPU() {
        let clock = CPUConsumers.clock()
        let cpuSample = CPUConsumers.sample()
        // Normalisasi ke waktu dinding → fraksi satu core (bukan porsi
        // relatif antar proses, yang bikin Mac idle tampak "sibuk").
        let wallDelta = clock > previousCPUSampleClock ? clock - previousCPUSampleClock : nil
        topCPUGroups = CPUConsumers.groups(from: previousCPUSample, to: cpuSample, wallDelta: wallDelta)
        previousCPUSample = cpuSample
        previousCPUSampleClock = clock

        if let current = CPUSampler.sample() {
            if let previous = previousCPULoad {
                let instant = CPUSampler.usageFraction(from: previous, to: current)
                cpuUsageFraction = instant
                if let instant {
                    smoothedCPUFraction = smoothedCPUFraction
                        .map { $0 * (1 - cpuSmoothing) + instant * cpuSmoothing }
                        ?? instant
                }
            }
            previousCPULoad = current
        }
    }
}
