import SwiftUI
import RespiteCore
import DesignKit

extension Color {
    /// Aksen produk Respite (teal) — dipakai hero, donut, dan CTA utama.
    static let respite = Color(red: 0.10, green: 0.58, blue: 0.46)
}

/// Beranda bergaya PureMac: hero card + kartu statistik (donut penyimpanan)
/// + grid kartu alat. Satu pandangan: kondisi Mac + pintu ke semua alat.
struct HomeView: View {
    @ObservedObject var model: SystemStatsModel
    @Binding var selectedModule: Module?

    private let columns = [
        GridItem(.flexible(), spacing: DKSpacing.md),
        GridItem(.flexible(), spacing: DKSpacing.md),
        GridItem(.flexible(), spacing: DKSpacing.md),
    ]

    private var toolModules: [Module] {
        Module.allCases.filter { $0 != .home && $0 != .donation }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.xl) {
                header
                heroBand
                toolsGrid
            }
            .padding(DKSpacing.xl + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text(NSLocalizedString("Perawatan Cerdas", comment: ""))
                    .font(.system(size: 30, weight: .bold))
                Text(NSLocalizedString("Tinjauan ruang yang bisa dibebaskan dan alat untuk mengelolanya.", comment: ""))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                let score = model.healthScore
                let band = HealthScore.Band.band(for: score)
                HStack(spacing: DKSpacing.xs) {
                    Image(systemName: band == .neutral ? "checkmark" : "exclamationmark.triangle")
                        .font(.caption.weight(.bold))
                    Text(band == .neutral ? NSLocalizedString("Sehat", comment: "") : NSLocalizedString("Perlu perhatian", comment: ""))
                        .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, DKSpacing.md)
                .padding(.vertical, DKSpacing.xs + 2)
                .background(
                    (band == .neutral ? Color.respite : DKColor.attention).opacity(0.14)
                )
                .foregroundColor(band == .neutral ? Color.respite : DKColor.attention)
                .clipShape(Capsule())
                Text(String(
                    format: NSLocalizedString("Health Score %d/100", comment: ""),
                    score
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Hero band

    private var heroBand: some View {
        HStack(alignment: .top, spacing: DKSpacing.md) {
            heroCard
                .frame(maxWidth: .infinity)
            storageCard
                .frame(maxWidth: .infinity)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.respite)
                    .frame(width: 34, height: 34)
                    .background(Color.respite.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                Spacer()
                Text(String(
                    format: NSLocalizedString("%d alat", comment: ""),
                    toolModules.count
                ))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(NSLocalizedString("Bebaskan ruang di Mac kamu.", comment: ""))
                .font(.system(size: 21, weight: .bold))
            Text(NSLocalizedString("Respite memeriksa cache, log, data pengembang, dan Trash. Semuanya kamu tinjau dulu sebelum dihapus.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DKSpacing.md) {
                Button {
                    selectedModule = .smartScan
                } label: {
                    Label(NSLocalizedString("Pindai Mac Ini", comment: ""), systemImage: "magnifyingglass")
                        .fixedSize()
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color.respite)

                HStack(spacing: DKSpacing.xs) {
                    Image(systemName: "lock")
                    Text(NSLocalizedString("Lokal & privat", comment: ""))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(DKSpacing.lg + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Tint teal transparan di atas background window: adaptif terang/gelap,
        // dan lebih dalam dari mint flat yang kemarin keliatan keputih-putihan.
        .background(Color.respite.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: DKRadius.card + 4)
                .stroke(Color.respite.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 4))
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Penyimpanan Mac", comment: ""))
                        .font(.headline)
                    Text(String(
                        format: NSLocalizedString("%@ tersedia", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    model.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            if model.snapshot.disk.purgeableBytes > 0 {
                Text(NSLocalizedString("Ruang purgeable dibebaskan macOS sendiri saat dibutuhkan — tidak dihitung sebagai ruang yang bisa Respite bebaskan.", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DKSpacing.lg) {
                DonutStorage(
                    usedFraction: 1 - model.snapshot.disk.availableFraction
                )
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: DKSpacing.sm) {
                    legendDot(
                        color: Color.respite,
                        label: NSLocalizedString("Terpakai", comment: ""),
                        value: ByteFormat.string(from: model.snapshot.disk.totalBytes - model.snapshot.disk.availableBytes)
                    )
                    legendDot(
                        color: Color.primary.opacity(0.15),
                        label: NSLocalizedString("Tersedia", comment: ""),
                        value: ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    )
                    if model.snapshot.disk.purgeableBytes > 0 {
                        legendDot(
                            color: Color.secondary.opacity(0.5),
                            label: NSLocalizedString("Purgeable", comment: ""),
                            value: ByteFormat.string(from: model.snapshot.disk.purgeableBytes)
                        )
                    }
                }
            }
        }
        .padding(DKSpacing.lg + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: DKRadius.card + 4)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 4))
    }

    private func legendDot(color: Color, label: String, value: String) -> some View {
        HStack(spacing: DKSpacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.dkData(12))
        }
        .frame(minWidth: 150)
        .accessibilityElement(children: .combine)
    }

    // MARK: Grid alat

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("Alat", comment: ""))
                    .font(.title3.weight(.bold))
                Spacer()
                Text(NSLocalizedString("Utilitas untuk penyimpanan, aplikasi, dan perawatan sistem", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            LazyVGrid(columns: columns, spacing: DKSpacing.md) {
                ForEach(toolModules) { module in
                    ToolCard(module: module) {
                        selectedModule = module
                    }
                }
            }
        }
    }
}

// MARK: - Kartu alat

private struct ToolCard: View {
    let module: Module
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: module.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(module.tintColor)
                    .frame(width: 30, height: 30)
                    .background(module.tintColor.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(module.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: DKRadius.card)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Buka modul", comment: "") + " " + module.title)
        .accessibilityHint(module.shortDescription)
    }
}

// MARK: - Donut penyimpanan

private struct DonutStorage: View {
    let usedFraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: 13)
            Circle()
                .trim(from: 0, to: usedFraction)
                .stroke(Color.respite, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(usedFraction * 100))%")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(NSLocalizedString("TERPAKAI", comment: ""))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: NSLocalizedString("Penyimpanan %d persen terpakai", comment: ""),
            Int(usedFraction * 100)
        ))
    }
}
