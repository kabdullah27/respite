import XCTest
@testable import RespiteCore

/// Orphan Finder — matching pemilik harus ketat; false positive = menawarkan
/// hapus data app yang MASIH terpasang (mahal). Semua fixture di temp dir.
final class OrphanFinderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-orphan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ relative: String, size: Int = 2_000_000) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xAB, count: size).write(to: url)
    }

    private func locations() -> OrphanFinder.Locations {
        OrphanFinder.Locations(
            applicationSupport: root.appendingPathComponent("Application Support"),
            caches: root.appendingPathComponent("Caches"),
            preferences: root.appendingPathComponent("Preferences"),
            containers: root.appendingPathComponent("Containers")
        )
    }

    private let installedApps = [
        AppRef(bundleID: "com.stillhere.chrome", name: "MyBrowser"),
    ]

    /// Item milik app TERPASANG → bukan yatim. Item tanpa pemilik → yatim.
    func testYatimVsTerpasang() async throws {
        try makeFile("Application Support/com.stillhere.chrome/data.db")
        try makeFile("Application Support/com.goneforever.app/data.db")
        try makeFile("Caches/com.goneforever.app.cache")

        let finder = OrphanFinder(
            locations: locations(),
            apps: installedApps
        )

        var items: [OrphanItem] = []
        for try await event in finder.scan() {
            if case .found(let item) = event { items.append(item) }
        }

        XCTAssertEqual(items.count, 2, "dua item com.goneforever.app; yang punya pemilik bukan yatim")
        XCTAssertTrue(items.allSatisfy { $0.url.path.contains("goneforever") })
    }

    /// Preferences "com.x.plist" dicocokkan via bundle ID tanpa extension.
    func testPreferencesPlistDitandaiBundleID() throws {
        XCTAssertTrue(OrphanFinder.hasOwner(
            name: "com.stillhere.chrome.plist",
            path: "/x/Preferences/com.stillhere.chrome.plist",
            apps: installedApps
        ))
        XCTAssertFalse(OrphanFinder.hasOwner(
            name: "com.other.plist",
            path: "/x/Preferences/com.other.plist",
            apps: installedApps
        ))
    }

    /// Vendor folder "SomeVendor/MyBrowser" tetap dianggap punya pemilik
    /// (komponen path match nama app terpasang).
    func testPathComponentNamaApp() {
        XCTAssertTrue(OrphanFinder.hasOwner(
            name: "MyBrowser",
            path: "/x/Application Support/SomeVendor/MyBrowser",
            apps: installedApps
        ))
    }

    /// Item com.apple.* SELALU punya pemilik — jangan pernah tawarin.
    func testAppleSelaluPunyaPemilik() async throws {
        try makeFile("Caches/com.apple.somethingbig")
        let finder = OrphanFinder(locations: locations(), apps: [])
        var count = 0
        for try await event in finder.scan() {
            if case .found = event { count += 1 }
        }
        XCTAssertEqual(count, 0, "item com.apple.* tidak boleh jadi yatim walau app list kosong")
    }

    /// Item di bawah threshold ukuran tidak dilaporkan (noise).
    func testKecilDilewati() async throws {
        try makeFile("Caches/com.tiny.app", size: 10_000)
        let finder = OrphanFinder(locations: locations(), apps: installedApps)
        var count = 0
        for try await event in finder.scan() {
            if case .found = event { count += 1 }
        }
        XCTAssertEqual(count, 0)
    }
}
