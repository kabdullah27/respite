import Foundation
import Darwin

/// Kumulatif tick CPU semua core sejak boot — didelta antar sample buat dapat
/// beban "sekarang".
public struct CPULoad: Sendable, Equatable {
    public let busy: UInt64   // user + system + nice
    public let total: UInt64  // busy + idle

    public init(busy: UInt64, total: UInt64) {
        self.busy = busy
        self.total = total
    }
}

public enum CPUSampler {
    /// Baca tick counter kernel via `host_processor_info` (API resmi, sama
    /// kayak yang dipakai Activity Monitor). Return nil kalau gagal baca.
    public static func sample() -> CPULoad? {
        var numCPUs: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &info, &infoCount)
        guard result == KERN_SUCCESS, let ticks = info, numCPUs > 0 else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: ticks)), size)
        }
        var busy: UInt64 = 0
        var idle: UInt64 = 0
        for core in 0..<Int(numCPUs) {
            let base = core * Int(CPU_STATE_MAX)
            busy += UInt64(ticks[base + Int(CPU_STATE_USER)])
                  + UInt64(ticks[base + Int(CPU_STATE_SYSTEM)])
                  + UInt64(ticks[base + Int(CPU_STATE_NICE)])
            idle += UInt64(ticks[base + Int(CPU_STATE_IDLE)])
        }
        return CPULoad(busy: busy, total: busy + idle)
    }

    /// Beban antara dua sample (0...1). Window-nya sejauh jarak antar sample
    /// (2 detik di SystemStatsModel) — cukup representatif buat display,
    /// rolling window 10 menit buat watchdog menyusul (TRD §4.11).
    public static func usageFraction(from previous: CPULoad, to current: CPULoad) -> Double? {
        guard current.total > previous.total else { return nil }
        let deltaBusy = current.busy > previous.busy ? current.busy - previous.busy : 0
        let deltaTotal = current.total - previous.total
        return min(1, Double(deltaBusy) / Double(deltaTotal))
    }
}
