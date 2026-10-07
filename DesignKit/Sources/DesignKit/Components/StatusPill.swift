import SwiftUI

/// Badge kapsul kecil buat status ("Sehat", "Perlu perhatian", "Baru").
public struct StatusPill: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, DKSpacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
