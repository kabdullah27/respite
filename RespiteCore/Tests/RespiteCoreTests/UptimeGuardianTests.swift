import XCTest
@testable import RespiteCore

final class UptimeGuardianTests: XCTestCase {
    private let day = 86_400.0

    func testUptimePendekSelaluOk() {
        // Swap gede pun, kalau uptime belum lama → belum perlu sweep.
        let verdict = UptimeGuardian.evaluate(
            uptime: 2 * day,
            swapUsedBytes: 8_000_000_000,
            memoryAvailableFraction: 0.4
        )
        XCTAssertEqual(verdict.kind, .ok)
    }

    func testUptimeLamaDanSwapTinggi() {
        let verdict = UptimeGuardian.evaluate(
            uptime: 20 * day,
            swapUsedBytes: 3_000_000_000,
            memoryAvailableFraction: 0.4
        )
        XCTAssertEqual(verdict.kind, .sweepRecommended)
        XCTAssertEqual(verdict.reasons, [.longUptime, .highSwap])
    }

    func testUptimeLamaDanMemoriTipis() {
        let verdict = UptimeGuardian.evaluate(
            uptime: 15 * day,
            swapUsedBytes: 100_000_000,
            memoryAvailableFraction: 0.05
        )
        XCTAssertEqual(verdict.kind, .sweepRecommended)
        XCTAssertEqual(verdict.reasons, [.longUptime, .lowMemory])
    }

    func testUptimeLamaTapiKondisiSehat() {
        let verdict = UptimeGuardian.evaluate(
            uptime: 30 * day,
            swapUsedBytes: 0,
            memoryAvailableFraction: 0.5
        )
        XCTAssertEqual(verdict.kind, .ok)
    }

    func testBatasTepat14Hari() {
        let verdict = UptimeGuardian.evaluate(
            uptime: 14 * day,
            swapUsedBytes: 5_000_000_000,
            memoryAvailableFraction: 0.4
        )
        XCTAssertEqual(verdict.kind, .sweepRecommended, "tepat 14 hari = sudah memenuhi")
    }

    func testThresholdBisaDiatur() {
        let verdict = UptimeGuardian.evaluate(
            uptime: 5 * day,
            swapUsedBytes: 5_000_000_000,
            memoryAvailableFraction: 0.4,
            uptimeDays: 3
        )
        XCTAssertEqual(verdict.kind, .sweepRecommended, "threshold 3 hari → 5 hari lolos")
    }
}

final class MaintenanceSweepTests: XCTestCase {
    /// Proses yang pasti nggak ada → killall gagal rapi, tanpa nyentuh sistem.
    func testProsesTidakAdaGagalTanpaCrash() {
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }

        let outcome = MaintenanceSweep.restartProcesses(
            ["RespiteProsesFiktifXYZ"],
            ledgerURL: ledgerURL
        )
        XCTAssertTrue(outcome.restarted.isEmpty)
        XCTAssertEqual(outcome.failed.count, 1)
        // Tetap tercatat di ledger — jejak aksi, bukan cuma sukses.
        XCTAssertEqual(SafetyLedger.load(from: ledgerURL).count, 1)
    }

    func testProsesKritisDitolak() {
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }

        let outcome = MaintenanceSweep.restartProcesses(
            ["WindowServer"],
            ledgerURL: ledgerURL
        )
        XCTAssertTrue(outcome.restarted.isEmpty, "proses kritis nggak boleh bisa di-restart")
        XCTAssertTrue(SafetyLedger.load(from: ledgerURL).isEmpty, "aksi yang ditolak nggak boleh tercatat sebagai dieksekusi")
    }
}

final class MaintenanceReminderTests: XCTestCase {
    func testRisingEdgeSaja() {
        let now = Date()
        // Kondisi baru saja mulai → notif.
        XCTAssertTrue(MaintenanceReminder.shouldNotify(
            previousNotified: false, recommendedNow: true, lastNotifiedAt: nil, now: now
        ))
        // Sudah dinotifikasi & masih memenuhi → jangan spam.
        XCTAssertFalse(MaintenanceReminder.shouldNotify(
            previousNotified: true, recommendedNow: true, lastNotifiedAt: now, now: now
        ))
        // Kondisi sudah tidak memenuhi → tidak notif.
        XCTAssertFalse(MaintenanceReminder.shouldNotify(
            previousNotified: false, recommendedNow: false, lastNotifiedAt: nil, now: now
        ))
    }

    func testCooldownAntarKejadian() {
        let now = Date()
        // Kejadian baru (previousNotified sudah reset) tapi <1 jam dari notif terakhir → tahan.
        XCTAssertFalse(MaintenanceReminder.shouldNotify(
            previousNotified: false,
            recommendedNow: true,
            lastNotifiedAt: now.addingTimeInterval(-1_800),
            now: now
        ))
        // Lebih dari 1 jam → boleh notif lagi.
        XCTAssertTrue(MaintenanceReminder.shouldNotify(
            previousNotified: false,
            recommendedNow: true,
            lastNotifiedAt: now.addingTimeInterval(-3_600),
            now: now
        ))
    }
}
