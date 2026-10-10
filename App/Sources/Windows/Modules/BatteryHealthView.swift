import SwiftUI
import RespiteCore
import DesignKit

/// "Baterai" (TRD §4.12.1): IOKit, 100% read-only. Status besar dalam bahasa
/// sehari-hari dari kapasitas penuh vs kapasitas desain. Data resmi
/// ("Service Recommended") ada di Pengaturan Sistem — dijelaskan jujur di
/// "Lihat detail".
struct BatteryHealthView: View {
    @ObservedObject var model: SystemStatsModel

    /// Batas wajar siklus pengisian baterai MacBook modern menurut Apple.
    private let typicalCycleLimit = 1000

    var body: some View {
        if let battery = model.battery {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                statusCard(battery)
                checksSection(battery)
                technicalDetails(battery)
            }
        } else {
            ToolCard {
                HStack(alignment: .top, spacing: DKSpacing.md) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.respite)
                    VStack(alignment: .leading, spacing: DKSpacing.xs) {
                        Text(NSLocalizedString("Mac ini tidak memakai baterai", comment: ""))
                            .font(.title3.weight(.semibold))
                        Text(NSLocalizedString("Mac desktop langsung tersambung ke listrik, jadi tidak ada baterai yang perlu dicek. Semuanya aman.", comment: ""))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Status

    private enum Condition {
        case healthy, weakening, replace, unknown
    }

    private func condition(_ battery: BatteryInfo) -> Condition {
        guard let health = battery.healthPercent else { return .unknown }
        if health >= 80 { return .healthy }
        if health >= 60 { return .weakening }
        return .replace
    }

    private func statusCard(_ battery: BatteryInfo) -> some View {
        let condition = condition(battery)
        let headline: String
        let color: Color
        let symbol: String
        let advice: String
        switch condition {
        case .healthy:
            headline = NSLocalizedString("Baterai sehat", comment: "")
            color = Color.respite
            symbol = "checkmark.seal.fill"
            advice = NSLocalizedString("Masih kuat dipakai seharian seperti biasa.", comment: "")
        case .weakening:
            headline = NSLocalizedString("Baterai mulai melemah", comment: "")
            color = DKColor.attention
            symbol = "exclamationmark.triangle.fill"
            advice = NSLocalizedString("Baterai jadi lebih cepat habis dari waktu baru. Masih bisa dipakai, tapi mulai pertimbangkan penggantian.", comment: "")
        case .replace:
            headline = NSLocalizedString("Baterai perlu diganti", comment: "")
            color = DKColor.irreversible
            symbol = "exclamationmark.octagon.fill"
            advice = NSLocalizedString("Kapasitasnya sudah jauh berkurang. Bawa ke servis resmi Apple untuk penggantian baterai.", comment: "")
        case .unknown:
            headline = NSLocalizedString("Kondisi baterai belum terbaca", comment: "")
            color = DKColor.neutral
            symbol = "battery.50"
            advice = NSLocalizedString("Kamu bisa melihat kondisinya di Pengaturan Sistem › Baterai.", comment: "")
        }
        return ToolCard {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.title2.weight(.semibold))
                    if let health = battery.healthPercent {
                        Text(String(
                            format: NSLocalizedString("Masih menyimpan %d%% dari kapasitas aslinya", comment: ""),
                            health
                        ))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    }
                }
                Spacer()
            }
            if let health = battery.healthPercent {
                UsageBar(
                    fraction: Double(health) / 100,
                    color: condition == .healthy ? Color.respite : color
                )
            }
            Text(advice)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Yang diperiksa

    private func checksSection(_ battery: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Yang diperiksa", comment: ""))
                .font(.headline)
            checkRow(
                NSLocalizedString("Isi baterai sekarang", comment: ""),
                value: String(
                    format: NSLocalizedString("%1$d%% · %2$@", comment: ""),
                    battery.capacityPercent,
                    battery.isCharging
                        ? NSLocalizedString("sedang diisi", comment: "")
                        : NSLocalizedString("tidak sedang diisi", comment: "")
                ),
                fraction: Double(battery.capacityPercent) / 100,
                isWarning: battery.capacityPercent <= 20 && !battery.isCharging
            )
            checkRow(
                NSLocalizedString("Sudah diisi ulang", comment: ""),
                value: String(
                    format: NSLocalizedString("%1$d kali (batas wajar ±%2$d)", comment: ""),
                    battery.cycleCount,
                    typicalCycleLimit
                ),
                fraction: Double(battery.cycleCount) / Double(typicalCycleLimit),
                isWarning: battery.cycleCount >= typicalCycleLimit
            )
        }
    }

    private func checkRow(_ label: String, value: String, fraction: Double, isWarning: Bool) -> some View {
        VStack(spacing: DKSpacing.xs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            UsageBar(fraction: fraction, color: isWarning ? DKColor.attention : Color.respite)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Detail teknis

    private func technicalDetails(_ battery: BatteryInfo) -> some View {
        ToolDetails {
            HStack {
                Text(NSLocalizedString("Cycle count", comment: ""))
                Spacer()
                Text("\(battery.cycleCount)").monospacedDigit()
            }
            if let health = battery.healthPercent {
                HStack {
                    Text(NSLocalizedString("Kapasitas penuh vs kapasitas desain", comment: ""))
                    Spacer()
                    Text("\(health)%").monospacedDigit()
                }
            }
            HStack {
                Text(NSLocalizedString("Status daya", comment: ""))
                Spacer()
                Text(battery.powerState)
            }
            Text(NSLocalizedString("Satu siklus = pemakaian setara 100% isi baterai (boleh dicicil, mis. dua kali 50%). Baterai dianggap sehat selama kapasitas penuhnya masih di atas 80% kapasitas desain.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("Indikator kondisi baterai resmi dari Apple (mis. \"Service Recommended\") tersedia di Pengaturan Sistem › Baterai. Modul ini sepenuhnya baca-saja dan tidak mengubah pengaturan daya apa pun.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
