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
            Text(NSLocalizedString("Hapus selamanya?", comment: ""))
                .font(.title3.weight(.semibold))
            Text(String(
                format: NSLocalizedString("%d item (%@) akan dihapus selamanya. File ini tidak masuk Trash dan tidak bisa dikembalikan. Kalau masih ragu, pilih Batal.", comment: ""),
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

            Text(NSLocalizedString("Ketik kata hapus di kotak di atas supaya tombolnya aktif.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: DKSpacing.md) {
                Button(NSLocalizedString("Batal", comment: ""), action: onCancel)
                Button(NSLocalizedString("Hapus Permanen", comment: ""), role: .destructive) {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .tint(DKColor.irreversible)
                // Kata konfirmasi ikut bahasa UI ("delete" / "hapus"); "hapus"
                // tetap diterima di bahasa mana pun.
                .disabled(!Self.confirmWords.contains(confirmText.trimmedLower))
            }
        }
        .padding(DKSpacing.xl)
        .frame(width: 440, height: 380)
    }
}

extension PermanentDeleteConfirmSheet {
    static var confirmWords: Set<String> {
        [NSLocalizedString("hapus", comment: "Kata yang harus diketik untuk konfirmasi hapus permanen").lowercased(), "hapus"]
    }
}

extension String {
    var trimmedLower: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
