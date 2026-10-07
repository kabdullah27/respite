import XCTest
@testable import RespiteCore

final class RunawayWatchdogTests: XCTestCase {
    private let minute = 60.0

    private func samples(
        _ name: String, fraction: Double, minutes: Int, everySeconds: Int = 2, from: Date
    ) -> [WatchdogSample] {
        (0..<minutes * 60 / everySeconds).map { i in
            WatchdogSample(
                date: from.addingTimeInterval(Double(i * everySeconds)),
                name: name,
                fraction: fraction
            )
        }
    }

    func testSustainTinggiTerdeteksi() {
        let now = Date()
        let history = samples("Chrome Helper", fraction: 0.8, minutes: 10, from: now.addingTimeInterval(-10 * minute))
        let verdicts = RunawayWatchdog.evaluate(history: history, now: now)
        XCTAssertEqual(verdicts.first?.name, "Chrome Helper")
        XCTAssertEqual(verdicts.first?.averageFraction ?? 0, 0.8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(verdicts.first?.sustainedMinutes ?? 0, 9, "span data nyata ~10 menit")
    }

    func testSpikeSesaatTidakDilaporkan() {
        let now = Date()
        // Hanya 4 tick tinggi (8 detik) sisanya rendah → rata-rata jatuh.
        var history: [WatchdogSample] = samples("Exporter", fraction: 0.05, minutes: 10, from: now.addingTimeInterval(-10 * minute))
        for i in 0..<4 {
            history.append(WatchdogSample(
                date: now.addingTimeInterval(-Double(i * 2)),
                name: "Exporter",
                fraction: 0.9
            ))
        }
        XCTAssertTrue(RunawayWatchdog.evaluate(history: history, now: now).isEmpty)
    }

    func testIntermitenKurangCoverageTidakDilaporkan() {
        let now = Date()
        // Tinggi cuma di 40% tick → coverage 0.4 < 0.8, walau avg-nya tinggi.
        let history = (0..<300).map { i -> WatchdogSample in
            WatchdogSample(
                date: now.addingTimeInterval(Double((i - 300) * 2)),
                name: "OnOff",
                fraction: i % 5 < 2 ? 0.9 : 0.0
            )
        }
        XCTAssertTrue(RunawayWatchdog.evaluate(history: history, now: now).isEmpty)
    }

    func testDataTerlaluPendekDitunda() {
        let now = Date()
        let history = samples("Baru", fraction: 0.9, minutes: 1, from: now.addingTimeInterval(-minute))
        XCTAssertTrue(RunawayWatchdog.evaluate(history: history, now: now).isEmpty,
                      "butuh minimal 5 tick — jangan panik di 2 detik pertama")
    }

    func testJendelaLamaTerdibuang() {
        let now = Date()
        // Sustain 10 menit TAPI terjadi 30 menit lalu → sudah selesai.
        let history = samples("Dulu", fraction: 0.9, minutes: 10, from: now.addingTimeInterval(-40 * minute))
        XCTAssertTrue(RunawayWatchdog.evaluate(history: history, now: now).isEmpty)
    }
}
