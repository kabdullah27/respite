import XCTest
import ImageIO
import CoreGraphics
@testable import RespiteCore

final class SimilarPhotosTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-photo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Pure math

    func testHamming() {
        XCTAssertEqual(SimilarPhotosScanner.hamming(0b1010, 0b1010), 0)
        XCTAssertEqual(SimilarPhotosScanner.hamming(0b1010, 0b0101), 4)
        XCTAssertEqual(SimilarPhotosScanner.hamming(0, ~UInt64(0)), 64)
    }

    private func photo(_ phash: UInt64) -> PhotoItem {
        PhotoItem(url: URL(fileURLWithPath: "/tmp/x-\(phash).jpg"), sizeBytes: 100, lastModified: .distantPast, phash: phash)
    }

    func testClusterGabungYangMirip() {
        // A & B identik, C beda 2 bit (masih ≤ 6), D beda jauh.
        let a: UInt64 = 0xFFFFFFFFFFFFFFFF
        let b = a
        let c: UInt64 = a ^ 0b11           // jarak 2
        let d: UInt64 = 0b0000000000000001 // jarak jauh dari a
        let clusters = SimilarPhotosScanner.cluster(
            items: [photo(a), photo(b), photo(c), photo(d)],
            hammingThreshold: 6
        )
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].count, 3, "A, B, C satu klaster; D sendirian dibuang")
    }

    // MARK: Foto sungguhan

    /// Bikin PNG via CoreGraphics (tanpa AppKit — core tetap UI-free).
    private func makePNG(_ name: String, draw: (CGContext, CGFloat) -> Void) throws -> URL {
        let size = 64
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(ctx, CGFloat(size))
        let image = ctx.makeImage()!
        let url = root.appendingPathComponent(name)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return url
    }

    func testFotoIdentikTergrup() throws {
        func gradient(_ ctx: CGContext, _ size: CGFloat) {
            for i in 0..<8 {
                let shade = CGFloat(i) / 8
                ctx.setFillColor(CGColor(gray: shade, alpha: 1))
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * size / 8, width: size, height: size / 8))
            }
        }
        // Dua file dengan GAMBAR sama (byte PNG beda — ditulis dua kali).
        let a = try makePNG("a.png", draw: gradient)
        let b = try makePNG("b.png", draw: gradient)
        // Foto yang jelas beda: pola noise kotak-kotak.
        let c = try makePNG("noise.png") { ctx, size in
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for i in 0..<8 {
                ctx.setFillColor(CGColor(gray: (i % 2 == 0) ? 0.0 : 1.0, alpha: 1))
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * size / 8, width: size, height: size / 8))
            }
        }

        let items = [a, b, c].compactMap { url -> PhotoItem? in
            guard let hash = SimilarPhotosScanner.averageHash(url) else { return nil }
            return PhotoItem(url: url, sizeBytes: 100, lastModified: .distantPast, phash: hash)
        }
        XCTAssertEqual(items.count, 3)

        let clusters = SimilarPhotosScanner.cluster(items: items, hammingThreshold: 6)
        XCTAssertEqual(clusters.count, 1, "dua foto identik harus satu klaster, noise terpisah")
        XCTAssertEqual(clusters[0].count, 2)
    }
}
