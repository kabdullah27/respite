import XCTest
@testable import RespiteCore

final class TrashManagerTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".Trash"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeTrashed(_ name: String, size: Int, daysAgo: Int) throws {
        let url = home.appendingPathComponent(".Trash/\(name)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86_400)],
            ofItemAtPath: url.path
        )
    }

    func testScanTrashSortedDesc() throws {
        try makeTrashed("kecil.txt", size: 100, daysAgo: 3)
        try makeTrashed("gede.zip", size: 900, daysAgo: 40)

        let items = TrashScanner.scan(home: home)
        XCTAssertEqual(items.map(\.url.lastPathComponent), ["gede.zip", "kecil.txt"])
        XCTAssertEqual(items.first?.sizeBytes, 900)
    }

    func testHapusPermanenMenghapusDanTerekam() throws {
        try makeTrashed("rahasia.zip", size: 500, daysAgo: 10)
        let items = TrashScanner.scan(home: home)

        let ledgerURL = home.appendingPathComponent("ledger.json")
        let outcome = CleanExecutor.permanentlyDelete(items, ledgerURL: ledgerURL)

        XCTAssertEqual(outcome.cleaned.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: items[0].url.path))
        let entries = SafetyLedger.load(from: ledgerURL)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].reversible, "hapus permanen harus tercatat irreversible")
        XCTAssertEqual(entries[0].actionType, "delete-permanent")
    }
}
