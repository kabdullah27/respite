import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Onboarding first-run (PRD §8, Design Spec §8.2): tiga langkah singkat —
/// welcome, permintaan Full Disk Access DENGAN alasan konkret + status live,
/// dan prinsip privasi. Ditampilkan sekali (flag UserDefaults).
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    @State private var fdaGranted: Bool?

    private let fdaPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DKColor.accent)
                Text("Respite").font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(DKSpacing.xl)

            Divider()

            Group {
                switch step {
                case 0: welcomePage
                case 1: accessPage
                default: privacyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(DKSpacing.xl)

            Divider()

            HStack(spacing: DKSpacing.md) {
                if step > 0 {
                    Button(NSLocalizedString("Kembali", comment: "")) { step -= 1 }
                }
                Spacer()
                HStack(spacing: DKSpacing.xs) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == step ? DKColor.accent : Color.primary.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button(step < 2 ? NSLocalizedString("Lanjut", comment: "") : NSLocalizedString("Mulai menggunakan Respite", comment: "")) {
                    if step < 2 {
                        step += 1
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(DKSpacing.md)
        }
        .frame(width: 500, height: 420)
        .onAppear { refreshFDAStatus() }
    }

    // MARK: Halaman 1 — Selamat datang

    private var welcomePage: some View {
        VStack(spacing: DKSpacing.lg) {
            FeatureRow(symbol: "tray.full", text: NSLocalizedString("Pindai cache, file besar, sisa aplikasi, dan cache developer — lengkap dengan alasan kenapa aman dihapus.", comment: ""))
            FeatureRow(symbol: "waveform.path.ecg", text: NSLocalizedString("Diagnosis kenapa Mac lambat saat ini — dari data sungguhan, bukan angka menakut-nakuti.", comment: ""))
            FeatureRow(symbol: "trash", text: NSLocalizedString("Semua penghapusan pergi ke Trash dan bisa dibatalkan — bukan dihapus permanen.", comment: ""))
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    // MARK: Halaman 2 — Full Disk Access

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            Text(NSLocalizedString("Respite membutuhkan Akses Disk Penuh untuk memindai ~/Library/Caches, Trash, dan sisa data aplikasi secara utuh. Tanpa itu, sebagian hasil pindai bisa kosong.", comment: ""))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DKSpacing.sm) {
                Image(systemName: fdaStatusIcon)
                    .foregroundStyle(fdaStatusColor)
                Text(fdaStatusText).font(.callout.weight(.medium))
                Spacer()
                Button(NSLocalizedString("Periksa ulang", comment: "")) {
                    refreshFDAStatus()
                }
                .controlSize(.small)
            }
            .padding(DKSpacing.md)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.control))

            Button {
                NSWorkspace.shared.open(fdaPaneURL)
            } label: {
                Label(NSLocalizedString("Buka Pengaturan Privasi", comment: ""), systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Text(NSLocalizedString("Aktifkan Respite di daftar Akses Disk Penuh, lalu kembali ke sini. Bisa juga nanti lewat Pengaturan sistem — sebagian fitur tetap berfungsi.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var fdaStatusIcon: String {
        switch fdaGranted {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle"
        case nil: return "questionmark.circle"
        }
    }

    private var fdaStatusColor: Color {
        switch fdaGranted {
        case .some(true): return DKColor.accent
        case .some(false): return DKColor.attention
        case nil: return DKColor.neutral
        }
    }

    private var fdaStatusText: String {
        switch fdaGranted {
        case .some(true): return NSLocalizedString("Akses Disk Penuh aktif", comment: "")
        case .some(false): return NSLocalizedString("Akses Disk Penuh belum aktif", comment: "")
        case nil: return NSLocalizedString("Status tidak dapat dipastikan", comment: "")
        }
    }

    private func refreshFDAStatus() {
        fdaGranted = FullDiskAccess.likelyGranted()
    }

    // MARK: Halaman 3 — Privasi

    private var privacyPage: some View {
        VStack(spacing: DKSpacing.lg) {
            FeatureRow(symbol: "antenna.slash", text: NSLocalizedString("Tanpa telemetri — tidak ada data yang dikirim ke mana pun. Satu-satunya permintaan jaringan (nanti) hanya pemeriksaan pembaruan.", comment: ""))
            FeatureRow(symbol: "lock", text: NSLocalizedString("Semua proses berjalan lokal di Mac kamu.", comment: ""))
            FeatureRow(symbol: "shield", text: NSLocalizedString("Folder pribadi (Documents, Desktop, Keychain, Mail) tidak pernah masuk pemindaian — batas keras yang tidak bisa dimatikan.", comment: ""))
        }
        .frame(maxWidth: 400, alignment: .leading)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DKSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DKColor.accent)
                .frame(width: 26)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
