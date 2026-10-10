import SwiftUI
import RespiteCore
import DesignKit

/// Nyala saat lid dibuka — setting firmware NVRAM AutoBoot.
/// Perubahan selalu lewat dialog admin standar macOS — password tidak
/// pernah disimpan aplikasi.
struct PowerLidView: View {
    @State private var bootState: AutoBootSetting.State = AutoBootSetting.read()
    @State private var isChanging = false
    @State private var errorText: String?
    @State private var successText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            ToolCard {
                Text(NSLocalizedString("Biasanya Mac langsung menyala begitu layarnya dibuka atau charger dicolok — kadang malah menyala sendiri di dalam tas. Kamu bisa mengaturnya supaya Mac hanya menyala setelah tombol power ditekan.", comment: ""))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                Label(statusLabel, systemImage: statusSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(bootState == .unknown ? DKColor.attention : Color.indigo)
                    .fixedSize(horizontal: false, vertical: true)

                // Satu tombol kontekstual — labelnya mengikuti aksi yang tersedia.
                Button {
                    change(to: bootState == .disabled)
                } label: {
                    Label(
                        bootState == .disabled
                            ? NSLocalizedString("Nyalakan sendiri saat dibuka", comment: "")
                            : NSLocalizedString("Hanya nyala saat tombol power ditekan", comment: ""),
                        systemImage: bootState == .disabled ? "power" : "power.dotted"
                    )
                    .frame(minWidth: 180)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color.indigo)
                .disabled(isChanging || bootState == .unknown)

                Text(NSLocalizedString("macOS akan meminta password Mac kamu untuk menyimpan perubahan ini.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if isChanging {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Menunggu password kamu…", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(DKColor.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let successText {
                    Label(successText, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(Color.respite)
                }
            }

            ToolDetails {
                Text(NSLocalizedString("Setting firmware (NVRAM) — berlaku untuk semua akun", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("Setiap perubahan memunculkan dialog admin macOS — password tidak pernah disimpan aplikasi. Menguji: matikan Mac penuh → tutup lid → buka lid — kalau tidak menyala, setting berhasil.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { bootState = AutoBootSetting.read() }
    }

    private var isCurrentlyEnabled: Bool {
        bootState == .enabled || bootState == .enabledDefault
    }

    private var isCurrentlyDisabled: Bool {
        bootState == .disabled
    }

    private var statusLabel: String {
        switch bootState {
        case .enabled, .enabledDefault:
            return NSLocalizedString("Saat ini: Mac menyala sendiri saat dibuka", comment: "")
        case .disabled:
            return NSLocalizedString("Saat ini: Mac hanya menyala setelah tombol power ditekan", comment: "")
        case .unknown:
            return NSLocalizedString("Saat ini: pengaturan ini tidak bisa dibaca di Mac kamu", comment: "")
        }
    }

    private var statusSymbol: String {
        switch bootState {
        case .enabled, .enabledDefault: return "power"
        case .disabled: return "power.dotted"
        case .unknown: return "questionmark.circle"
        }
    }

    private func change(to enabled: Bool) {
        isChanging = true
        errorText = nil
        successText = nil
        Task.detached(priority: .userInitiated) {
            do {
                try AutoBootSetting.set(enabled)
                let fresh = AutoBootSetting.read()
                await MainActor.run {
                    bootState = fresh
                    successText = NSLocalizedString("Tersimpan. Status di atas sudah diperbarui.", comment: "")
                    isChanging = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isChanging = false
                }
            }
        }
    }
}
