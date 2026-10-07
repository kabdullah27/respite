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
            HStack(spacing: DKSpacing.md) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.indigo)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Nyala saat dibuka", comment: ""))
                        .font(.title3.weight(.semibold))
                    Text(NSLocalizedString("Setting firmware (NVRAM) — berlaku untuk semua akun", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(statusLabel)
                    .font(.dkData(12))
                    .foregroundColor(.secondary)
            }

            Text(NSLocalizedString("Secara pabrik, Mac menyala sendiri begitu lid dibuka (atau charger dicolok) — kadang nyala sendiri di dalam tas. Matikan ini kalau kamu ingin Mac hanya menyala setelah tombol power ditekan.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Satu tombol kontekstual — labelnya mengikuti aksi yang tersedia.
            Button {
                change(to: bootState == .disabled)
            } label: {
                Label(
                    bootState == .disabled
                        ? NSLocalizedString("Aktifkan Nyala-otomatis", comment: "")
                        : NSLocalizedString("Nonaktifkan — butuh tekan power", comment: ""),
                    systemImage: bootState == .disabled ? "power" : "power.dotted"
                )
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .disabled(isChanging || bootState == .unknown)

            if isChanging {
                HStack(spacing: DKSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(NSLocalizedString("Menunggu dialog admin…", comment: ""))
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

            Text(NSLocalizedString("Setiap perubahan memunculkan dialog admin macOS — password tidak pernah disimpan aplikasi. Menguji: matikan Mac penuh → tutup lid → buka lid — kalau tidak menyala, setting berhasil.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            return NSLocalizedString("Aktif (default pabrik)", comment: "")
        case .disabled:
            return NSLocalizedString("Nonaktif — harus tekan power", comment: "")
        case .unknown:
            return NSLocalizedString("tidak dapat dibaca", comment: "")
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
                    successText = NSLocalizedString("Diterapkan — status di atas dibaca ulang dari firmware.", comment: "")
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
