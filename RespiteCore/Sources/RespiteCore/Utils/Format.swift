import Foundation

public enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.isAdaptive = true
        // "0 KB", bukan "Zero KB" / "Nol KB".
        f.allowsNonnumericFormatting = false
        return f
    }()

    /// "12,4 GB" — ikut locale user secara otomatis (desimal koma di ID).
    public static func string(from bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }

    public static func string(from bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(clamping: bytes))
    }
}
