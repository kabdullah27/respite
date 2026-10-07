import Foundation

/// Satu temuan diagnosis — kind-nya structured enum biar UI yang mindahin
/// ke teks ter-localize (core tetap UI-free, TRD §4.19).
public struct DiagnosticFinding: Identifiable, Sendable, Equatable {
    public enum Severity: Int, Sendable, Comparable, Equatable {
        case info = 0
        case attention = 1
        case critical = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public enum Kind: Sendable, Equatable {
        case thermalCritical
        case thermalFair
        case cpuHigh(percent: Int)
        case memoryPressure(percent: Int)
        case diskLow(percentAvailable: Int)
        case allHealthy
    }

    public let id: UUID
    public let kind: Kind
    public let severity: Severity

    public init(kind: Kind, severity: Severity) {
        self.id = UUID()
        self.kind = kind
        self.severity = severity
    }
}

/// Explanation engine "Diagnosis Performa" (TRD §4.5.2) — rule-based decision
/// tree, prioritas: (1) thermal paling severe & actionable, (2) CPU berat,
/// (3) tekanan memori, (4) disk kritis. Output maksimal 2 akar masalah.
///
/// Input CPU sebaiknya nilai yang udah dihaluskan (EMA di SystemStatsModel) —
/// spike sesaat nggak mau di-diagnosis sebagai "kelambanan".
public enum DiagnosticEngine {
    public static func diagnose(
        thermalState: ProcessInfo.ThermalState,
        cpuLoadFraction: Double?,
        memoryUsedFraction: Double,
        diskAvailableFraction: Double
    ) -> [DiagnosticFinding] {
        var findings: [DiagnosticFinding] = []

        if thermalState == .serious || thermalState == .critical {
            findings.append(DiagnosticFinding(kind: .thermalCritical, severity: .critical))
        } else if thermalState == .fair {
            findings.append(DiagnosticFinding(kind: .thermalFair, severity: .attention))
        }

        if let cpu = cpuLoadFraction, cpu >= 0.70 {
            findings.append(DiagnosticFinding(
                kind: .cpuHigh(percent: Int(cpu * 100)),
                severity: .attention
            ))
        }

        if memoryUsedFraction >= 0.80 {
            findings.append(DiagnosticFinding(
                kind: .memoryPressure(percent: Int(memoryUsedFraction * 100)),
                severity: memoryUsedFraction >= 0.92 ? .critical : .attention
            ))
        }

        if diskAvailableFraction <= 0.15 {
            findings.append(DiagnosticFinding(
                kind: .diskLow(percentAvailable: Int(diskAvailableFraction * 100)),
                severity: diskAvailableFraction <= 0.10 ? .critical : .attention
            ))
        }

        if findings.isEmpty {
            return [DiagnosticFinding(kind: .allHealthy, severity: .info)]
        }
        return Array(findings.sorted { $0.severity > $1.severity }.prefix(2))
    }
}
