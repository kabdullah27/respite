import AppKit
import ImageIO

/// Thumbnail hemat via ImageIO (decode di-downscale langsung dari source,
/// bukan load full lalu resize) + NSCache biar scroll bolak-balik ringan.
enum PhotoThumbnail {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL, maxPixel: Int = 56) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) {
            return hit
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
