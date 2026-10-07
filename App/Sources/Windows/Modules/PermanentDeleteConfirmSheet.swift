import SwiftUI
import RespiteCore
import DesignKit

/// Konfirmasi berlapis buat SEMUA aksi irreversible (guardrails poin 5):
/// peringatan merah + user harus mengetik "hapus" sebelum tombol aktif.
/// Dipakai Trash Manager & Shredder.
struct PermanentDeleteConfirmSheet: View {
    let itemCount: Int
    let totalBytes: Int64
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var confirmText = ""

    var body: some View {
        VStack(spacing: DKSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DKColor.irreversible)
            Text(NSLocalizedString("Hapus permanen dari Trash?", comment: ""))
                .font(.title3.weight(.semibold))
            Text(String(
                format: NSLocalizedString("%d item (%@) akan dihapus selamanya — melewati Trash, TIDAK BISA DIBATALKAN dengan cara apa pun. Kalau masih ragu, batalkan dan kelola lewat Finder.", comment: ""),
                itemCount,
                ByteFormat.string(from: totalBytes)
            ))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            TextField(
                NSLocalizedString("Ketik \"hapus\" untuk mengonfirmasi", comment: ""),
                text: $confirmText
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 260)

            HStack(spacing: DKSpacing.md) {
                Button(NSLocalizedString("Batal", comment: ""), action: onCancel)
                Button(NSLocalizedString("Hapus Permanen", comment: ""), role: .destructive) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(DKColor.irreversible)
                .disabled(confirmText.trimmedLower != "hapus")
            }
        }
        .padding(DKSpacing.xl)
        .frame(width: 440, height: 360)
    }
}

extension String {
    var trimmedLower: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
