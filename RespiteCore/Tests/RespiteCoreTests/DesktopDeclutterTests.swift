import XCTest
@testable import RespiteCore

final class DesktopDeclutterTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-desk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Desktop"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeDesktopItem(_ name: String, size: Int, daysAgo: Int) throws -> URL {
        let url = home.appendingPathComponent("Desktop/\(name)")
        try Data(count: size).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86_400)],
            ofItemAtPath: url.path
        )
        return url
    }

    func testPolaNamaScreenshot() {
        // Format baru & lama macOS.
        XCTAssertTrue(DesktopDeclutter.isScreenshot("Screenshot 2025-06-01 at 10.00.00.png"))
        XCTAssertTrue(DesktopDeclutter.isScreenshot("Screen Shot 2019-12-31 at 08.45.11.png"))
        // Bukan screenshot.
        XCTAssertFalse(DesktopDeclutter.isScreenshot("laporan.pdf"))
        XCTAssertFalse(DesktopDeclutter.isScreenshot("screenshots-favorit.png"))
        XCTAssertFalse(DesktopDeclutter.isScreenshot("Screenshot-lama.png"))
    }

    func testScanTopLevelSajaDenganRecency() throws {
        try makeDesktopItem("Screenshot 2025-01-01 at 09.00.00.png", size: 100, daysAgo: 90)
        try makeDesktopItem("Screenshot 2025-09-20 at 11.00.00.png", size: 50, daysAgo: 1)
        try makeDesktopItem("laporan.pdf", size: 999, daysAgo: 300)
        // Subfolder bernama kayak screenshot → diabaikan (bukan file).
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Desktop/Screenshot 2025-01-01 folder"),
            withIntermediateDirectories: true
        )

        let items = DesktopDeclutter.scan(home: home)
        XCTAssertEqual(items.count, 2, "cuma file screenshot top-level")
        XCTAssertTrue(items[0].isSelectedByDefault, "90 hari lalu → terpilih")
        XCTAssertFalse(items[1].isSelectedByDefault, "1 hari lalu → Recency Guard")
        XCTAssertEqual(items.first?.targetFolder, "2025-01")
    }

    func testArsipPindahKeFolderPerBulan() throws {
        let url = try makeDesktopItem("Screenshot 2025-03-15 at 08.00.00.png", size: 100, daysAgo: 100)

        let ledgerURL = home.appendingPathComponent("ledger.json")
        let items = DesktopDeclutter.scan(home: home)
        let outcome = DesktopDeclutter.archive(items, home: home, ledgerURL: ledgerURL)

        XCTAssertEqual(outcome.moved.count, 1)
        XCTAssertTrue(outcome.failedURLs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "sudah tidak di Desktop")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Desktop Archive/2025-03/Screenshot 2025-03-15 at 08.00.00.png").path
        ))
        XCTAssertEqual(SafetyLedger.load(from: ledgerURL).count, 1)
    }
}
