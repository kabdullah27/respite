import XCTest
import CoreGraphics
@testable import RespiteCore

/// Regresi untuk bug logika yang ditemukan di audit 2026-10-10.
final class LogicFixesTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-fixes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Squarify

    /// Dulu satuan rasio campur (fraksi vs poin) → semua item jadi strip
    /// selebar canvas. Sekarang harus ada lebih dari satu kolom/baris.
    func testSquarifyBenarBenarMembagiDuaArah() {
        let sizes: [Double] = [50, 20, 10, 5, 5, 4, 3, 2, 1]
        let canvas = CGRect(x: 0, y: 0, width: 800, height: 400)
        let rects = Squarify.layout(sizes: sizes, in: canvas)

        XCTAssertFalse(rects.allSatisfy { $0.width == canvas.width }, "bukan semua strip penuh-lebar")
        let area = rects.map { $0.width * $0.height }.reduce(0, +)
        XCTAssertEqual(area, canvas.width * canvas.height, accuracy: 1.0)
        // Proporsi luas sesuai proporsi ukuran.
        XCTAssertEqual(rects[0].width * rects[0].height, 0.5 * 800 * 400, accuracy: 1.0)
        // Rasio aspek wajar (nggak ada sliver 800×4).
        for rect in rects {
            let ratio = max(rect.width / rect.height, rect.height / rect.width)
            XCTAssertLessThan(ratio, 10, "rect \(rect) terlalu gepeng")
        }
    }

    // MARK: Similar Photos

    /// Single-linkage merantai A~B~C walau A–C jauh. Complete-linkage nggak.
    func testKlasterTidakMerantai() {
        let a: UInt64 = 0
        let b: UInt64 = 0b111111           // jarak 6 dari a
        let c: UInt64 = 0b111111_111111    // jarak 6 dari b, 12 dari a
        func photo(_ h: UInt64) -> PhotoItem {
            PhotoItem(url: URL(fileURLWithPath: "/tmp/p-\(h).jpg"), sizeBytes: 1, lastModified: .distantPast, phash: h)
        }
        let clusters = SimilarPhotosScanner.cluster(items: [photo(a), photo(b), photo(c)], hammingThreshold: 6)
        for cluster in clusters {
            for x in cluster { for y in cluster {
                XCTAssertLessThanOrEqual(SimilarPhotosScanner.hamming(x.phash, y.phash), 6)
            } }
        }
        XCTAssertEqual(clusters.flatMap { $0 }.count, 2, "C nggak boleh ikut klaster A")
    }

    // MARK: Duplicate Finder

    /// {A, hardlink-A, C}: cuma A & C yang dilaporkan; reclaimable = 1×size.
    func testHardLinkSebagianTidakMenggandakanReclaimable() async throws {
        let root = home.appendingPathComponent("dup")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data(repeating: 0x42, count: 1_200_000)
        let a = root.appendingPathComponent("a.bin")
        let link = root.appendingPathComponent("a-link.bin")
        let c = root.appendingPathComponent("c.bin")
        try data.write(to: a)
        try data.write(to: c)
        guard Darwin.link(a.path, link.path) == 0 else { throw XCTSkip("hard link tidak didukung") }

        let scanner = DuplicateScanner(config: .init(root: root, minBytes: 1_000_000, homeDirectory: home))
        var groups: [DuplicateGroup] = []
        var reclaimable: Int64 = 0
        for try await event in scanner.scan() {
            switch event {
            case .found(let group): groups.append(group)
            case .finished(_, let bytes): reclaimable = bytes
            default: break
            }
        }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
        XCTAssertEqual(reclaimable, Int64(data.count))
    }

    // MARK: Large Files

    func testFileBesarLangsungDiRootIkutKetemu() async throws {
        let big = home.appendingPathComponent("besar.dmg")
        try Data(repeating: 1, count: 2_000).write(to: big)
        let scanner = LargeFilesScanner(
            config: .init(root: home, minBytes: 1_000, homeDirectory: home),
            whitelist: UserWhitelist(patterns: [])
        )
        var found: [URL] = []
        for try await event in scanner.scan() {
            if case .found(let hit) = event { found.append(hit.url) }
        }
        XCTAssertEqual(found.map(\.lastPathComponent), ["besar.dmg"])
    }

    // MARK: Uninstaller

    /// bundleID dari Info.plist nggak dipercaya — "../.." nggak boleh
    /// membuat ~/Library jadi "sisa" yang ke-centang.
    func testBundleIDTraversalDitolak() throws {
        let library = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let app = InstalledApp(
            url: home.appendingPathComponent("Jahat.app"),
            name: "..",
            bundleID: "../..",
            sizeBytes: 0
        )
        let leftovers = LeftoverScanner.leftovers(for: app, locations: .standard(home: home))
        XCTAssertTrue(leftovers.isEmpty, "\(leftovers.map(\.url.path))")
    }

    // MARK: Orphan Finder

    func testFolderDataAppleBukanYatim() {
        XCTAssertTrue(OrphanFinder.isAppleOwned("MobileSync"))
        XCTAssertTrue(OrphanFinder.isAppleOwned("AddressBook"))
        XCTAssertTrue(OrphanFinder.isAppleOwned("group.com.apple.notes"))
        XCTAssertTrue(OrphanFinder.isAppleOwned("ABCDE12345.groups.com.apple.x"))
        XCTAssertFalse(OrphanFinder.isAppleOwned("com.goneforever.app"))
    }

    func testTeamIDContainerCocokDenganBundleID() {
        let apps = [AppRef(bundleID: "com.vendor.app", name: "VendorApp")]
        XCTAssertTrue(OrphanFinder.hasOwner(name: "ABCDE12345.com.vendor.app", path: "/x", apps: apps))
        XCTAssertTrue(OrphanFinder.hasOwner(name: "group.com.vendor.app.shared", path: "/x", apps: apps))
        XCTAssertFalse(OrphanFinder.isConfidentlyMatchable(name: "UBF8T346G9.Office", locationName: "Group Containers"))
        XCTAssertFalse(OrphanFinder.isConfidentlyMatchable(name: "Office", locationName: "Application Support"))
        XCTAssertTrue(OrphanFinder.isConfidentlyMatchable(name: "com.gone.app.plist", locationName: "Preferences"))
    }

    // MARK: Mail

    func testLampiranHarusDiBawahLibraryMail() {
        XCTAssertFalse(MailAttachments.isAttachmentPath(
            URL(fileURLWithPath: "/Users/x/Documents/Attachments/kontrak.pdf")
        ))
        XCTAssertFalse(MailAttachments.isAttachmentPath(
            URL(fileURLWithPath: "/Users/x/Library/Mail/Attachments")
        ), "folder Attachments itu sendiri bukan lampiran")
    }

    // MARK: Ledger

    func testRecordBatchSatuTulisDanTanggalIso() {
        let url = home.appendingPathComponent("history.json")
        SafetyLedger.record([
            LedgerEntry(actionType: "a", target: "1", reversible: true, detail: ""),
            LedgerEntry(actionType: "b", target: "2", reversible: true, detail: ""),
        ], to: url)
        SafetyLedger.record(LedgerEntry(actionType: "c", target: "3", reversible: true, detail: ""), to: url)
        XCTAssertEqual(SafetyLedger.load(from: url).map(\.actionType), ["a", "b", "c"])
        // Encoder migrasi = encoder record → hasilnya bisa dibaca load().
        let entries = SafetyLedger.load(from: url)
        let data = try! SafetyLedger.makeEncoder().encode(entries)
        try! data.write(to: url)
        XCTAssertEqual(SafetyLedger.load(from: url).count, 3)
    }

    func testItemDiTrashTidakDihitungFreed() throws {
        let trash = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let file = trash.appendingPathComponent("x.bin")
        try Data(repeating: 0, count: 10).write(to: file)
        let outcome = CleanExecutor.move(
            [.init(url: file, bytes: 10, label: "x")],
            module: "test",
            ledgerURL: home.appendingPathComponent("ledger.json")
        )
        XCTAssertEqual(outcome.freedBytes, 0)
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Update checker

    func testPreReleaseLebihLamaDariFinal() {
        XCTAssertTrue(UpdateChecker.isVersion("1.2.0", newerThan: "1.2.0-beta.2"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0-rc.1", newerThan: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.2.0-beta.10", newerThan: "1.2.0-beta.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.0+build5", newerThan: "1.2.0"))
    }

    // MARK: Desktop Declutter

    func testScreenShotLamaPakaiTanggalDiNama() {
        let name = DesktopDeclutter.archiveFolderName(
            fromFileName: "Screen Shot 2020-01-05 at 10.00.00.png",
            modified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(name, "2020-01")
    }

    // MARK: CPU consumers

    /// Dengan wallDelta, fraksi = porsi satu core — Mac idle nggak "sibuk".
    func testFraksiCPUDinormalisasiWaktuDinding() {
        let prev = [CPUConsumers.Sample(pid: 1, name: "WindowServer", cpuTime: 1_000)]
        let cur = [CPUConsumers.Sample(pid: 1, name: "WindowServer", cpuTime: 1_010)]
        let relative = CPUConsumers.groups(from: prev, to: cur)
        XCTAssertEqual(relative.first?.fraction ?? 0, 1.0, accuracy: 0.001)
        let normalized = CPUConsumers.groups(from: prev, to: cur, minFraction: 0, wallDelta: 1_000)
        XCTAssertEqual(normalized.first?.fraction ?? 0, 0.01, accuracy: 0.001)
    }
}
