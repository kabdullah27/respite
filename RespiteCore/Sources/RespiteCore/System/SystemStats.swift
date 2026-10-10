import Foundation
import Darwin

/// Statistik memori fisik — dibaca dari `host_statistics64` (API yang sama
/// dengan Activity Monitor). `used` = active + wired + compressed;
/// `available` = free + inactive (bisa di-reclaim tanpa swap).
public struct MemoryStats: Sendable, Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let availableBytes: UInt64

    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    public var availableFraction: Double {
        totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0
    }
}

/// Kapasitas volume boot — `volumeAvailableCapacityForImportantUsage`
/// konsisten dengan angka "Available" di Finder.
public struct DiskStats: Sendable, Equatable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    /// Ruang "purgeable" = yang bisa dibebaskan macOS sendiri saat dibutuhkan
    /// (cache sistem, snapshot lokal, dsb). Dihitung dari selisih
    /// available-for-important vs available sungguhan — 0 kalau tidak terbaca.
    /// DITAMPILKAN apa adanya, TIDAK PERNAH ditawarkan buat "dibersihkan"
    /// (kejujuran ala PureMac: tool pihak ketiga nggak bisa klaim purgeable).
    public let purgeableBytes: Int64

    public init(totalBytes: Int64, availableBytes: Int64, purgeableBytes: Int64 = 0) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
    }

    public var availableFraction: Double {
        totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0
    }
}

/// Pemakaian swap — `sysctl vm.swapusage` (PRD §5.1).
public struct SwapUsage: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

/// Satu sample titik-waktu dari semua data source read-only yang murah.
public struct SystemSnapshot: Sendable, Equatable {
    public let memory: MemoryStats
    public let disk: DiskStats
    public let uptime: TimeInterval
    public let thermalState: ProcessInfo.ThermalState
    public let swap: SwapUsage?

    public var healthScore: Int {
        HealthScore.compute(
            memoryUsedFraction: memory.usedFraction,
            diskAvailableFraction: disk.availableFraction,
            thermalState: thermalState
        )
    }
}

public enum SystemStats {
    /// Sekali saja — tiap mach_host_self() menambah ref send-right.
    static let hostPort = mach_host_self()

    /// Waktu boot menurut kernel — dibaca sekali, nggak berubah selama proses hidup.
    private static let bootDate: Date? = {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var tv = timeval()
        var size = UInt(MemoryLayout<timeval>.stride)
        guard sysctl(&mib, u_int(mib.count), &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }()

    /// Uptime jam dinding SEJAK BOOT, termasuk waktu sleep — ini yang dirasa
    /// user sebagai "berapa lama nggak restart" (PRD §5.1 pakai `kern.boottime`).
    /// `ProcessInfo.systemUptime` cuma akumulasi waktu BANGUN, jadi Mac yang
    /// sering sleep keliatan "baru 8 jam" padahal udah berhari-hari nyala.
    static func wallUptime() -> TimeInterval {
        if let bootDate {
            return max(0, Date().timeIntervalSince(bootDate))
        }
        return ProcessInfo.processInfo.systemUptime
    }

    static func swapUsage() -> SwapUsage? {
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        var usage = xsw_usage()
        var size = UInt(MemoryLayout<xsw_usage>.stride)
        guard sysctl(&mib, u_int(mib.count), &usage, &size, nil, 0) == 0 else { return nil }
        return SwapUsage(usedBytes: usage.xsu_used, totalBytes: usage.xsu_total)
    }

    /// Ambil snapshot baru. Non-failable: kalau salah satu sumber gagal dibaca,
    /// field-nya diisi 0 — UI tetap bisa render, debug lewat Logger.
    public static func snapshot() -> SystemSnapshot {
        SystemSnapshot(
            memory: memoryStats() ?? MemoryStats(totalBytes: 0, usedBytes: 0, availableBytes: 0),
            disk: diskStats() ?? DiskStats(totalBytes: 0, availableBytes: 0),
            uptime: wallUptime(),
            // Instance ProcessInfo BARU tiap kali — nilai thermalState di
            // instance shared (processInfo) bisa stale, terutama setelah Mac
            // bangun dari sleep (known gotcha; suka stuck di .fair).
            thermalState: ProcessInfo().thermalState,
            swap: swapUsage()
        )
    }

    static func memoryStats() -> MemoryStats? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutableBytes(of: &stats) { buffer -> kern_return_t in
            guard let base = buffer.bindMemory(to: integer_t.self).baseAddress else { return KERN_FAILURE }
            return host_statistics64(Self.hostPort, HOST_VM_INFO64, base, &count)
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * pageSize }
        let used = bytes(stats.active_count) + bytes(stats.wire_count) + bytes(stats.compressor_page_count)
        let available = bytes(stats.free_count) + bytes(stats.inactive_count)
        return MemoryStats(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            usedBytes: used,
            availableBytes: available
        )
    }

    static func diskStats(volumePath: String = "/") -> DiskStats? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? URL(fileURLWithPath: volumePath).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        let available = important > 0 ? important : plain
        // Purgeable = ruang yang cuma "available" kalau sistem boleh membuang
        // cache/snapshot-nya sendiri: important (termasuk purgeable) − plain.
        // Selisih bisa negatif di volume aneh → clamp.
        let purgeable = important > 0 ? max(0, important - plain) : 0
        return DiskStats(
            totalBytes: Int64(total),
            availableBytes: available,
            purgeableBytes: purgeable
        )
    }
}
