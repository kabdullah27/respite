import XCTest
@testable import RespiteCore

final class ProcessKillerTests: XCTestCase {
    func testProsesKritisDitolakSebelumEksekusi() {
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }

        // PID 1 = launchd — kalau guard-nya bolong, test ini bakal ngerusak
        // sistem. Guard HARUS nolak duluan.
        let outcome = ProcessKiller.terminate(pid: 1, name: "launchd", ledgerURL: ledgerURL)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.rawReason, "protected-process")
        XCTAssertTrue(SafetyLedger.load(from: ledgerURL).isEmpty, "aksi yang ditolak nggak boleh tercatat")
    }

    func testPIDFiktifGagalRapi() {
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }

        let outcome = ProcessKiller.terminate(pid: 999_999, name: "ProsesFiktif", ledgerURL: ledgerURL)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertFalse(outcome.rawReason.isEmpty)
        // Percobaan yang dieksekusi (walau gagal) tetap tercatat — jejak aksi.
        XCTAssertEqual(SafetyLedger.load(from: ledgerURL).count, 1)
    }
}

final class ProcessGroupingTests: XCTestCase {
    private func proc(_ name: String, _ pid: Int32, _ bytes: UInt64) -> ProcessMemory {
        ProcessMemory(pid: pid, name: name, footprintBytes: bytes)
    }

    func testHelperSejenisDigabung() {
        let input = [
            proc("Chrome Helper (Renderer)", 101, 60_000_000),
            proc("Chrome Helper (Renderer)", 102, 80_000_000),
            proc("Chrome Helper (Renderer)", 103, 70_000_000),
            proc("AplikasiBiasa", 200, 500_000_000),
            proc("KecilTakSignifikan", 300, 30_000_000),
        ]
        let groups = TopProcesses.group(input, minGroupBytes: 150_000_000, limit: 10)

        // Tiga helper digabung jadi satu grup 210 MB, tepat di bawah app 500 MB.
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].name, "AplikasiBiasa")
        XCTAssertEqual(groups[1].name, "Chrome Helper (Renderer)")
        XCTAssertEqual(groups[1].pids, [101, 102, 103])
        XCTAssertEqual(groups[1].totalFootprintBytes, 210_000_000)
    }

    func testGrupKecilTerfilter() {
        let input = [
            proc("Mini", 1, 60_000_000),
            proc("Mini", 2, 60_000_000),  // total 120 MB < 150 MB → nggak tampil
        ]
        let groups = TopProcesses.group(input, minGroupBytes: 150_000_000, limit: 10)
        XCTAssertTrue(groups.isEmpty)
    }
}

final class ThermalInfoTests: XCTestCase {
    func testParseSpeedLimit() {
        XCTAssertEqual(ThermalInfo.parseSpeedLimit("CPU_Speed_Limit = 100"), 100)
        XCTAssertEqual(ThermalInfo.parseSpeedLimit("blah\nCPU_Speed_Limit = 85.0\n"), 85)
        XCTAssertNil(ThermalInfo.parseSpeedLimit("kepotong"))
    }

    func testClearLedger() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        SafetyLedger.record(
            LedgerEntry(actionType: "x", target: "/tmp/a", reversible: true, detail: "t"),
            to: fileURL
        )
        XCTAssertEqual(SafetyLedger.load(from: fileURL).count, 1)
        SafetyLedger.clear(to: fileURL)
        XCTAssertTrue(SafetyLedger.load(from: fileURL).isEmpty)
    }
}

final class ReportExporterTests: XCTestCase {
    func testCSVHeaderDanEscaping() {
        let entries = [
            LedgerEntry(actionType: "move-to-trash", target: "/tmp/ber\"koma, file", timestamp: Date(timeIntervalSince1970: 0), reversible: true, detail: "Smart Scan: A · 1,2 GB"),
        ]
        let csv = ReportExporter.csv(from: entries)
        XCTAssertTrue(csv.hasPrefix("timestamp,action,target,reversible,detail"))
        XCTAssertTrue(csv.contains("\"/tmp/ber\"\"koma, file\""), "kutip & koma harus di-escape")
        XCTAssertTrue(csv.contains(",yes,"))
    }

    func testJSONRoundtrip() throws {
        let entries = [
            LedgerEntry(actionType: "kill-process", target: "X (PID 1)", timestamp: Date(), reversible: false, detail: "test"),
        ]
        let data = try XCTUnwrap(ReportExporter.jsonData(from: entries))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode([LedgerEntry].self, from: data).count, 1)
    }
}
