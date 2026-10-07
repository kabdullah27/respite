import SwiftUI
import RespiteCore
import DesignKit

/// Kesehatan Baterai (TRD §4.12.1): IOKit, 100% read-only. Data resmi
/// kondisi baterai ("Service Recommended") ada di System Settings —
/// modul ini menampilkan yang tersedia via API publik + jujur soal itu.
struct BatteryHealthView: View {
    @ObservedObject var model: SystemStatsModel

    var body: some View {
        if let battery = model.battery {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                Text(NSLocalizedString("Sekarang", comment: ""))
                    .font(.title3.weight(.semibold))

                // Kartu status: baris rapi label-kiri / nilai-kanan.
                VStack(alignment: .leading, spacing: DKSpacing.md) {
                    statusRow(
                        label: NSLocalizedString("Cycle count", comment: ""),
                        value: "\(battery.cycleCount)",
                        caption: NSLocalizedString("jumlah siklus pengisian penuh yang sudah dipakai", comment: "")
                    )
                    statusRow(
                        label: NSLocalizedString("Kapasitas saat ini", comment: ""),
                        value: "\(battery.capacityPercent)%",
                        caption: NSLocalizedString("dari kapasitas maksimum yang masih bisa ditampung", comment: "")
                    )
                    statusRow(
                        label: NSLocalizedString("Status daya", comment: ""),
                        value: battery.isCharging
                            ? NSLocalizedString("Mengisi", comment: "")
                            : NSLocalizedString("Dipakai", comment: ""),
                        caption: battery.powerState
                    )
                }

                // Kesehatan: bar + persen, di kartunya sendiri.
                if let health = battery.healthPercent {
                    VStack(alignment: .leading, spacing: DKSpacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(NSLocalizedString("Kesehatan baterai", comment: ""))
                                .font(.callout)
                            Spacer()
                            Text("\(health)%")
                                .font(.dkData(15, weight: .semibold))
                                .foregroundColor(health < 80 ? DKColor.attention : Color.primary)
                        }
                        UsageBar(
                            fraction: Double(health) / 100,
                            color: health < 80 ? DKColor.attention : DKColor.accent
                        )
                        Text(health < 80
                             ? NSLocalizedString("Di bawah 80% — penggantian baterai mulai layak dipertimbangkan.", comment: "")
                             : NSLocalizedString("Masih sehat — kapasitas tersisa layak dipakai harian tanpa kendala.", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(DKSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DKColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }

                Text(NSLocalizedString("Indikator kondisi baterai resmi dari Apple (mis. \"Service Recommended\") tersedia di Pengaturan Sistem › Baterai. Modul ini sepenuhnya baca-saja dan tidak mengubah pengaturan daya apa pun.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            EmptyStateView(
                symbol: "battery.100",
                title: NSLocalizedString("Tidak ada baterai", comment: ""),
                message: NSLocalizedString("Mac ini terhubung langsung ke daya (desktop) — modul baterai disembunyikan otomatis.", comment: "")
            )
        }
    }

    private func statusRow(label: String, value: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout)
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(value)
                .font(.dkData(15, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
