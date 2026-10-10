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
            ToolCard {
                Text(NSLocalizedString("Mau mengelap keyboard atau layar? Kunci keyboard dulu supaya tidak ada tombol yang tertekan. Trackpad dan mouse tetap bisa dipakai.", comment: ""))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    lock.isLocked
                        ? NSLocalizedString("Saat ini: keyboard terkunci", comment: "")
                        : NSLocalizedString("Saat ini: keyboard bisa dipakai seperti biasa", comment: ""),
                    systemImage: lock.isLocked ? "lock.fill" : "lock.open"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(lock.isLocked ? Color.mint : Color.secondary)

                HStack(spacing: DKSpacing.md) {
                    Text(NSLocalizedString("Buka sendiri setelah", comment: ""))
                        .font(.callout)
                    Picker("", selection: $lockSeconds) {
                        ForEach(durationOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                }

                Button {
                    lock.lock(autoUnlockAfter: lockSeconds > 0 ? TimeInterval(lockSeconds) : nil)
                } label: {
                    Label(
                        lock.isLocked
                            ? NSLocalizedString("Keyboard sedang terkunci", comment: "")
                            : NSLocalizedString("Kunci Keyboard Sekarang", comment: ""),
                        systemImage: "lock"
                    )
                    .frame(minWidth: 180)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color.mint)
                .disabled(lock.isLocked)

                Divider()

                VStack(alignment: .leading, spacing: DKSpacing.sm) {
                    Text(NSLocalizedString("Cara membuka kunci:", comment: ""))
                        .font(.callout.weight(.semibold))
                    exitRow(icon: "hand.tap", text: NSLocalizedString("Tekan dan tahan tombol di layar selama 1 detik", comment: ""))
                    exitRow(icon: "timer", text: NSLocalizedString("Atau tunggu waktunya habis — terbuka sendiri", comment: ""))
                    exitRow(icon: "command", text: NSLocalizedString("Darurat: tekan ⌘⌥L", comment: ""))
                }
            }

            ToolDetails {
                Text(NSLocalizedString("Paksa keluar Respite — kunci hilang sendiri", comment: ""))
                Text(NSLocalizedString("Overlay menahan input selama aktif, bukan mematikan keyboard di level hardware — tidak ada state yang tertinggal.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
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
