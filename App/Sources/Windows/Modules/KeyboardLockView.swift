import SwiftUI
import RespiteCore
import DesignKit

/// Kunci Keyboard: tahan semua ketukan keyboard selama layar kunci aktif
/// (pola KeyboardCleanTool). Trackpad & mouse tidak pernah disentuh.
struct KeyboardLockView: View {
    @ObservedObject private var lock = KeyboardLockController.shared

    /// Durasi kunci — 0 = tanpa timer (manual). Default 2 menit.
    @AppStorage("app.respite.keyboardLock.seconds") private var lockSeconds = 120

    private let durationOptions: [(seconds: Int, label: String)] = [
        (60, NSLocalizedString("1 menit", comment: "")),
        (120, NSLocalizedString("2 menit", comment: "")),
        (180, NSLocalizedString("3 menit", comment: "")),
        (300, NSLocalizedString("5 menit", comment: "")),
        (0, NSLocalizedString("Tanpa timer", comment: "")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.mint)
                    .frame(width: 44, height: 44)
                    .background(Color.mint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Kunci Keyboard", comment: ""))
                        .font(.title3.weight(.semibold))
                    Text(NSLocalizedString("bersihkan layar & keyboard tanpa salah tekan", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if lock.isLocked {
                    Label(NSLocalizedString("Terkunci", comment: ""), systemImage: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.mint)
                }
            }

            Text(NSLocalizedString("Menahan semua ketukan keyboard selama layar kunci aktif — trackpad & mouse tetap berfungsi.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DKSpacing.md) {
                Text(NSLocalizedString("Buka otomatis setelah", comment: ""))
                    .font(.callout)
                Picker("", selection: $lockSeconds) {
                    ForEach(durationOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
            }

            Button {
                lock.lock(autoUnlockAfter: lockSeconds > 0 ? TimeInterval(lockSeconds) : nil)
            } label: {
                Label(
                    lock.isLocked
                        ? NSLocalizedString("Sudah Terkunci — buka di layar penuh", comment: "")
                        : NSLocalizedString("Kunci Keyboard Sekarang", comment: ""),
                    systemImage: "lock"
                )
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Color.mint)
            .disabled(lock.isLocked)

            Divider()

            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                Text(NSLocalizedString("Cara keluar (semua via trackpad):", comment: ""))
                    .font(.callout.weight(.semibold))
                exitRow(icon: "hand.tap", text: NSLocalizedString("Tahan tombol di layar selama 1 detik", comment: ""))
                exitRow(icon: "timer", text: NSLocalizedString("Tunggu timer habis — terbuka sendiri, plus notifikasi", comment: ""))
                exitRow(icon: "command", text: NSLocalizedString("⌘⌥L — pintasan darurat yang tetap jalan saat terkunci", comment: ""))
                exitRow(icon: "xmark.app", text: NSLocalizedString("Paksa keluar Respite — kunci hilang sendiri", comment: ""))
            }

            Text(NSLocalizedString("Overlay menahan input selama aktif, bukan mematikan keyboard di level hardware — tidak ada state yang tertinggal.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exitRow(icon: String, text: String) -> some View {
        HStack(spacing: DKSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.mint)
                .frame(width: 20)
            Text(text).font(.callout)
        }
    }
}
