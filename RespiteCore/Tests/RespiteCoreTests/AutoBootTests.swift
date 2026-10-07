import XCTest
@testable import RespiteCore

/// Nilai NVRAM → state — murni, tanpa sentuh NVRAM beneran.
final class AutoBootTests: XCTestCase {
    func testParseNilaiFirmware() {
        XCTAssertEqual(AutoBootSetting.parse("%00"), .disabled)
        XCTAssertEqual(AutoBootSetting.parse("%03"), .enabled)
        XCTAssertEqual(AutoBootSetting.parse(""), .enabledDefault)
    }

    func testNilaiTakDikenalTidakDisimpulkan() {
        XCTAssertEqual(AutoBootSetting.parse("%07"), .unknown)
    }
}
