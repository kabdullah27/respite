import SwiftUI
import RespiteCore
import DesignKit

extension Color {
    /// Aksen produk Respite (teal) — dipakai status, tombol utama, centang.
    static let respite = Color(red: 0.10, green: 0.58, blue: 0.46)
}

/// Beranda — dibaca dari atas ke bawah dalam 5 detik:
///   1. Kondisi Mac (satu kalimat + warna)
///   2. Penyimpanan + SATU tombol utama "Bersihkan Mac Sekarang"
///   3. Saran yang relevan dengan kondisi sekarang
///   4. Daftar alat per tujuan
struct HomeView: View {
    @ObservedObject var model: SystemStatsModel
    @Binding var selectedModule: Module?

    private let columns = [
        GridItem(.flexible(), spacing: DKSpacing.md),
        GridItem(.flexible(), spacing: DKSpacing.md),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.xl) {
                statusCard
                storageCard
                suggestions
                toolSection(.cleaning)
                toolSection(.monitoring)
                Text(NSLocalizedString("Alat untuk pengguna lanjutan ada di menu kiri, bagian \"Alat Lain\".", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(DKSpacing.xl + 4)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 1. Kondisi Mac

    private var statusCard: some View {
        let score = model.healthScore
        let band = HealthScore.Band.band(for: score)
        let color = MacStatus.color(band)
        // Saat sehat, jangan tampilkan peringatan di kartu status (kontradiktif)
        // — saran kecil sudah muncul di bagian "Saran untuk kamu".
        let subtitle: String = {
            if band == .neutral {
                return suggestionItems.isEmpty
                    ? MacStatus.findingText(.allHealthy)
                    : NSLocalizedString("Semua berjalan normal. Ada saran kecil di bawah.", comment: "")
            }
            return model.diagnosticFindings.first.map { MacStatus.findingText($0.kind) }
                ?? MacStatus.findingText(.allHealthy)
        }()
        return HStack(spacing: DKSpacing.lg) {
            Image(systemName: MacStatus.symbol(band))
                .font(.system(size: 34))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(MacStatus.headline(band))
                    .font(.system(size: 22, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(MacStatus.scoreText(score))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Button(NSLocalizedString("Lihat penjelasan", comment: "")) {
                selectedModule = .diagnostic
            }
        }
        .padding(DKSpacing.lg + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: DKRadius.card + 4)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 4))
    }

    // MARK: 2. Penyimpanan + tombol utama

    private var storageCard: some View {
        let disk = model.snapshot.disk
        let used = 1 - disk.availableFraction
        return ToolCard {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Penyimpanan", comment: ""))
                    .font(.headline)
                Spacer()
                Text(String(
                    format: NSLocalizedString("%1$@ kosong dari %2$@", comment: ""),
                    ByteFormat.string(from: disk.availableBytes),
                    ByteFormat.string(from: disk.totalBytes)
                ))
                .font(.callout)
                .foregroundColor(.secondary)
                .monospacedDigit()
            }
            ThickBar(fraction: used, color: used >= 0.85 ? DKColor.attention : Color.respite)
            Text(String(
                format: NSLocalizedString("%d%% sudah terpakai", comment: ""),
                Int(used * 100)
            ))
            .font(.caption)
            .foregroundColor(.secondary)

            HStack(spacing: DKSpacing.md) {
                Button {
                    selectedModule = .smartScan
                } label: {
                    Label(NSLocalizedString("Bersihkan Mac Sekarang", comment: ""), systemImage: "sparkles")
                        .frame(minWidth: 220)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color.respite)
                Text(NSLocalizedString("Kamu akan melihat daftarnya dulu. Tidak ada yang dihapus tanpa persetujuanmu.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DKSpacing.xs)
        }
    }

    // MARK: 3. Saran

    /// Saran dari kondisi sekarang — kosong kalau semuanya sehat.
    private var suggestionItems: [(text: String, action: String, module: Module)] {
        model.diagnosticFindings.compactMap { finding in
            guard let action = MacStatus.action(finding.kind) else { return nil }
            return (MacStatus.findingText(finding.kind), action.title, action.module)
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let items = suggestionItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                Text(NSLocalizedString("Saran untuk kamu", comment: ""))
                    .font(.title3.weight(.semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: DKSpacing.md) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(DKColor.attention)
                        Text(item.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(item.action) { selectedModule = item.module }
                    }
                    .padding(DKSpacing.md)
                    .background(DKColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }
            }
        }
    }

    // MARK: 4. Alat per tujuan

    private func toolSection(_ section: ModuleSection) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(section.title)
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: columns, spacing: DKSpacing.md) {
                ForEach(Module.allCases.filter { $0.section == section && $0 != .home }) { module in
                    HomeToolRow(module: module) {
                        selectedModule = module
                    }
                }
            }
        }
    }
}

// MARK: - Komponen

/// Bar penyimpanan tebal — lebih mudah dibaca daripada donut.
private struct ThickBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(8, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(String(
            format: NSLocalizedString("Penyimpanan %d persen terpakai", comment: ""),
            Int(fraction * 100)
        ))
    }
}

private struct HomeToolRow: View {
    let module: Module
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DKSpacing.md) {
                module.iconTile
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(module.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: DKRadius.card)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityHint(module.shortDescription)
    }
}
