import XCTest
@testable import RespiteCore

final class SmartScannerTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    /// Bikin file dengan tanggal modifikasi yang bisa disetel.
    private func makeFile(_ path: String, size: Int, daysAgo: Int) throws {
        let url = fixtureRoot.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testScanKategoriUkuranDanRecency() async throws {
        // Cache: 2 owner — satu lama (default terpilih), satu baru (Recency Guard).
        try makeFile("Caches/AlphaOld/cache.db", size: 100, daysAgo: 60)
        try makeFile("Caches/BetaNew/cache.db", size: 50, daysAgo: 1)
        try makeFile("Logs/GammaLog/system.log", size: 200, daysAgo: 30)

        let targets = ScanTargets(
            userCaches: fixtureRoot.appendingPathComponent("Caches"),
            userLogs: fixtureRoot.appendingPathComponent("Logs"),
            trash: nil
        )
        let scanner = SmartScanner(targets: targets, whitelist: UserWhitelist())

        var allResults: [ScanResult] = []
        var summary: ScanSummary?
        var finishedCategories: [ScanCategory] = []
        for try await event in scanner.scan() {
            switch event {
            case .found(let result): allResults.append(result)
            case .categoryFinished(let category, _, _): finishedCategories.append(category)
            case .finished(let s): summary = s
            case .categoryStarted: break
            }
        }

        XCTAssertEqual(allResults.count, 3)
        XCTAssertEqual(finishedCategories, [.userCaches, .userLogs], "kategori selesai berurutan")

        let alpha = try XCTUnwrap(allResults.first { $0.ownerName == "AlphaOld" })
        XCTAssertEqual(alpha.category, .userCaches)
        XCTAssertEqual(alpha.sizeBytes, 100)
        XCTAssertTrue(alpha.isSelectedByDefault, "item 60 hari lalu harusnya terpilih default")

        let beta = try XCTUnwrap(allResults.first { $0.ownerName == "BetaNew" })
        // Cache/log/trash SELALU direkomendasikan — "baru dipakai" bukan
        // alasan menahan cache (Recency Guard tidak berlaku untuk Smart Scan).
        XCTAssertTrue(beta.isSelectedByDefault)

        let gamma = try XCTUnwrap(allResults.first { $0.ownerName == "GammaLog" })
        XCTAssertEqual(gamma.category, .userLogs)

        XCTAssertEqual(summary?.resultCount, 3)
        XCTAssertEqual(summary?.totalBytes, 350)
    }

    func testWhitelistNgeFilterHasil() async throws {
        try makeFile("Caches/ExcludedApp/cache.db", size: 10, daysAgo: 30)
        try makeFile("Caches/KeptApp/cache.db", size: 20, daysAgo: 30)

        var whitelist = UserWhitelist()
        whitelist.add(fixtureRoot.appendingPathComponent("Caches/ExcludedApp").path)

        let scanner = SmartScanner(
            targets: ScanTargets(
                userCaches: fixtureRoot.appendingPathComponent("Caches"),
                userLogs: nil,
                trash: nil
            ),
            whitelist: whitelist
        )

        var results: [ScanResult] = []
        for try await event in scanner.scan() {
            if case .found(let result) = event { results.append(result) }
        }
        XCTAssertEqual(results.map(\.ownerName), ["KeptApp"])
    }

    func testScanBisaDibatalkan() async throws {
        try makeFile("Caches/SlowApp/cache.db", size: 10, daysAgo: 30)
        let scanner = SmartScanner(
            targets: ScanTargets(
                userCaches: fixtureRoot.appendingPathComponent("Caches"),
                userLogs: nil,
                trash: nil
            )
        )
        let consumer = Task {
            for try await _ in scanner.scan() { /* jalan sampai dibatalkan */ }
        }
        consumer.cancel()
        _ = try? await consumer.value
        // Selesai tanpa crash setelah cancel = pass.
    }
}

final class SafetyLedgerTests: XCTestCase {
    func testRecordDanLoadRoundtrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        SafetyLedger.record(
            LedgerEntry(actionType: "move-to-trash", target: "/tmp/x", reversible: true, detail: "test"),
            to: fileURL
        )
        SafetyLedger.record(
            LedgerEntry(actionType: "move-to-trash", target: "/tmp/y", reversible: true, detail: "test"),
            to: fileURL
        )
        let entries = SafetyLedger.load(from: fileURL)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.target), ["/tmp/x", "/tmp/y"])
    }
}

final class CleanExecutorTests: XCTestCase {
    /// Guard di level OPERASI: path protected ditolak meskipun lolos ke list
    /// hasil scan — UI layer bisa ke-bypass, ini nggak (TRD §4.20 p1).
    func testPathProtectedDitolakDiLevelOperasi() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedURL = home.appendingPathComponent("Documents/should-not-be-touched-\(UUID().uuidString)")
        try Data(count: 5).write(to: protectedURL)
        defer { try? FileManager.default.removeItem(at: protectedURL) }

        let result = ScanResult(
            url: protectedURL,
            category: .userCaches,
            ownerName: "DocFolder",
            sizeBytes: 5,
            lastModified: Date().addingTimeInterval(-86_400 * 30),
            isSelectedByDefault: true
        )
        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }

        let outcome = CleanExecutor.moveToTrash([result], ledgerURL: ledgerURL)

        XCTAssertTrue(outcome.cleaned.isEmpty)
        XCTAssertEqual(outcome.failed.map(\.url), [protectedURL], "ditolak harus dilaporkan, bukan hilang diam-diam")
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedURL.path), "file protected nggak boleh tersentuh")
        XCTAssertTrue(SafetyLedger.load(from: ledgerURL).isEmpty, "nggak boleh ada entry buat aksi yang ditolak")
    }
}
