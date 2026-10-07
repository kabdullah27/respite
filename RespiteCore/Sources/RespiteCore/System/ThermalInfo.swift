import Foundation

/// Detail thermal di luar 4-level enum (TRD §4.5.1): `pmset -g therm` punya
/// field `CPU_Speed_Limit` — di bawah 100% berarti CPU lagi di-throttle.
public enum ThermalInfo {
    /// Persen batas kecepatan CPU (100 = normal). Nilai via shell-out
    /// read-only `pmset -g therm`; nil kalau gagal.
    public static func cpuSpeedLimitPercent() -> Int? {
        guard let output = runPMSet() else { return nil }
        return parseSpeedLimit(output)
    }

    static func runPMSet() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "therm"]
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

    /// Pure — diuji unit test. Contoh baris: `CPU_Speed_Limit = 85`.
    public static func parseSpeedLimit(_ output: String) -> Int? {
        guard let range = output.range(
            of: #"CPU_Speed_Limit\s*=\s*(\d+)"#,
            options: .regularExpression
        ) else { return nil }
        let numbers = output[range].split(whereSeparator: { !$0.isNumber })
        guard let last = numbers.last else { return nil }
        return Int(last)
    }
}
