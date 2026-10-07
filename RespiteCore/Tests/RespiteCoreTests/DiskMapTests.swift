import XCTest
import CoreGraphics
@testable import RespiteCore

final class SquarifyTests: XCTestCase {
    func testTotalAreaTerjaga() {
        let sizes: [Double] = [50, 25, 12.5, 6.25, 6.25]
        let canvas = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let rects = Squarify.layout(sizes: sizes, in: canvas)

        XCTAssertEqual(rects.count, sizes.count)
        let area = rects.map { $0.width * $0.height }.reduce(0, +)
        XCTAssertEqual(area, canvas.width * canvas.height, accuracy: 1.0,
                       "area total harus mengisi canvas persis")
    }

    func testSemuaRectDalamCanvas() {
        let sizes: [Double] = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
        let canvas = CGRect(x: 5, y: 5, width: 400, height: 300)
        let rects = Squarify.layout(sizes: sizes, in: canvas)
        for rect in rects {
            XCTAssertTrue(canvas.contains(rect.insetBy(dx: 0.001, dy: 0.001)),
                          "rect \(rect) keluar dari canvas")
        }
    }

    func testSatuItemIsiPenuh() {
        let rects = Squarify.layout(sizes: [42], in: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(rects[0], CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testInputKosongDanNol() {
        XCTAssertTrue(Squarify.layout(sizes: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        XCTAssertEqual(Squarify.layout(sizes: [0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)).count, 2)
    }
}

final class DiskMapScannerTests: XCTestCase {
    func testAnakPerLevelSortedDesc() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-dmap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Gede/sub"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Kecil"),
            withIntermediateDirectories: true
        )
        try Data(count: 900).write(to: root.appendingPathComponent("Gede/file-a"))
        try Data(count: 500).write(to: root.appendingPathComponent("Gede/sub/file-b"))
        try Data(count: 50).write(to: root.appendingPathComponent("Kecil/x"))
        try Data(count: 10).write(to: root.appendingPathComponent("lebih-kecil.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let items = DiskMapScanner.children(of: root)

        XCTAssertEqual(items.first?.name, "Gede", "folder terbesar duluan")
        XCTAssertEqual(items.first?.sizeBytes, 1400, "ukuran folder = jumlah isi (rekursif)")
        XCTAssertTrue(items.first?.isDirectory ?? false)
        XCTAssertEqual(items.map(\.name), ["Gede", "Kecil", "lebih-kecil.txt"])
    }
}
