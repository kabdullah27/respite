import SwiftUI
import RespiteCore
import DesignKit

/// "Suhu Mac" (TRD §4.5.1): 100% read-only, paling aman di seluruh app.
/// Status besar dalam bahasa sehari-hari + suhu (kalau sensornya terbaca)
/// + saran. Enum thermalState & `CPU_Speed_Limit` pmset ada di "Lihat detail".
struct ThermalDetectorView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var speedLimit: Int?

    private var thermalState: ProcessInfo.ThermalState { model.snapshot.thermalState }

    private var isHot: Bool {
        thermalState == .serious || thermalState == .critical
    }

    private var statusColor: Color {
        switch thermalState {
        case .nominal: return Color.respite
        case .fair, .serious: return DKColor.attention
        case .critical: return DKColor.irreversible
        @unknown default: return DKColor.neutral
        }
    }

    private var statusSymbol: String {
        switch thermalState {
        case .nominal: return "checkmark.seal.fill"
        case .fair: return "thermometer.medium"
        case .serious, .critical: return "thermometer.high"
        @unknown default: return "thermometer.medium"
        }
    }

    private var statusMessage: String {
        switch thermalState {
        case .nominal:
            return NSLocalizedString("Mac kamu tidak kepanasan dan berjalan dengan kecepatan penuh.", comment: "")
        case .fair:
            return NSLocalizedString("Mac mulai hangat, tapi masih berjalan normal.", comment: "")
        case .serious, .critical:
            return NSLocalizedString("Mac sengaja diperlambat supaya cepat dingin. Kelambanan saat ini karena panas, bukan karena file sampah.", comment: "")
        @unknown default:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            statusCard
            adviceSection
            technicalDetails
        }
        .task {
            speedLimit = await Task.detached(priority: .utility) {
                ThermalInfo.cpuSpeedLimitPercent()
            }.value
        }
    }

    // MARK: Status

    private var statusCard: some View {
        ToolCard {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 30))
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MacStatus.thermalText(thermalState))
                        .font(.title2.weight(.semibold))
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Suhu hanya ditampilkan kalau sensor beneran terbaca —
                // baris "tidak terbaca" permanen cuma jadi noise di Mac
                // yang mengunci sensornya (feedback user 2026-09-24).
                if let celsius = model.cpuCelsius {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.0f°C", celsius))
                            .font(.dkData(22, weight: .semibold))
                            .foregroundColor(celsiusColor(celsius))
                        Text(NSLocalizedString("suhu prosesor", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func celsiusColor(_ celsius: Double) -> Color {
        if celsius >= 90 { return DKColor.irreversible }
        if celsius >= 75 { return DKColor.attention }
        return Color.respite
    }

    // MARK: Saran

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            Text(thermalState == .nominal
                 ? NSLocalizedString("Supaya Mac tetap dingin", comment: "")
                 : NSLocalizedString("Yang bisa kamu lakukan", comment: ""))
                .font(.headline)
            adviceRow(
                symbol: "xmark.app",
                text: NSLocalizedString("Tutup aplikasi berat yang sedang tidak kamu pakai.", comment: ""),
                action: (NSLocalizedString("Lihat aplikasi berat", comment: ""), Module.memoryMonitor)
            )
            adviceRow(
                symbol: "wind",
                text: NSLocalizedString("Taruh Mac di permukaan keras dan datar — jangan di atas kasur, bantal, atau pangkuan berselimut.", comment: "")
            )
            adviceRow(
                symbol: "sun.max",
                text: NSLocalizedString("Jauhkan dari sinar matahari langsung dan ruangan yang panas.", comment: "")
            )
            if isHot {
                adviceRow(
                    symbol: "pause.circle",
                    text: NSLocalizedString("Istirahatkan sebentar pekerjaan berat (game, edit video) sampai Mac dingin lagi.", comment: "")
                )
            }
        }
    }

    private func adviceRow(symbol: String, text: String, action: (title: String, module: Module)? = nil) -> some View {
        HStack(alignment: .top, spacing: DKSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(Color.respite)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action {
                Button(action.title) { openModule(action.module) }
            }
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    // MARK: Detail teknis

    private var rawStateLabel: String {
        switch thermalState {
        case .nominal: return NSLocalizedString("Nominal", comment: "")
        case .fair: return NSLocalizedString("Fair — suhu meninggi", comment: "")
        case .serious: return NSLocalizedString("Serious — throttling aktif", comment: "")
        case .critical: return NSLocalizedString("Critical", comment: "")
        @unknown default: return "?"
        }
    }

    private var technicalDetails: some View {
        ToolDetails {
            HStack {
                Text(NSLocalizedString("Status thermal (thermalState)", comment: ""))
                Spacer()
                Text(rawStateLabel)
            }
            HStack {
                Text(NSLocalizedString("Batas kecepatan CPU", comment: ""))
                Spacer()
                if let limit = speedLimit {
                    Text(String(format: NSLocalizedString("%d%%", comment: ""), limit))
                        .monospacedDigit()
                } else {
                    Text("—")
                }
            }
            if let celsius = model.cpuCelsius {
                HStack {
                    Text(NSLocalizedString("Suhu CPU (sensor SMC)", comment: ""))
                    Spacer()
                    Text(String(format: "%.1f°C", celsius)).monospacedDigit()
                }
            }
            Text(thermalState == .nominal
                 ? NSLocalizedString("Tidak ada throttling — performa CPU berjalan penuh.", comment: "")
                 : NSLocalizedString("Sistem sedang menurunkan kecepatan CPU karena suhu. Tutup aplikasi berat dan pastikan ventilasi tidak tertutup — kelambanan saat ini berasal dari panas, bukan dari file sampah.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
            if thermalState != .nominal, let limit = speedLimit, limit == 100 {
                Text(NSLocalizedString("Status thermal dari sistem menyebut Fair, tetapi batas kecepatan CPU masih 100% — tidak ada penalti performa nyata saat ini. Nilai thermalState kadang tertinggal setelah Mac bangun dari sleep; Respite memeriksanya ulang setiap 2 detik dan setiap kali Mac bangun.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(NSLocalizedString("Sumber: ProcessInfo.thermalState, pmset -g therm (CPU_Speed_Limit), dan sensor SMC (kalau terbaca). 100% berarti tidak ada throttling. Modul ini sepenuhnya baca-saja.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
