import Foundation
import ObjectiveC
import Darwin

/// Satu proses + jejak memorinya.
public struct ProcessMemory: Identifiable, Sendable, Equatable {
    public let pid: Int32
    public let name: String
    /// Physical footprint — metrik yang sama dipakai Activity Monitor
    /// buat kolom Memory (termasuk compressed memory).
    public let footprintBytes: UInt64

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, footprintBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.footprintBytes = footprintBytes
    }
}

/// Sekelompok proses bernama sama (Chrome Helper, Electron Helper, dst —
/// aplikasi modern spawn banyak instance). Dikelompokkan biar list-nya
/// manusiawi, bukan 8 baris identik.
public struct ProcessGroup: Identifiable, Sendable, Equatable {
    public let name: String
    public let pids: [Int32]
    public let totalFootprintBytes: UInt64

    public var id: String { name }

    public init(name: String, pids: [Int32], totalFootprintBytes: UInt64) {
        self.name = name
        self.pids = pids
        self.totalFootprintBytes = totalFootprintBytes
    }
}

/// Daftar proses pemakai memori terbesar via API publik `proc_pid_rusage`.
///
/// Catatan jujur: atribusi **swap per-proses** (ri_swap_usage) cuma ada di
/// API private Apple — yang bisa ditampilkan legal adalah physical footprint,
/// yaitu pemicu utama tekanan memori yang bikin macOS nulis swap.
/// Daftar semua PID. `proc_listallpids` minta ukuran buffer dalam BYTE —
/// dulu dikasih jumlah elemen (4096) → maksimal 1024 PID, sisanya hilang.
func allPIDs() -> [Int32] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
    let count = pids.withUnsafeMutableBytes { buffer in
        proc_listallpids(buffer.baseAddress, Int32(buffer.count))
    }
    guard count > 0 else { return [] }
    return Array(pids.prefix(Int(count)))
}

public enum TopProcesses {
    public static func byMemoryFootprint(
        limit: Int = 12,
        minBytes: UInt64 = 100_000_000
    ) -> [ProcessMemory] {
        let pids = allPIDs()
        let count = pids.count
        guard count > 0 else { return [] }

        var results: [ProcessMemory] = []
        for pid in pids where pid > 0 {
            autoreleasepool {
            var info = rusage_info_v4()
            // Flavor 4 = RUSAGE_INFO_4 (makronya nggak diekspor ke Swift).
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, 4, $0)
                }
            }
            guard result == 0, info.ri_phys_footprint >= minBytes else { return }

            var pathBuffer = [CChar](repeating: 0, count: 1024)
            let pathLength = proc_pidpath(pid, &pathBuffer, 1024)
            let name: String
            if pathLength > 0 {
                let fullPath = String(cString: pathBuffer)
                name = URL(fileURLWithPath: fullPath).lastPathComponent
            } else {
                name = "PID \(pid)"
            }
            results.append(ProcessMemory(pid: pid, name: name, footprintBytes: info.ri_phys_footprint))
            }
        }
        return Array(results.sorted { $0.footprintBytes > $1.footprintBytes }.prefix(limit))
    }

    /// Versi dikelompokkan per nama — threshold per-proses lebih rendah
    /// (helper kecil yang jumlahnya banyak tetap kelihatan sebagai grup gede).
    public static func groupedByMemoryFootprint(
        limit: Int = 10,
        minPerProcessBytes: UInt64 = 50_000_000,
        minGroupBytes: UInt64 = 150_000_000
    ) -> [ProcessGroup] {
        let all = byMemoryFootprint(limit: 10_000, minBytes: minPerProcessBytes)
        return group(all, minGroupBytes: minGroupBytes, limit: limit)
    }

    /// Pure — dipisah biar bisa di-unit-test dengan data sintetis.
    static func group(
        _ processes: [ProcessMemory],
        minGroupBytes: UInt64,
        limit: Int
    ) -> [ProcessGroup] {
        let byName = Dictionary(grouping: processes, by: \.name)
        return byName
            .map { name, members in
                ProcessGroup(
                    name: name,
                    pids: members.map(\.pid),
                    totalFootprintBytes: members.reduce(0) { $0 + $1.footprintBytes }
                )
            }
            .filter { $0.totalFootprintBytes >= minGroupBytes }
            .sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Pemakai CPU terbesar

/// Beban CPU per proses via delta WAKTU CPU (publik: `ri_user_time` +
/// `ri_system_time` dari `proc_pid_rusage`) antar dua sample — metrik yang
/// sama dengan kolom % CPU di Activity Monitor.
///
/// Catatan jujur: status "Not Responding" hanya bisa dibaca lewat API private
/// Apple — kalau app macet total, angkanya di sini justru turun ke 0%.
public enum CPUConsumers {
    public struct Sample: Sendable, Equatable {
        public let pid: Int32
        public let name: String
        /// Kumulatif waktu CPU (satuan apapun — delta-nya yang dipakai).
        public let cpuTime: UInt64

        public init(pid: Int32, name: String, cpuTime: UInt64) {
            self.pid = pid
            self.name = name
            self.cpuTime = cpuTime
        }
    }

    public struct Group: Identifiable, Sendable, Equatable {
        public let name: String
        public let pids: [Int32]
        /// Dengan `wallDelta`: fraksi SATU core (1.0 = 100% satu core, bisa
        /// >1 buat proses multi-thread — sama kayak Activity Monitor).
        /// Tanpa itu: porsi dari total CPU semua proses.
        public let fraction: Double

        public var id: String { name }
    }

    /// Jam monoton dalam satuan yang SAMA dengan `ri_user_time` (mach tick
    /// di Apple Silicon, ns di Intel) — delta-nya dipakai sebagai `wallDelta`.
    public static func clock() -> UInt64 { mach_absolute_time() }

    /// Ambil sample kumulatif semua proses (syscall murah per proses).
    public static func sample() -> [Sample] {
        let pids = allPIDs()
        let count = pids.count
        guard count > 0 else { return [] }

        var results: [Sample] = []
        for pid in pids where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, 4, $0)
                }
            }
            guard result == 0 else { continue }
            let cpuTime = info.ri_user_time + info.ri_system_time
            guard cpuTime > 0 else { continue }

            var pathBuffer = [CChar](repeating: 0, count: 1024)
            let pathLength = proc_pidpath(pid, &pathBuffer, 1024)
            let name: String
            if pathLength > 0 {
                name = URL(fileURLWithPath: String(cString: pathBuffer)).lastPathComponent
            } else {
                name = "PID \(pid)"
            }
            results.append(Sample(pid: pid, name: name, cpuTime: cpuTime))
        }
        return results
    }

    /// Grouping pure — diuji unit test. Delta waktu CPU antar dua sample
    /// dibagi total delta semua proses = persentase window.
    public static func groups(
        from previous: [Sample],
        to current: [Sample],
        minFraction: Double = 0.03,
        limit: Int = 8,
        wallDelta: UInt64? = nil
    ) -> [Group] {
        let prevByPID = Dictionary(uniqueKeysWithValues: previous.map { ($0.pid, $0.cpuTime) })
        let nameByPID = Dictionary(current.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })

        var deltas: [(pid: Int32, delta: UInt64)] = []
        var totalDelta: UInt64 = 0
        for currentSample in current {
            guard let prevTime = prevByPID[currentSample.pid] else { continue }
            guard currentSample.cpuTime > prevTime else { continue }
            let delta = currentSample.cpuTime - prevTime
            deltas.append((currentSample.pid, delta))
            totalDelta += delta
        }
        guard totalDelta > 0 else { return [] }
        // Porsi relatif bikin Mac idle kelihatan "sibuk": WindowServer pakai
        // 1% satu core tapi dapat 0.6 karena yang lain ~0. Normalisasi ke
        // waktu dinding kalau tersedia.
        let denominator = wallDelta.map { max($0, 1) } ?? totalDelta

        let byName = Dictionary(grouping: deltas) { nameByPID[$0.pid] ?? "PID \($0.pid)" }
        return byName
            .map { name, members in
                Group(
                    name: name,
                    pids: members.map(\.pid),
                    fraction: Double(members.reduce(0) { $0 + $1.delta }) / Double(denominator)
                )
            }
            .filter { $0.fraction >= minFraction }
            .sorted { $0.fraction > $1.fraction }
            .prefix(limit)
            .map { $0 }
    }
}
