import XCTest
@testable import RespiteCore

final class LargeFilesScannerTests: XCTestCase {
    private var root: URL!
    private var fakeHome: URL!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-home-\(UUID().uuidString)")
        root = fakeHome
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func makeFile(_ relativePath: String, size: Int, daysAgo: Int) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testHanyaFileDiAtasThreshold() async throws {
        try makeFile("Movies/kecil.bin", size: 100, daysAgo: 30)
        try makeFile("Movies/besar.bin", size: 500, daysAgo: 30)
        try makeFile("Downloads/raksasa.iso", size: 900, daysAgo: 2)

        let scanner = LargeFilesScanner(config: .init(
            root: root,
            minBytes: 300,
            recencyDays: 7,
            homeDirectory: fakeHome
        ))

        var hits: [FileHit] = []
        var summaryCount: Int?
        for try await event in scanner.scan() {
            switch event {
            case .found(let hit): hits.append(hit)
            case .finished(let count, _): summaryCount = count
            }
        }

        XCTAssertEqual(Set(hits.map { $0.url.lastPathComponent }), ["besar.bin", "raksasa.iso"])
        XCTAssertEqual(summaryCount, 2)

        let baru = hits.first { $0.url.lastPathComponent == "raksasa.iso" }
        XCTAssertFalse(baru?.isSelectedByDefault ?? true, "file 2 hari lalu kena Recency Guard")
        let lama = hits.first { $0.url.lastPathComponent == "besar.bin" }
        XCTAssertTrue(lama?.isSelectedByDefault ?? false)
    }

    func testPathProtectedDikecualikan() async throws {
        // Dokumen "pribadi" di Documents → nggak boleh muncul walau gedean.
        try makeFile("Documents/rahasia-besar.zip", size: 900, daysAgo: 60)
        try makeFile("Downloads/oke.bin", size: 900, daysAgo: 60)

        let scanner = LargeFilesScanner(config: .init(
            root: root,
            minBytes: 300,
            homeDirectory: fakeHome
        ))

        var names: [String] = []
        for try await event in scanner.scan() {
            if case .found(let hit) = event { names.append(hit.url.lastPathComponent) }
        }
        XCTAssertEqual(names, ["oke.bin"])
    }

    func testTrashSendiriDilewati() async throws {
        try makeFile(".Trash/terbuang.bin", size: 900, daysAgo: 60)
        try makeFile("Downloads/oke.bin", size: 900, daysAgo: 60)

        let scanner = LargeFilesScanner(config: .init(
            root: root,
            minBytes: 300,
            homeDirectory: fakeHome
        ))

        var names: [String] = []
        for try await event in scanner.scan() {
            if case .found(let hit) = event { names.append(hit.url.lastPathComponent) }
        }
        XCTAssertEqual(names, ["oke.bin"], "isi Trash udah tanggung jawab Smart Scan")
    }
}

final class CleanExecutorMoveTests: XCTestCase {
    func testMoveGenerikKeTrash() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-move-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("file-besar.bin")
        try Data(count: 42).write(to: file)

        let ledgerURL = dir.appendingPathComponent("ledger.json")
        let outcome = CleanExecutor.move(
            [CleanExecutor.TrashItem(url: file, bytes: 42, label: "file-besar.bin")],
            module: "Large Files",
            ledgerURL: ledgerURL
        )

        XCTAssertEqual(outcome.cleaned.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "file harusnya udah pindah ke Trash")
        XCTAssertEqual(SafetyLedger.load(from: ledgerURL).count, 1)
    }
}
