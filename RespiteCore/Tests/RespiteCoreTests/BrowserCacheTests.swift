import XCTest
@testable import RespiteCore

final class BrowserCacheTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-browser-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeFile(_ relativePath: String, size: Int) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
    }

    func testChromiumMultiProfilDanFirefoxSafari() throws {
        // Chrome: dua profil + Caches dir.
        try makeFile("Library/Application Support/Google/Chrome/Default/Cache/Cache_Data/x", size: 300)
        try makeFile("Library/Application Support/Google/Chrome/Profile 1/Cache/Cache_Data/y", size: 200)
        try makeFile("Library/Application Support/Google/Chrome/GrannyDefault/cache-lain", size: 999) // bukan profil
        try makeFile("Library/Caches/com.google.Chrome/blob", size: 100)
        // Firefox.
        try makeFile("Library/Caches/Firefox/Profiles/abc123.default/cache2/entries/e1", size: 400)
        // Safari.
        try makeFile("Library/Caches/com.apple.Safari/fsCachedData/f", size: 50)
        // Browser nggak keinstall → tidak muncul (Edge/Brave/Arc).
        // Fake app biar Chrome & Firefox & Safari "terinstall".
        try makeFile("Applications/Google Chrome.app/Contents/MacOS/Chrome", size: 10)
        try makeFile("Applications/Firefox.app/Contents/MacOS/firefox", size: 10)
        try makeFile("Applications/Safari.app/Contents/MacOS/Safari", size: 10)

        let results = BrowserCacheScanner.scan(home: home, applicationsDirs: [home.appendingPathComponent("Applications")])

        XCTAssertEqual(Set(results.map(\.name)), ["Google Chrome", "Firefox", "Safari"])

        let chrome = results.first { $0.name == "Google Chrome" }!
        XCTAssertEqual(chrome.cacheRoots.count, 3, "Default + Profile 1 + Caches dir")
        XCTAssertEqual(chrome.totalCacheBytes, 600, "300 + 200 + 100; folder non-profil dikecualikan")

        let firefox = results.first { $0.name == "Firefox" }!
        XCTAssertEqual(firefox.totalCacheBytes, 400)

        let safari = results.first { $0.name == "Safari" }!
        XCTAssertEqual(safari.totalCacheBytes, 50)
    }

    func testBrowserTidakTerinstallDisembunyikan() throws {
        // Cache Chrome ada, tapi app-nya tidak → skip (leftover handling menyusul).
        try makeFile("Library/Caches/com.google.Chrome/blob", size: 100)
        let results = BrowserCacheScanner.scan(home: home, applicationsDirs: [home.appendingPathComponent("Applications")])
        XCTAssertTrue(results.isEmpty)
    }
}

extension BrowserCacheTests {
    func testRiwayatDanCookieDitemukan() throws {
        // Chromium: file per profil.
        try makeFile("Library/Application Support/Google/Chrome/Default/History", size: 300)
        try makeFile("Library/Application Support/Google/Chrome/Default/Cookies", size: 100)
        try makeFile("Library/Application Support/Google/Chrome/Profile 2/History", size: 50)
        // Firefox: places/cookies di Application Support (bukan Caches).
        try makeFile("Library/Application Support/Firefox/Profiles/x.default/places.sqlite", size: 200)
        try makeFile("Library/Application Support/Firefox/Profiles/x.default/cookies.sqlite", size: 40)
        try makeFile("Applications/Google Chrome.app/Contents/MacOS/Chrome", size: 10)
        try makeFile("Applications/Firefox.app/Contents/MacOS/firefox", size: 10)
        try makeFile("Applications/Safari.app/Contents/MacOS/Safari", size: 10)

        let results = BrowserCacheScanner.scan(home: home, applicationsDirs: [home.appendingPathComponent("Applications")])

        let chrome = results.first { $0.name == "Google Chrome" }!
        XCTAssertEqual(chrome.historyURLs.count, 2, "Default + Profile 2")
        XCTAssertEqual(chrome.totalHistoryBytes, 350)
        XCTAssertEqual(chrome.totalCookiesBytes, 100)

        let firefox = results.first { $0.name == "Firefox" }!
        XCTAssertEqual(firefox.totalHistoryBytes, 0, "places.sqlite berisi bookmark — riwayat Firefox nggak ditawarkan")
        XCTAssertEqual(firefox.totalCookiesBytes, 40)

        // Safari tidak menawarkan history/cookies.
        XCTAssertNotNil(results.first { $0.name == "Safari" })
    }
}
