import SwiftUI
import RespiteCore
import DesignKit

/// Modul Deteksi Thermal (TRD §4.5.1): 100% read-only, paling aman di seluruh
/// app. 4-level enum + angka spesifik `CPU_Speed_Limit` dari pmset.
struct ThermalDetectorView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var speedLimit: Int?

    private var state: (label: String, color: Color) {
        switch model.snapshot.thermalState {
        case .nominal: return (NSLocalizedString("Nominal", comment: ""), DKColor.accent)
        case .fair: return (NSLocalizedString("Fair — suhu meninggi", comment: ""), DKColor.attention)
        case .serious: return (NSLocalizedString("Serious — throttling aktif", comment: ""), DKColor.attention)
        case .critical: return (NSLocalizedString("Critical", comment: ""), DKColor.irreversible)
        @unknown default: return ("?", DKColor.neutral)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            VStack(alignment: .leading, spacing: DKSpacing.md) {
                Text(NSLocalizedString("Sekarang", comment: "")).font(.title3.weight(.semibold))
                HStack {
                    Text(NSLocalizedString("Status thermal", comment: "")).font(.callout)
                    Spacer()
                    Text(state.label)
                        .font(.dkData(13))
                        .foregroundColor(state.color)
                }
                // Suhu hanya ditampilkan kalau sensor beneran terbaca —
                // baris "tidak terbaca" permanen cuma jadi noise di Mac
                // yang mengunci sensornya (feedback user 2026-09-24).
                if let c = model.cpuCelsius {
                    HStack {
                        Text(NSLocalizedString("Suhu CPU", comment: "")).font(.callout)
                        Spacer()
                        Text(String(format: "%.1f°C", c))
                            .font(.dkData(15, weight: .semibold))
                            .foregroundColor(c >= 90 ? DKColor.irreversible : (c >= 75 ? DKColor.attention : DKColor.accent))
                    }
                }
                VStack(alignment: .leading, spacing: DKSpacing.xs) {
                    HStack {
                        Text(NSLocalizedString("Batas kecepatan CPU", comment: "")).font(.callout)
                        Spacer()
                        if let limit = speedLimit {
                            Text(String(
                                format: NSLocalizedString("%d%%", comment: ""),
                                limit
                            ))
                            .font(.dkData(12))
                        } else {
                            Text("—").font(.dkData(12)).foregroundColor(.secondary)
                        }
                    }
                    if let limit = speedLimit {
                        UsageBar(
                            fraction: Double(limit) / 100,
                            color: limit < 100 ? DKColor.attention : DKColor.accent
                        )
                    }
                }
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))

            Text(explanation)
                .font(.callout)
                .foregroundColor(explanationColor)
                .fixedSize(horizontal: false, vertical: true)

            if model.snapshot.thermalState != .nominal, let limit = speedLimit, limit == 100 {
                Text(NSLocalizedString("Status thermal dari sistem menyebut Fair, tetapi batas kecepatan CPU masih 100% — tidak ada penalti performa nyata saat ini. Nilai thermalState kadang tertinggal setelah Mac bangun dari sleep; Respite memeriksanya ulang setiap 2 detik dan setiap kali Mac bangun.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(NSLocalizedString("Sumber: ProcessInfo.thermalState, pmset -g therm (CPU_Speed_Limit), dan sensor SMC (kalau terbaca). 100% berarti tidak ada throttling. Modul ini sepenuhnya baca-saja.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            speedLimit = await Task.detached(priority: .utility) {
                ThermalInfo.cpuSpeedLimitPercent()
            }.value
        }
    }

    private var explanation: String {
        switch model.snapshot.thermalState {
        case .nominal:
            return NSLocalizedString("Tidak ada throttling — performa CPU berjalan penuh.", comment: "")
        case .fair, .serious, .critical:
            return NSLocalizedString("Sistem sedang menurunkan kecepatan CPU karena suhu. Tutup aplikasi berat dan pastikan ventilasi tidak tertutup — kelambanan saat ini berasal dari panas, bukan dari file sampah.", comment: "")
        @unknown default:
            return ""
        }
    }

    private var explanationColor: Color {
        model.snapshot.thermalState == .nominal ? DKColor.accent : DKColor.attention
    }
}
