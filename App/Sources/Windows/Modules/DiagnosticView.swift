import SwiftUI
import RespiteCore
import DesignKit

/// Teks & warna status Mac dalam bahasa sehari-hari — dipakai Beranda dan
/// "Kenapa Mac Lambat?" supaya kalimatnya selalu sama.
enum MacStatus {
    static func headline(_ band: HealthScore.Band) -> String {
        switch band {
        case .neutral: return NSLocalizedString("Mac kamu dalam kondisi baik", comment: "")
        case .attention: return NSLocalizedString("Ada yang perlu diperhatikan", comment: "")
        case .critical: return NSLocalizedString("Mac kamu butuh perhatian", comment: "")
        }
    }

    static func color(_ band: HealthScore.Band) -> Color {
        switch band {
        case .neutral: return Color.respite
        case .attention: return DKColor.attention
        case .critical: return DKColor.irreversible
        }
    }

    static func symbol(_ band: HealthScore.Band) -> String {
        switch band {
        case .neutral: return "checkmark.seal.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    static func scoreText(_ score: Int) -> String {
        String(format: NSLocalizedString("Skor kesehatan %d dari 100", comment: ""), score)
    }

    static func findingText(_ kind: DiagnosticFinding.Kind) -> String {
        switch kind {
        case .thermalCritical:
            return NSLocalizedString("Mac kamu sedang panas, jadi macOS sengaja memperlambatnya supaya dingin.", comment: "")
        case .thermalFair:
            return NSLocalizedString("Mac mulai hangat. Tutup aplikasi berat dan jangan tutupi lubang udaranya.", comment: "")
        case .cpuHigh(let percent):
            return String(
                format: NSLocalizedString("Prosesor sedang sibuk (%d%%). Ada aplikasi yang bekerja keras — tutup kalau tidak dipakai.", comment: ""),
                percent
            )
        case .memoryPressure(let percent):
            return String(
                format: NSLocalizedString("Memori hampir penuh (%d%% terpakai). Tutup aplikasi yang tidak sedang dipakai.", comment: ""),
                percent
            )
        case .diskLow(let percent):
            return String(
                format: NSLocalizedString("Ruang penyimpanan tinggal %d%%. Mac bisa melambat kalau penyimpanan hampir penuh.", comment: ""),
                percent
            )
        case .allHealthy:
            return NSLocalizedString("Tidak ada masalah yang terlihat. Mac kamu berjalan normal.", comment: "")
        }
    }

    /// Langkah lanjut untuk temuan — tombol yang langsung membuka alatnya.
    static func action(_ kind: DiagnosticFinding.Kind) -> (title: String, module: Module)? {
        switch kind {
        case .thermalCritical, .thermalFair:
            return (NSLocalizedString("Cek suhu", comment: ""), .thermalDetector)
        case .cpuHigh, .memoryPressure:
            return (NSLocalizedString("Lihat aplikasi berat", comment: ""), .memoryMonitor)
        case .diskLow:
            return (NSLocalizedString("Kosongkan ruang", comment: ""), .smartScan)
        case .allHealthy:
            return nil
        }
    }

    static func severityColor(_ severity: DiagnosticFinding.Severity) -> Color {
        switch severity {
        case .info: return Color.respite
        case .attention: return DKColor.attention
        case .critical: return DKColor.irreversible
        }
    }

    static func severitySymbol(_ severity: DiagnosticFinding.Severity) -> String {
        switch severity {
        case .info: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return NSLocalizedString("Normal", comment: "")
        case .fair: return NSLocalizedString("Hangat", comment: "")
        case .serious: return NSLocalizedString("Panas — sedang diperlambat", comment: "")
        case .critical: return NSLocalizedString("Sangat panas", comment: "")
        @unknown default: return "—"
        }
    }

    static func cpuText(_ fraction: Double?) -> String {
        guard let fraction else { return NSLocalizedString("Mengukur…", comment: "") }
        switch fraction {
        case ..<0.4: return NSLocalizedString("Santai", comment: "")
        case ..<0.8: return NSLocalizedString("Cukup sibuk", comment: "")
        default: return NSLocalizedString("Sangat sibuk", comment: "")
        }
    }
}

/// Buka alat lain dari halaman mana pun (dipakai tombol saran).
func openModule(_ module: Module) {
    NotificationCenter.default.post(name: .respiteOpenModule, object: module)
}

/// "Kenapa Mac Lambat?" — status besar, temuan + tombol tindakan, lalu
/// empat hal yang diperiksa. Rumus skor disimpan di "Lihat detail".
struct DiagnosticView: View {
    @ObservedObject var model: SystemStatsModel

    var body: some View {
        let score = model.healthScore
        let band = HealthScore.Band.band(for: score)
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            ToolCard {
                HStack(spacing: DKSpacing.md) {
                    Image(systemName: MacStatus.symbol(band))
                        .font(.system(size: 30))
                        .foregroundStyle(MacStatus.color(band))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MacStatus.headline(band))
                            .font(.title2.weight(.semibold))
                        Text(MacStatus.scoreText(score))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                Text(NSLocalizedString("Yang kami temukan", comment: ""))
                    .font(.headline)
                ForEach(model.diagnosticFindings) { finding in
                    HStack(alignment: .top, spacing: DKSpacing.md) {
                        Image(systemName: MacStatus.severitySymbol(finding.severity))
                            .foregroundStyle(MacStatus.severityColor(finding.severity))
                            .padding(.top, 2)
                        Text(MacStatus.findingText(finding.kind))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if let action = MacStatus.action(finding.kind) {
                            Button(action.title) { openModule(action.module) }
                        }
                    }
                    .padding(DKSpacing.md)
                    .background(DKColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }
            }

            VStack(alignment: .leading, spacing: DKSpacing.md) {
                Text(NSLocalizedString("Yang diperiksa", comment: ""))
                    .font(.headline)
                checkRow(
                    NSLocalizedString("Prosesor", comment: ""),
                    value: MacStatus.cpuText(model.cpuUsageFraction),
                    fraction: model.cpuUsageFraction
                )
                checkRow(
                    NSLocalizedString("Memori", comment: ""),
                    value: String(
                        format: NSLocalizedString("%1$@ dari %2$@ terpakai", comment: ""),
                        ByteFormat.string(from: Int64(model.snapshot.memory.usedBytes)),
                        ByteFormat.string(from: Int64(model.snapshot.memory.totalBytes))
                    ),
                    fraction: model.snapshot.memory.usedFraction
                )
                checkRow(
                    NSLocalizedString("Penyimpanan", comment: ""),
                    value: String(
                        format: NSLocalizedString("%@ masih kosong", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    ),
                    fraction: 1 - model.snapshot.disk.availableFraction
                )
                checkRow(
                    NSLocalizedString("Suhu", comment: ""),
                    value: MacStatus.thermalText(model.snapshot.thermalState),
                    fraction: nil
                )
            }

            ToolDetails(title: NSLocalizedString("Bagaimana skor dihitung?", comment: "")) {
                Text(NSLocalizedString("Skor 0–100 dari empat hal: memori (30%), penyimpanan (25%), suhu (25%), dan prosesor (20%). Di atas 70 berarti sehat. Pemeriksaan ini hanya membaca — tidak ada yang diubah.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func checkRow(_ label: String, value: String, fraction: Double?) -> some View {
        VStack(spacing: DKSpacing.xs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            if let fraction {
                UsageBar(fraction: fraction, color: fraction >= 0.85 ? DKColor.attention : Color.respite)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
