import SwiftUI

public extension Font {
    /// Pakai buat SEMUA angka data (size, persentase, durasi, count) di app manapun.
    static func dkData(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
