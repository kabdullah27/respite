import XCTest
@testable import RespiteCore

final class DeepLinkTests: XCTestCase {
    func testParseActionValid() {
        XCTAssertEqual(
            DeepLink.action(from: URL(string: "respite://action/run-diagnostic")!),
            .runDiagnostic
        )
        XCTAssertEqual(
            DeepLink.action(from: URL(string: "respite://action/maintenance-sweep")!),
            .maintenanceSweep
        )
        XCTAssertEqual(
            DeepLink.action(from: URL(string: "respite://action/free-memory")!),
            .freeMemory
        )
    }

    func testSkemaDanAksiTakDikenalDitolak() {
        XCTAssertNil(DeepLink.action(from: URL(string: "respite://bukan/action")!))
        XCTAssertNil(DeepLink.action(from: URL(string: "other://action/run-diagnostic")!))
        XCTAssertNil(DeepLink.action(from: URL(string: "respite://action/hapus-semua")!),
                     "aksi tak dikenal tidak boleh lolos — apalagi yang berbahaya")
        XCTAssertNil(DeepLink.action(from: URL(string: "respite://action")!))
    }
}
