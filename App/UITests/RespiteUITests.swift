import XCTest

/// Smoke test UI (macOS) — bukan pengganti tes core (114 di RespiteCore),
/// tapi jaring pengaman regressi alur utama: launch, navigasi modul via
/// shortcut, About, dan Settings → tab Pembaruan.
/// Bahasa asumsi: English (development region; mesin dev English).
final class RespiteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchAndWait() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        // Direct-exec launch: window muncul via self-heal `open` ±2 dtk.
        // Kalau throttle aktivasi macOS bikin gagal sekali, coba activate
        // dari runner sekali lagi sebelum menyerah.
        var window = app.windows.firstMatch
        if !window.waitForExistence(timeout: 20) {
            app.activate()
            window = app.windows.firstMatch
        }
        XCTAssertTrue(window.waitForExistence(timeout: 15), "window utama harus muncul saat launch")
        return app
    }

    /// Launch → branding sidebar + hero CTA Beranda terlihat.
    func testLaunchShowsHome() throws {
        let app = launchAndWait()
        XCTAssertTrue(app.staticTexts["Respite"].firstMatch.exists, "branding Respite di sidebar")
        // Hero CTA di Beranda (English-first).
        let scan = app.buttons["Clean Up My Mac"]
        XCTAssertTrue(scan.waitForExistence(timeout: 10), "CTA 'Clean Up My Mac' di Beranda")
    }

    /// ⌘1..⌘9 memindahkan modul tanpa crash — spot-check tiap tujuan.
    func testModuleShortcutsNavigate() throws {
        let app = launchAndWait()

        // ⌘1 → Beranda (CTA scan ada).
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Clean Up My Mac"].waitForExistence(timeout: 8))

        // ⌘2 → Bersihkan Cepat: tombol Start Scan.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Start Scan"].waitForExistence(timeout: 8), "modul Bersihkan Cepat")

        // ⌘3 → File Besar: halaman memakai pola mulai yang sama.
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Start Scan"].waitForExistence(timeout: 8), "modul File Besar")

        // ⌘4..⌘9: cukup assert app masih hidup (window ada) tiap lompatan.
        for key in ["4", "5", "6", "7", "8", "9"] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertTrue(app.windows.firstMatch.exists, "window tetap ada setelah ⌘\(key)")
        }
    }

    /// About window via chip versi "1.2" di sidebar (menu bar API XCUITest
    /// di macOS ini flaky — jalur chip mengetes flow yang sama).
    func testAboutWindow() throws {
        let app = launchAndWait()
        let chip = app.buttons["1.2"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "chip versi di sidebar")
        chip.click()

        let version = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Version' OR value CONTAINS 'Version'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10), "About window menampilkan versi")
    }

    /// Settings (⌘,) → tab Updates → tombol Check for Updates ada.
    func testSettingsUpdatesTab() throws {
        let app = launchAndWait()
        app.typeKey(",", modifierFlags: .command)
        // Window Settings (SwiftUI Settings scene).
        let settingsWindow = app.windows.firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 8))

        let updatesTab = app.buttons["Updates"]
        XCTAssertTrue(updatesTab.waitForExistence(timeout: 8), "tab Updates di Settings")
        updatesTab.click()
        XCTAssertTrue(
            app.buttons["Check for Updates…"].waitForExistence(timeout: 8),
            "tombol Check for Updates (manual-only) di tab Updates"
        )
    }
}

