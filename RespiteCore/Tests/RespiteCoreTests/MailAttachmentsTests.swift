import XCTest
@testable import RespiteCore

final class MailAttachmentsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-mail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func makeFile(_ relativePath: String, size: Int, daysAgo: Int) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-Double(daysAgo) * 86_400)],
            ofItemAtPath: url.path
        )
        return url
    }

    func testHanyaLampiranYangDisentuh() throws {
        // Lampiran lama & gede → masuk, terpilih.
        try makeFile("Library/Mail/V9/acc/INBOX.mbox/Attachments/video.mp4", size: 900, daysAgo: 120)
        // Lampiran baru → masuk tapi TIDAK terpilih (guard 90 hari).
        try makeFile("Library/Mail/V9/acc/INBOX.mbox/Attachments/doc.pdf", size: 800, daysAgo: 5)
        // Lampiran kecil → dilewati minBytes.
        try makeFile("Library/Mail/V9/acc/INBOX.mbox/Attachments/kecil.txt", size: 10, daysAgo: 200)
        // File lain di dalam Mail (bukan Attachments) → TIDAK BOLEH tersentuh.
        try makeFile("Library/Mail/V9/acc/INBOX.mbox/Data/1/3/message.emlx", size: 999, daysAgo: 300)

        let items = MailAttachments.scan(home: home, minBytes: 100)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.url.lastPathComponent, "video.mp4")
        XCTAssertEqual(items.first?.isSelectedByDefault, true)
        XCTAssertEqual(items.last?.isSelectedByDefault, false)
        XCTAssertFalse(items.contains { $0.url.lastPathComponent == "message.emlx" })
    }

    func testMoveToTrashHanyaJalurLampiran() throws {
        let attachment = try makeFile("Library/Mail/V9/acc/INBOX.mbox/Attachments/besar.zip", size: 500, daysAgo: 100)
        // Palsu: item di luar Attachments diselundupkan — harus ditolak.
        try makeFile("Library/Mail/V9/penting.emlx", size: 50, daysAgo: 100)
        let smuggled = MailAttachment(
            url: home.appendingPathComponent("Library/Mail/V9/penting.emlx"),
            sizeBytes: 10,
            lastModified: .distantPast,
            isSelectedByDefault: true
        )

        let ledgerURL = home.appendingPathComponent("ledger.json")
        let outcome = MailAttachments.moveToTrash([smuggled], ledgerURL: ledgerURL)

        XCTAssertTrue(outcome.trashed.isEmpty, "item di luar Attachments wajib ditolak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: smuggled.url.path))

        let items = MailAttachments.scan(home: home, minBytes: 100)
        let outcome2 = MailAttachments.moveToTrash(items, ledgerURL: ledgerURL)
        XCTAssertEqual(outcome2.trashed.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.path))
        XCTAssertEqual(SafetyLedger.load(from: ledgerURL).count, 1, "cuma aksi yang beneran dieksekusi yang tercatat")
    }

    func testPathLampiran() {
        XCTAssertTrue(MailAttachments.isAttachmentPath(
            URL(fileURLWithPath: "/Users/x/Library/Mail/V9/a/INBOX.mbox/Attachments/f.pdf")
        ))
        XCTAssertFalse(MailAttachments.isAttachmentPath(
            URL(fileURLWithPath: "/Users/x/Library/Mail/V9/a/INBOX.mbox/Data/1/3")
        ))
    }
}
