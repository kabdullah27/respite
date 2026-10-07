import SwiftUI

/// Empty state yang didesain — icon di squircle tinted + judul + pesan.
/// Dipake buat modul yang belum diimplement & state "belum ada data".
public struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    public init(symbol: String, title: String, message: String) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DKSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(DKColor.accent)
                .frame(width: 64, height: 64)
                .background(DKColor.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(DKSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
