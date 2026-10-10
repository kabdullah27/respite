import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Onboarding first-run (PRD §8, Design Spec §8.2): tiga langkah singkat —
/// apa yang dilakukan Respite, janji keamanan (tidak ada yang dihapus tanpa
/// persetujuan, semua ke Trash), lalu izin akses file (opsional) dengan
/// status live. Ditampilkan sekali (flag UserDefaults).
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
                case 1: safetyPage
                default: accessPage
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
                Button(step < 2 ? NSLocalizedString("Lanjut", comment: "") : NSLocalizedString("Mulai pakai Respite", comment: "")) {
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
        .frame(width: 520, height: 460)
        .onAppear { refreshFDAStatus() }
    }

    // MARK: Langkah 1 — Apa yang dilakukan Respite

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            pageTitle(NSLocalizedString("Bikin Mac kamu lega dan lancar lagi", comment: ""))
            FeatureRow(symbol: "sparkles", text: NSLocalizedString("Cari file yang tidak terpakai — file sementara, file besar, dan sisa aplikasi.", comment: ""))
            FeatureRow(symbol: "questionmark.circle", text: NSLocalizedString("Jelaskan kenapa Mac terasa lambat, dengan bahasa sederhana.", comment: ""))
            FeatureRow(symbol: "lock", text: NSLocalizedString("Semua berjalan di Mac kamu. Tidak ada data yang dikirim ke mana pun.", comment: ""))
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    // MARK: Langkah 2 — Aman

    private var safetyPage: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            pageTitle(NSLocalizedString("Tidak ada yang dihapus tanpa persetujuanmu", comment: ""))
            FeatureRow(symbol: "checkmark.circle", text: NSLocalizedString("Kamu selalu melihat daftarnya dulu dan memilih sendiri apa yang dibuang.", comment: ""))
            FeatureRow(symbol: "trash", text: NSLocalizedString("Semuanya masuk ke Trash, jadi bisa dikembalikan kapan saja.", comment: ""))
            FeatureRow(symbol: "shield", text: NSLocalizedString("Dokumen pribadi dan file sistem tidak pernah disentuh.", comment: ""))
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private func pageTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Langkah 3 — Izin akses file (opsional)

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            pageTitle(NSLocalizedString("Izinkan akses file (boleh nanti)", comment: ""))
            Text(NSLocalizedString("Supaya Respite bisa menemukan semua file yang bisa dibersihkan, beri izin \"Akses Disk Penuh\". Tanpa izin ini, sebagian hasil bisa kosong.", comment: ""))
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

            Text(NSLocalizedString("Nyalakan Respite di daftar Akses Disk Penuh, lalu kembali ke sini. Boleh dilewati — sebagian besar fitur tetap bisa dipakai.", comment: ""))
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
        case .some(true): return NSLocalizedString("Izin sudah diberikan", comment: "")
        case .some(false): return NSLocalizedString("Izin belum diberikan", comment: "")
        case nil: return NSLocalizedString("Belum bisa dipastikan", comment: "")
        }
    }

    private func refreshFDAStatus() {
        fdaGranted = FullDiskAccess.likelyGranted()
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
