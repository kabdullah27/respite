import Foundation
import Darwin

/// Jejak memori proses Respite sendiri — PRD G2: hemat RAM adalah janji
/// produk, jadi angkanya dibikin transparan di UI (bukan disembunyiin).
public enum SelfMemory {
    /// Physical footprint — metrik yang sama kayak kolom Memory di Activity
    /// Monitor (lebih jujur dari RSS yang menghitung shared pages).
    public static func footprintBytes() -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), 4, $0)
            }
        }
        guard result == 0 else { return 0 }
        return info.ri_phys_footprint
    }
}
