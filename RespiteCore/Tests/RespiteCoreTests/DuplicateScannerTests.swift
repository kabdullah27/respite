import XCTest
@testable import RespiteCore

final class DuplicateScannerTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-dup-home-\(UUID().uuidString)")
        root = home.appendingPathComponent("Duplikat")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeFile(
        _ relativePath: String,
        content: Data,
        daysAgo: Int
    ) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86_400)],
            ofItemAtPath: url.path
        )
        return url
    }

    func testDuplikatPersisDitemukanDanKeepTerlama() async throws {
        let content = Data("isi-file-foto-nih".utf8)
        try makeFile("Lama/foto.jpg", content: content, daysAgo: 60)
        try makeFile("Baru/foto-salinan.jpg", content: content, daysAgo: 1)
        // Ukuran sama, isi beda → BUKAN duplikat.
        try makeFile("Lain/beda.jpg", content: Data("isi-lain-x".utf8), daysAgo: 60)

        let scanner = DuplicateScanner(config: .init(root: root, minBytes: 1, homeDirectory: home))
        var groups: [DuplicateGroup] = []
        for try await event in scanner.scan() {
            if case .found(let group) = event { groups.append(group) }
        }

        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.files.count, 2)

        let keep = group.files.first { $0.isSuggestedKeep }
        XCTAssertEqual(keep?.url.lastPathComponent, "foto.jpg", "yang terlama disarankan disimpan")

        let salinan = group.files.first { !$0.isSuggestedKeep }
        XCTAssertEqual(salinan?.isSelectedByDefault, false, "salinan baru (1 hari) kena Recency Guard")
    }

    func testKolisiPartialHashDipisahFase3() async throws {
        // Prefix 4 KB sama, isi belakang beda → fase 3 harus memisahkan.
        let prefix = Data(repeating: 0xAB, count: 4096)
        try makeFile("a.bin", content: prefix + Data("aaa".utf8), daysAgo: 60)
        try makeFile("b.bin", content: prefix + Data("bbb".utf8), daysAgo: 60)

        let scanner = DuplicateScanner(config: .init(root: root, minBytes: 1, homeDirectory: home))
        var groups: [DuplicateGroup] = []
        for try await event in scanner.scan() {
            if case .found(let group) = event { groups.append(group) }
        }
        XCTAssertTrue(groups.isEmpty, "prefix sama bukan duplikat kalau isi totalnya beda")
    }

    func testUkuranKecilDilewati() async throws {
        try makeFile("x.txt", content: Data("kecil".utf8), daysAgo: 60)
        try makeFile("y.txt", content: Data("kecil".utf8), daysAgo: 60)

        let scanner = DuplicateScanner(config: .init(root: root, minBytes: 100, homeDirectory: home))
        var count = 0
        for try await event in scanner.scan() {
            if case .found = event { count += 1 }
        }
        XCTAssertEqual(count, 0, "di bawah threshold minBytes tidak dibandingkan")
    }

    /// Hard link (inode sama) BUKAN duplikat — menghapusnya tidak
    /// membebaskan ruang apa pun. Scanner harus menyaringnya.
    func testHardLinkBukanDuplikat() async throws {
        let original = root.appendingPathComponent("asli.bin")
        let hardlink = root.appendingPathComponent("hardlink.bin")
        let data = Data(repeating: 0x41, count: 1_500_000)
        try data.write(to: original)
        // link() = hard link beneran (POSIX), bukan symlink.
        let ok = original.path.withCString { src in
            hardlink.path.withCString { dst in
                link(src, dst) == 0
            }
        }
        if !ok {
            throw XCTSkip("Filesystem fixture tidak mendukung hard link")
        }

        let scanner = DuplicateScanner(config: .init(root: root, minBytes: 1_000_000, homeDirectory: home))
        var groups = 0
        for try await event in scanner.scan() {
            if case .found = event { groups += 1 }
        }
        XCTAssertEqual(groups, 0, "hard link ke inode sama tidak boleh dilaporkan")
    }
}
