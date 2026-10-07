import SwiftUI

/// Kartu metrik respite — dipake di menu bar dropdown, dashboard, dst.
public struct MetricCard: View {
    let title: String
    let value: String
    let unit: String

    public init(title: String, value: String, unit: String) {
        self.title = title; self.value = value; self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.xs) {
            Text(title).font(.caption).foregroundColor(.secondary)
            (Text(value).font(.dkData(20)) + Text(" \(unit)").font(.caption).foregroundColor(.secondary))
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.control))
    }
}
