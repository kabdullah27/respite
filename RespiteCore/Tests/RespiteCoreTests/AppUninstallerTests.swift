import XCTest
@testable import RespiteCore

final class AppUninstallerTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-apps-\(UUID().uuidString)")
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: home)
    }

    /// Bikin .app fixture dengan Info.plist beneran.
    private func makeApp(_ name: String, bundleID: String, fileBytes: Int) throws -> URL {
        let contents = root.appendingPathComponent("\(name).app/Contents/MacOS")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let binary = contents.appendingPathComponent(name)
        try Data(count: fileBytes).write(to: binary)
        let plist = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
        ] as NSDictionary
        plist.write(to: root.appendingPathComponent("\(name).app/Contents/Info.plist"), atomically: true)
        return root.appendingPathComponent("\(name).app")
    }

    private func makeLibraryItem(_ relativePath: String, fileBytes: Int) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: fileBytes).write(to: url)
    }

    func testKatalogNemuAplikasiDanSkipApple() throws {
        try makeApp("ToolBagus", bundleID: "com.vendor.toolbagus", fileBytes: 500)
        try makeApp("SafariPalsu", bundleID: "com.apple.something", fileBytes: 900)
        try makeApp("RespiteHelper", bundleID: "app.respite.helper", fileBytes: 100)

        let apps = AppCatalog.installedApps(searchPaths: [root])

        XCTAssertEqual(apps.count, 1, "app Apple & app Respite sendiri nggak boleh ditawarin")
        XCTAssertEqual(apps[0].name, "ToolBagus")
        XCTAssertEqual(apps[0].bundleID, "com.vendor.toolbagus")
        XCTAssertGreaterThanOrEqual(apps[0].sizeBytes, 500, "ukuran = binary + Info.plist bundle")
    }

    func testScanStreamingSamaDenganVersiSinkron() async throws {
        try makeApp("ToolBagus", bundleID: "com.vendor.toolbagus", fileBytes: 500)

        var streamed: [InstalledApp] = []
        var finishedTotal: Int?
        for try await event in AppCatalog.scanApps(searchPaths: [root]) {
            switch event {
            case .found(let app): streamed.append(app)
            case .finished(let total): finishedTotal = total
            }
        }
        XCTAssertEqual(finishedTotal, 1)
        XCTAssertEqual(streamed.map(\.name), AppCatalog.installedApps(searchPaths: [root]).map(\.name))
    }

    func testLeftoverExactVsFuzzy() throws {
        let app = InstalledApp(
            url: root.appendingPathComponent("ElectronKu.app"),
            name: "ElectronKu",
            bundleID: "com.electron.ku",
            sizeBytes: 100
        )
        // Exact: bundle ID.
        try makeLibraryItem("Library/Preferences/com.electron.ku.plist", fileBytes: 10)
        try makeLibraryItem("Library/Caches/com.electron.ku/cache.db", fileBytes: 200)
        // Fuzzy: nama app (kasus khas Electron).
        try makeLibraryItem("Library/Application Support/ElectronKu/store.bin", fileBytes: 300)
        // Nggak nyambung: milik app lain.
        try makeLibraryItem("Library/Caches/app.lain/x.bin", fileBytes: 999)

        let leftovers = LeftoverScanner.leftovers(for: app, locations: .standard(home: home))

        // Exact: Preferences plist + direktori Caches ber-bundle-ID.
        XCTAssertEqual(leftovers.filter { $0.confidence == .exact }.count, 2)
        XCTAssertEqual(leftovers.filter { $0.confidence == .fuzzy }.count, 1)
        XCTAssertFalse(leftovers.contains { $0.url.path.contains("app.lain") })

        let cacheExact = leftovers.first { $0.url.path.contains("Caches/com.electron.ku") }
        XCTAssertEqual(cacheExact?.sizeBytes, 200)
        let fuzzy = leftovers.first { $0.confidence == .fuzzy }
        XCTAssertTrue(fuzzy?.isSelectedByDefault == false, "fuzzy nggak boleh auto-check")
    }

    func testBundleIDKosongTidakCrash() {
        let app = InstalledApp(url: root, name: "Aneh", bundleID: nil, sizeBytes: 0)
        let leftovers = LeftoverScanner.leftovers(for: app, locations: .standard(home: home))
        XCTAssertTrue(leftovers.isEmpty)
    }
}
