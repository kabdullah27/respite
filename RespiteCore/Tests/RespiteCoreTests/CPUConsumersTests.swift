import XCTest
@testable import RespiteCore

final class CPUConsumersTests: XCTestCase {
    private func sample(_ pid: Int32, _ name: String, _ time: UInt64) -> CPUConsumers.Sample {
        CPUConsumers.Sample(pid: pid, name: name, cpuTime: time)
    }

    func testDeltaDanGrouping() {
        let before = [
            sample(1, "Chrome Helper (Renderer)", 1000),
            sample(2, "Chrome Helper (Renderer)", 500),
            sample(3, "Xcode", 2000),
        ]
        let after = [
            sample(1, "Chrome Helper (Renderer)", 3000), // delta 2000
            sample(2, "Chrome Helper (Renderer)", 1000), // delta 500
            sample(3, "Xcode", 2100),                    // delta 100
        ]
        let groups = CPUConsumers.groups(from: before, to: after)

        XCTAssertEqual(groups.first?.name, "Chrome Helper (Renderer)")
        XCTAssertEqual(groups.first?.pids.sorted(), [1, 2])
        // Total delta 2600 → grup Chrome 2500/2600 ≈ 0.96.
        XCTAssertEqual(groups.first?.fraction ?? 0, 2500.0 / 2600.0, accuracy: 0.0001)
    }

    func testProsesBaruDiacuhkan() {
        // PID 9 baru muncul (nggak ada di sample sebelumnya) → nggak dihitung.
        let before = [sample(1, "A", 100)]
        let after = [sample(1, "A", 300), sample(9, "Baru", 999_999)]
        let groups = CPUConsumers.groups(from: before, to: after)
        XCTAssertEqual(groups.first?.name, "A")
        XCTAssertFalse(groups.contains { $0.name == "Baru" })
    }

    func testTanpaAktivitasKosong() {
        let before = [sample(1, "A", 100)]
        let after = [sample(1, "A", 100)]
        XCTAssertTrue(CPUConsumers.groups(from: before, to: after).isEmpty)
    }

    func testFilterBawahDibuang() {
        let before = [
            sample(1, "Big", 0),
            sample(2, "Tiny", 0),
        ]
        let after = [
            sample(1, "Big", 1000),
            sample(2, "Tiny", 10), // 10/1010 < 3% → dibuang
        ]
        let groups = CPUConsumers.groups(from: before, to: after)
        XCTAssertEqual(groups.map(\.name), ["Big"])
    }
}
