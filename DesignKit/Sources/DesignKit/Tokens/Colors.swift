import SwiftUI

public enum DKColor {
    /// Selalu pakai accent warna sistem — jangan pernah define warna brand tetap di sini.
    public static var accent: Color { Color.accentColor }

    public static let neutral = Color(nsColor: .secondaryLabelColor)
    /// Butuh perhatian, TAPI bukan darurat — misal notifikasi maintenance, confidence rendah.
    public static let attention = Color(nsColor: .systemOrange)
    /// HANYA buat konfirmasi final yang nggak bisa di-undo. Jangan dipake buat notifikasi rutin.
    public static let irreversible = Color(nsColor: .systemRed)

    public static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    public static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
}
