import Foundation

/// Hasil evaluasi Uptime Guardian — pure function, gampang di-test.
public struct UptimeVerdict: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case ok
        case sweepRecommended
    }

    public enum Reason: String, Equatable, Sendable {
        case longUptime
        case highSwap
        case lowMemory
    }

    public let kind: Kind
    public let reasons: [Reason]

    public init(kind: Kind, reasons: [Reason]) {
        self.kind = kind
        self.reasons = reasons
    }
}

/// Uptime Guardian (PRD §5.1) — trigger: uptime ≥ N hari **DAN**
/// (swap ≥ threshold **ATAU** memori tersedia < 10%). Threshold user-configurable.
public enum UptimeGuardian {
    public static let uptimeDaysKey = "app.respite.uptimeDays"
    public static let swapThresholdGBKey = "app.respite.swapThresholdGB"

    public static let defaultUptimeDays = 14
    public static let defaultSwapThresholdGB = 2

    public static func uptimeDaysThreshold(from defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: uptimeDaysKey)
        return value > 0 ? value : defaultUptimeDays
    }

    public static func swapThresholdBytes(from defaults: UserDefaults = .standard) -> UInt64 {
        let value = defaults.double(forKey: swapThresholdGBKey)
        let gb = value > 0 ? value : Double(defaultSwapThresholdGB)
        return UInt64(gb * 1_000_000_000)
    }

    public static func evaluate(
        uptime: TimeInterval,
        swapUsedBytes: UInt64,
        memoryAvailableFraction: Double,
        uptimeDays: Int = defaultUptimeDays,
        swapThresholdBytes: UInt64 = UInt64(defaultSwapThresholdGB) * 1_000_000_000
    ) -> UptimeVerdict {
        let longUptime = uptime >= Double(uptimeDays) * 86_400
        let highSwap = swapUsedBytes >= swapThresholdBytes
        let lowMemory = memoryAvailableFraction < 0.10

        guard longUptime, highSwap || lowMemory else {
            return UptimeVerdict(kind: .ok, reasons: [])
        }
        var reasons: [UptimeVerdict.Reason] = [.longUptime]
        if highSwap { reasons.append(.highSwap) }
        if lowMemory { reasons.append(.lowMemory) }
        return UptimeVerdict(kind: .sweepRecommended, reasons: reasons)
    }
}

/// Maintenance Sweep — versi tanpa privilege (TRD §4.5): cuma proses level
/// user yang auto-restart sendiri dalam hitungan detik. Langkah sistem-level
/// (purge memori, periodic scripts, restart daemon sistem) menyusul bareng
/// privileged helper — jangan dipaksa lewat shell hack.
public enum MaintenanceSweep {
    public struct FailedStep: Equatable, Sendable {
        public let name: String
        public let reason: String
    }

    public struct Outcome: Equatable, Sendable {
        public let restarted: [String]
        public let failed: [FailedStep]
    }

    /// Restart proses user-level via `killall` — macOS auto-relaunch mereka
    /// sendiri. Ledger dicatat SEBELUM eksekusi (TRD §7). Selalu tolak nama
    /// yang ada di ProtectedList (double-guard, meski UI nggak mesti ngasih).
    public static func restartProcesses(
        _ names: [String],
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> Outcome {
        var restarted: [String] = []
        var failed: [FailedStep] = []

        for name in names {
            guard !ProtectedList.criticalProcesses.contains(name) else { continue }
            SafetyLedger.record(
                LedgerEntry(
                    actionType: "restart-process",
                    target: name,
                    reversible: false,
                    detail: "Maintenance Sweep: restart \(name)"
                ),
                to: ledgerURL
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [name]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    restarted.append(name)
                } else {
                    failed.append(FailedStep(name: name, reason: "exit \(process.terminationStatus)"))
                }
            } catch {
                failed.append(FailedStep(name: name, reason: error.localizedDescription))
            }
        }
        return Outcome(restarted: restarted, failed: failed)
    }
}

/// Pengingat maintenance terjadwal — rising-edge dengan cooldown, pure
/// biar bisa diuji unit test. Dipakai SystemStatsModel tiap tick:
/// notifikasi hanya saat kondisi BARU memenuhi (bukan tiap evaluasi).
public enum MaintenanceReminder {
    public static func shouldNotify(
        previousNotified: Bool,
        recommendedNow: Bool,
        lastNotifiedAt: Date?,
        now: Date,
        cooldown: TimeInterval = 3_600
    ) -> Bool {
        guard recommendedNow, !previousNotified else { return false }
        if let last = lastNotifiedAt, now.timeIntervalSince(last) < cooldown {
            return false
        }
        return true
    }
}
