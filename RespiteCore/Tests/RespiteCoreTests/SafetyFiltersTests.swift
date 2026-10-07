import XCTest
@testable import RespiteCore

final class SafetyFiltersTests: XCTestCase {
    // MARK: Protected List

    func testPathHomeSensitifTerproteksi() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertTrue(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Documents/laporan.pdf"),
            homeDirectory: home
        ))
        XCTAssertTrue(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Desktop"),
            homeDirectory: home
        ))
        XCTAssertTrue(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Library/Keychains/ops.db"),
            homeDirectory: home
        ))
    }

    func testPathCacheTidakTerproteksi() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertFalse(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Library/Caches/com.apple.Safari"),
            homeDirectory: home
        ))
        XCTAssertFalse(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Library/Logs/system.log"),
            homeDirectory: home
        ))
    }

    func testPrefixMiripTidakBolehFalsePositive() {
        // "Desktop-Backup" bukan "Desktop" — nggak boleh kena proteksi.
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertFalse(ProtectedList.isProtected(
            URL(fileURLWithPath: "/Users/tester/Desktop-Backup/old"),
            homeDirectory: home
        ))
    }

    // MARK: User Whitelist

    func testWhitelistExcludePrefix() {
        var whitelist = UserWhitelist()
        whitelist.add("/Users/tester/Library/Caches/Victim.app")
        XCTAssertTrue(whitelist.isExcluded(URL(fileURLWithPath: "/Users/tester/Library/Caches/Victim.app/Cache.db")))
        XCTAssertFalse(whitelist.isExcluded(URL(fileURLWithPath: "/Users/tester/Library/Caches/Other.app")))
    }

    func testWhitelistPersistKeDefaults() {
        let defaults = UserDefaults(suiteName: "test.whitelist")!
        defer { defaults.removePersistentDomain(forName: "test.whitelist") }
        var whitelist = UserWhitelist()
        whitelist.add("/tmp/fixture")
        whitelist.save(to: defaults)
        XCTAssertEqual(UserWhitelist.load(from: defaults).patterns, ["/tmp/fixture"])
    }

    // MARK: Recency Guard

    func testItemBaruTidakTerpilihDefault() {
        let now = Date()
        let fresh = now.addingTimeInterval(-3 * 86_400) // 3 hari lalu
        XCTAssertFalse(RecencyGuard.shouldSelectByDefault(lastModified: fresh, now: now, days: 7))
    }

    func testItemLamaTerpilihDefault() {
        let now = Date()
        let old = now.addingTimeInterval(-30 * 86_400)
        XCTAssertTrue(RecencyGuard.shouldSelectByDefault(lastModified: old, now: now, days: 7))
    }

    func testBatasTepat7Hari() {
        let now = Date()
        let tepat = now.addingTimeInterval(-7 * 86_400)
        // Tepat di batas = masih dianggap baru (belum lewat 7 hari penuh).
        XCTAssertFalse(RecencyGuard.shouldSelectByDefault(lastModified: tepat, now: now, days: 7))
    }
}
