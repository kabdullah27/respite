import SwiftUI

/// Pola list item khas: angka monospace + deskripsi. Dipake di semua list hasil/status.
public struct ReadoutRow: View {
    let value: String
    let unit: String?
    let label: String
    let detail: String?
    let badge: String?

    public init(value: String, unit: String? = nil, label: String, detail: String? = nil, badge: String? = nil) {
        self.value = value; self.unit = unit; self.label = label; self.detail = detail; self.badge = badge
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DKSpacing.md) {
            (Text(value).font(.dkData(15))
             + Text(unit.map { " \($0)" } ?? "").font(.caption).foregroundColor(.secondary))
                .frame(minWidth: 64, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DKSpacing.xs) {
                    Text(label).font(.body)
                    // Dipake buat Recency Guard ("Baru") atau flag confidence rendah lainnya —
                    // sengaja pakai DKColor.attention (amber), bukan warna badge custom per-app.
                    if let badge {
                        Text(badge).font(.caption2.weight(.medium))
                            .padding(.horizontal, DKSpacing.xs).padding(.vertical, 1)
                            .background(DKColor.attention.opacity(0.15))
                            .foregroundColor(DKColor.attention)
                            .clipShape(Capsule())
                    }
                }
                if let detail { Text(detail).font(.caption).foregroundColor(.secondary) }
            }
        }
    }
}
