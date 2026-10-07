import Foundation

/// Health Score 0-100 — deterministic & stateless (TRD §4.5.2): weighted formula
/// dari input yang bisa dijelasin, bukan model yang "belajar".
///
/// Dengan input CPU: memori 30%, disk 25%, thermal 25%, CPU 20%.
/// Tanpa input CPU (belum ada dua sample): bobot lama dinormalisasi sendiri —
/// memori 40%, disk 30%, thermal 30%.
public enum HealthScore {
    /// Band warna sesuai Design Spec §2: 70-100 netral, 40-69 amber, <40 merah.
    /// Merah cuma buat display — nggak pernah nge-trigger aksi otomatis.
    public enum Band: Sendable {
        case neutral
        case attention
        case critical

        public static func band(for score: Int) -> Band {
            switch score {
            case 70...: return .neutral
            case 40..<70: return .attention
            default: return .critical
            }
        }
    }

    public static func compute(
        memoryUsedFraction: Double,
        diskAvailableFraction: Double,
        thermalState: ProcessInfo.ThermalState,
        cpuLoadFraction: Double? = nil
    ) -> Int {
        let memoryScore = componentScore(forPressure: (memoryUsedFraction - 0.60) / 0.40)
        // Disk: lega di >=25% available, habis di <=10% — di bawah itu macOS
        // mulai agresif compress + swap, itu yang kerasa lambat.
        let diskScore = componentScore(forPressure: (0.25 - diskAvailableFraction) / 0.15)
        let thermalScore: Double
        switch thermalState {
        case .nominal: thermalScore = 100
        case .fair: thermalScore = 75
        case .serious: thermalScore = 40
        case .critical: thermalScore = 0
        @unknown default: thermalScore = 100
        }

        let total: Double
        if let cpu = cpuLoadFraction {
            // CPU: beban di bawah 50% dianggap sehat; di atasnya menekan skor.
            let cpuScore = componentScore(forPressure: (cpu - 0.50) / 0.50)
            total = 0.30 * memoryScore + 0.25 * diskScore + 0.25 * thermalScore + 0.20 * cpuScore
        } else {
            total = 0.40 * memoryScore + 0.30 * diskScore + 0.30 * thermalScore
        }
        return Int(total.rounded())
    }

    /// Map "seberapa parah" (0 = aman, 1 = maksimal) ke skor komponen 0-100.
    /// Nilai negatif (lebih aman dari threshold) di-clamp ke 100.
    private static func componentScore(forPressure pressure: Double) -> Double {
        max(0, min(1, pressure)).inverted() * 100
    }
}

private extension Double {
    func inverted() -> Double { 1 - self }
}
