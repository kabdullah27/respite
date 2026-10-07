import Foundation
import IOKit.ps

/// Respitean baterai internal (TRD §4.12.1) — via IOKit `IOPowerSources`
/// (publik, tanpa shell-out). `nil` = tidak ada baterai (Mac desktop) —
/// UI modul harus auto-hide untuk kasus itu.
public struct BatteryInfo: Sendable, Equatable {
    public let cycleCount: Int
    public let capacityPercent: Int
    public let isCharging: Bool
    /// "AC Power" / "Battery Power" / "Charging" / "Full" / "Discharging".
    public let powerState: String
    /// Kapasitas pengisian penuh vs kapasitas desain (indikator degradasi).
    /// `nil` kalau tidak tersedia.
    public let healthPercent: Int?

    public init(cycleCount: Int, capacityPercent: Int, isCharging: Bool, powerState: String, healthPercent: Int? = nil) {
        self.cycleCount = cycleCount
        self.capacityPercent = capacityPercent
        self.isCharging = isCharging
        self.powerState = powerState
        self.healthPercent = healthPercent
    }
}

public enum BatteryMonitor {
    /// Cache detail mahal (ioreg = spawn proses). Dulu read() menjalankan
    /// ioreg di TIAP tick 2 detik model statistik — untuk data (cycle count,
    /// kesehatan) yang paling cepat berubah harian. Sekarang: maksimal sekali
    /// per TTL; %/charging/state tetap segar tiap panggilan dari IOPS.
    /// static var aman — read() hanya dipanggil dari main actor.
    private static var detailCache: (at: Date, cycles: Int?, health: Int?)?
    private static let detailTTL: TimeInterval = 10 * 60

    /// Buat unit test — bersihkan cache antar kasus.
    static func resetDetailCache() {
        detailCache = nil
    }

    public static func read() -> BatteryInfo? {
        for desc in powerSourceDescriptions() {
            guard desc["Type"] as? String == "InternalBattery" else { continue }
            let current = desc["Current Capacity"] as? Int ?? 0
            let max = desc["Max Capacity"] as? Int ?? 0
            let charging = desc["Is Charging"] as? Bool ?? false
            let state = desc["Power Source State"] as? String ?? ""
            let ratio: Double = max > 0 ? Double(current) / Double(max) : 0.0

            let detail = cachedDetail(iopsCycles: desc["Cycle Count"] as? Int)

            return BatteryInfo(
                cycleCount: detail.cycles,
                capacityPercent: Int(ratio * 100.0),
                isCharging: charging,
                powerState: state,
                healthPercent: detail.health
            )
        }
        return nil
    }

    /// IOPS di sebagian mesin tidak menyediakan Cycle Count — fallback ke
    /// ioreg (TRD §4.12.1), plus health dari BatteryData — maks. 1×/TTL.
    private static func cachedDetail(iopsCycles: Int?) -> (cycles: Int, health: Int?) {
        if let cache = detailCache, Date().timeIntervalSince(cache.at) < detailTTL {
            return (cache.cycles ?? iopsCycles ?? 0, cache.health)
        }
        let output = runIOReg()
        let cycles = iopsCycles
            ?? output.flatMap(Self.parseCycleCount)
            ?? 0
        let health = output.flatMap(Self.parseHealthPercent)
        detailCache = (Date(), cycles, health)
        return (cycles, health)
    }

    static func runIOReg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "AppleSmartBattery"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    /// `"Cycle Count" = 330` ATAU `"CycleCount" = 330` (beda spasi antar mesin).
    static func parseCycleCount(_ output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\"Cycle Count\" =") || trimmed.hasPrefix("\"CycleCount\" =") {
                let numbers = trimmed.split(whereSeparator: { !$0.isNumber })
                if let last = numbers.last, let value = Int(last) {
                    return value
                }
            }
        }
        return nil
    }

    /// Dari BatteryData: FullChargeCapacity / DesignCapacity → persen.
    static func parseHealthPercent(_ output: String) -> Int? {
        guard let range = output.range(of: "BatteryData") else { return nil }
        let blob = String(output[range.lowerBound...])
        func value(named name: String) -> Int? {
            guard let r = blob.range(of: name + "\"=") else { return nil }
            let rest = blob[r.upperBound...].prefix(while: { $0.isNumber })
            return Int(rest)
        }
        guard let full = value(named: "FullChargeCapacity"),
              let design = value(named: "DesignCapacity"),
              design > 0
        else { return nil }
        return Int((Double(full) / Double(design)) * 100)
    }

    /// Bentuk blob beda antar versi macOS: array langsung, atau dict dengan
    /// key "Power Sources" yang isinya array. Dua-duanya didukung.
    static func powerSourceDescriptions() -> [[String: Any]] {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        if let array = blob as? [[String: Any]] {
            return array
        }
        if let dict = blob as? [String: Any],
           let sources = dict["Power Sources"] as? [[String: Any]] {
            return sources
        }
        return []
    }
}
