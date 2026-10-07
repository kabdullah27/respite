import XCTest
@testable import RespiteCore

/// UpdateChecker — perbandingan versi murni + parsing payload (network di-inject).
final class UpdateCheckerTests: XCTestCase {
    override func tearDown() {
        UpdateChecker.dataProvider = { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
        super.tearDown()
    }

    func testVersiBaruLebihTinggi() {
        XCTAssertTrue(UpdateChecker.isVersion("1.1.0", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.2"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.1", newerThan: "1.0"))
    }

    func testVersiSamaAtauLebihRendah() {
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0.0", newerThan: "1.0.1"))
        XCTAssertFalse(UpdateChecker.isVersion("0.9", newerThan: "1.0"))
    }

    func testPrefixVDiabaikan() {
        XCTAssertTrue(UpdateChecker.isVersion("v1.2.0", newerThan: "1.1.9"))
        XCTAssertEqual(UpdateChecker.normalize(" V2.0 "), "2.0")
    }

    func testParsingPayloadDanFlag() async throws {
        let json = """
        {"tag_name":"v1.2.0","html_url":"https://github.com/x/y/releases/tag/v1.2.0","published_at":"2026-09-01T10:00:00Z"}
        """
        UpdateChecker.dataProvider = { _ in Data(json.utf8) }
        let info = try await UpdateChecker.check(
            feedURL: URL(string: "https://example.com/latest")!,
            currentVersion: "1.1.0"
        )
        XCTAssertEqual(info.latestVersion, "1.2.0")
        XCTAssertTrue(info.isUpdateAvailable)
        XCTAssertEqual(info.releasePageURL?.absoluteString, "https://github.com/x/y/releases/tag/v1.2.0")
    }

    func testPayloadRusakJadiErrorJelas() async {
        UpdateChecker.dataProvider = { _ in Data("404: not found".utf8) }
        do {
            _ = try await UpdateChecker.check(
                feedURL: URL(string: "https://example.com/latest")!,
                currentVersion: "1.0.0"
            )
            XCTFail("harusnya melempar badPayload")
        } catch {
            XCTAssertEqual(error as? UpdateChecker.CheckError, .badPayload)
        }
    }
}
