import XCTest
@testable import RespiteCore

final class HealthScoreTests: XCTestCase {
    func testSistemSehatSkorMaksimal() {
        let score = HealthScore.compute(
            memoryUsedFraction: 0.3,
            diskAvailableFraction: 0.5,
            thermalState: .nominal
        )
        XCTAssertEqual(score, 100)
    }

    func testSemuaBurukSkorNol() {
        let score = HealthScore.compute(
            memoryUsedFraction: 1.0,
            diskAvailableFraction: 0.05,
            thermalState: .critical
        )
        XCTAssertEqual(score, 0)
    }

    func testBobotCampuran() {
        // memori 50, disk 100, thermal fair 75 → 0.4·50 + 0.3·100 + 0.3·75 = 72.5 → 73
        let score = HealthScore.compute(
            memoryUsedFraction: 0.8,
            diskAvailableFraction: 0.25,
            thermalState: .fair
        )
        XCTAssertEqual(score, 73)
    }

    func testDenganInputCPU() {
        // Semua sehat + CPU ringan → 100.
        XCTAssertEqual(
            HealthScore.compute(
                memoryUsedFraction: 0.3,
                diskAvailableFraction: 0.5,
                thermalState: .nominal,
                cpuLoadFraction: 0.2
            ),
            100
        )
        // memori 50, disk 100, thermal 75, cpu 40
        // → 0.3·50 + 0.25·100 + 0.25·75 + 0.2·40 = 66.75 → 67
        XCTAssertEqual(
            HealthScore.compute(
                memoryUsedFraction: 0.8,
                diskAvailableFraction: 0.25,
                thermalState: .fair,
                cpuLoadFraction: 0.8
            ),
            67
        )
    }

    func testBatasBand() {
        XCTAssertEqual(HealthScore.Band.band(for: 70), .neutral)
        XCTAssertEqual(HealthScore.Band.band(for: 100), .neutral)
        XCTAssertEqual(HealthScore.Band.band(for: 69), .attention)
        XCTAssertEqual(HealthScore.Band.band(for: 40), .attention)
        XCTAssertEqual(HealthScore.Band.band(for: 39), .critical)
        XCTAssertEqual(HealthScore.Band.band(for: 0), .critical)
    }
}
