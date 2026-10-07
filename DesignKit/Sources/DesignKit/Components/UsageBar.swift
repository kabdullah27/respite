import SwiftUI

/// Bar pemakaian tipis — cara paling universal buat nunjukin "berapa penuh"
/// tanpa harus ngerti angka (ramah buat semua umur).
public struct UsageBar: View {
    let fraction: Double
    let color: Color

    /// - Parameters:
    ///   - fraction: 0...1, di-clamp otomatis.
    ///   - color: warna isi bar — biasanya `DKColor.accent`, amber kalau butuh perhatian.
    public init(fraction: Double, color: Color? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        self.color = color ?? DKColor.accent
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true) // info lengkap dibawa label konteks di caller
    }
}
