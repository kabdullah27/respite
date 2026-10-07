import XCTest
@testable import RespiteCore

final class DiagnosticEngineTests: XCTestCase {
    func testSemuaSehat() {
        let findings = DiagnosticEngine.diagnose(
            thermalState: .nominal,
            cpuLoadFraction: 0.2,
            memoryUsedFraction: 0.5,
            diskAvailableFraction: 0.4
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].kind, .allHealthy)
        XCTAssertEqual(findings[0].severity, .info)
    }

    func testThermalDidahulukan() {
        // Thermal paling parah → harus jadi temuan pertama.
        let findings = DiagnosticEngine.diagnose(
            thermalState: .serious,
            cpuLoadFraction: 0.9,
            memoryUsedFraction: 0.95,
            diskAvailableFraction: 0.05
        )
        XCTAssertEqual(findings.first?.kind, .thermalCritical)
        XCTAssertEqual(findings.first?.severity, .critical)
    }

    func testMaksimalDuaTemuan() {
        let findings = DiagnosticEngine.diagnose(
            thermalState: .fair,
            cpuLoadFraction: 0.85,
            memoryUsedFraction: 0.88,
            diskAvailableFraction: 0.12
        )
        XCTAssertLessThanOrEqual(findings.count, 2, "PRD: output 1-2 akar masalah saja")
    }

    func testCPURinganTidakDilaporkan() {
        let findings = DiagnosticEngine.diagnose(
            thermalState: .nominal,
            cpuLoadFraction: 0.4,
            memoryUsedFraction: 0.5,
            diskAvailableFraction: 0.5
        )
        XCTAssertEqual(findings[0].kind, .allHealthy)
    }

    func testNilaiCPUNullTidakCrash() {
        let findings = DiagnosticEngine.diagnose(
            thermalState: .nominal,
            cpuLoadFraction: nil,
            memoryUsedFraction: 0.85,
            diskAvailableFraction: 0.5
        )
        XCTAssertEqual(findings[0].kind, .memoryPressure(percent: 85))
        XCTAssertEqual(findings[0].severity, .attention)
    }
}
