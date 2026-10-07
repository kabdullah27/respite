import XCTest
import SQLite3
@testable import RespiteCore

final class TimeMachineSnapshotTests: XCTestCase {
    func testParseOutput() {
        let output = """
        Snapshots for volume group "com.apple.APFSVolumeGroup.X":
        com.apple.TimeMachine.2024-01-15-101010.local
        com.apple.TimeMachine.2024-01-14-020304.local
        ========
        """
        let snapshots = TimeMachineSnapshots.parse(output)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].timestamp, "2024-01-15-101010")
        XCTAssertEqual(snapshots[0].id, "com.apple.TimeMachine.2024-01-15-101010.local")
    }

    func testParseOutputKosong() {
        XCTAssertTrue(TimeMachineSnapshots.parse("Snapshots for disk '/': (none)").isEmpty)
        XCTAssertTrue(TimeMachineSnapshots.parse("").isEmpty)
    }
}

final class PrivacyAuditTests: XCTestCase {
    /// Bikin fixture TCC.db beneran via SQLite C API.
    private func makeFixtureDB() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-tcc-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        var error: UnsafeMutablePointer<CChar>?
        _ = sqlite3_exec(db, """
        CREATE TABLE access(service TEXT NOT NULL, client TEXT NOT NULL, auth_value INTEGER);
        INSERT INTO access VALUES ('kTCCServiceCamera', 'com.vendor.a', 2);
        INSERT INTO access VALUES ('kTCCServiceCamera', 'com.vendor.b', 0);
        INSERT INTO access VALUES ('kTCCServiceSystemPolicyAllFiles', 'com.vendor.a', 2);
        """, nil, nil, &error)
        sqlite3_close(db)
        return url
    }

    func testBacaEntriDanStatus() throws {
        let dbURL = try makeFixtureDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let result = PrivacyAudit.list(dbURL: dbURL)
        XCTAssertTrue(result.readable)
        XCTAssertEqual(result.entries.count, 3)

        let allowed = result.entries.first { $0.client == "com.vendor.a" && $0.service == "kTCCServiceCamera" }
        XCTAssertEqual(allowed?.allowed, true)
        let denied = result.entries.first { $0.client == "com.vendor.b" }
        XCTAssertEqual(denied?.allowed, false)
    }

    func testDBHilangTidakCrash() {
        let result = PrivacyAudit.list(dbURL: URL(fileURLWithPath: "/tmp/tidak-ada-\(UUID().uuidString).db"))
        XCTAssertFalse(result.readable)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testNamaService() {
        XCTAssertEqual(PrivacyAudit.serviceName("kTCCServiceCamera"), "Kamera")
        XCTAssertEqual(PrivacyAudit.serviceName("kTCCServiceSystemPolicyAllFiles"), "Akses Disk Penuh")
        XCTAssertEqual(PrivacyAudit.serviceName("kTCCServiceMisterius"), "kTCCServiceMisterius")
    }
}

final class BatteryParserTests: XCTestCase {
    let sample = [
        "+-o AppleSmartBattery  <class AppleSmartBattery>",
        "    \"ExternalConnected\" = No",
        "      \"CycleCount\" = 330",
        "    \"BatteryData\" = {\"FullChargeCapacity\"=4141,\"DesignCapacity\"=4629,\"CurrentCapacity\"=65}",
        "    \"FullyCharged\" = No",
    ].joined(separator: "\n")

    func testParseCycleCountDuaFormat() {
        XCTAssertEqual(BatteryMonitor.parseCycleCount(sample), 330)
        let spasi = "  \"Cycle Count\" = 12"
        XCTAssertEqual(BatteryMonitor.parseCycleCount(spasi), 12)
        XCTAssertNil(BatteryMonitor.parseCycleCount("tidak ada"))
    }

    func testParseHealthPercent() {
        XCTAssertEqual(BatteryMonitor.parseHealthPercent(sample) ?? 0, 89)
        XCTAssertNil(BatteryMonitor.parseHealthPercent("kosong"))
    }
}
