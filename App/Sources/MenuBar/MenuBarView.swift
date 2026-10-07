import SwiftUI
import RespiteCore
import DesignKit

/// Dropdown menu bar — versi senada Beranda: ring skor kecil di header,
/// metrik dengan bar teal, CTA "Pindai Mac Ini" menonjol, footer keluar.
/// Ditampilkan sebagai popover oleh StatusBarController.
struct MenuBarView: View {
    @ObservedObject var model: SystemStatsModel
    let onOpenApp: (Module?) -> Void

    var body: some View {
        VStack(spacing: DKSpacing.lg) {
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                header
                // Label "Perlu perhatian" tanpa alasan = user bingung apa yang
                // harus dilakukan → tampilkan temuan utama satu kalimat.
                if HealthScore.Band.band(for: model.healthScore) != .neutral,
                   let reason = topReasonText {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(bandColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Transparansi: dari apa saja skor ini dihitung.
                Text("Skor: memori 30% · disk 25% · thermal 25% · CPU 20%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: DKSpacing.lg) {
                metricBlock(
                    title: NSLocalizedString("CPU", comment: ""),
                    value: cpuValue,
                    fraction: model.cpuUsageFraction ?? 0,
                    caption: NSLocalizedString("Beban keseluruhan prosesor", comment: "")
                )

                metricBlock(
                    title: NSLocalizedString("Memori", comment: ""),
                    value: ByteFormat.string(from: model.snapshot.memory.usedBytes),
                    fraction: model.snapshot.memory.usedFraction,
                    caption: String(
                        format: NSLocalizedString("dari %@ · %@ tersedia", comment: ""),
                        ByteFormat.string(from: model.snapshot.memory.totalBytes),
                        ByteFormat.string(from: model.snapshot.memory.availableBytes)
                    )
                )

                metricBlock(
                    title: NSLocalizedString("Disk", comment: ""),
                    value: String(
                        format: NSLocalizedString("%@ tersedia", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    ),
                    fraction: 1 - model.snapshot.disk.availableFraction,
                    caption: String(
                        format: NSLocalizedString("dari total %@", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.totalBytes)
                    )
                )
            }

            VStack(spacing: DKSpacing.xs) {
                // Thermal selalu tampil — "Nominal" itu juga informasi
                // (meyakinkan user kalau panas BUKAN penyebab lambatnya).
                infoRow(
                    symbol: model.snapshot.thermalState == .nominal
                        ? "thermometer.medium" : "thermometer.high",
                    label: NSLocalizedString("Thermal", comment: ""),
                    // Suhu (kalau sensor terbaca) nyempil di nilai thermal —
                    // konsisten dengan modul Deteksi Suhu.
                    value: thermalLabel + celsiusSuffix,
                    color: model.snapshot.thermalState == .nominal ? Color.respite : DKColor.attention
                )
                infoRow(symbol: "clock",
                        label: NSLocalizedString("Uptime", comment: ""),
                        value: UptimeFormat.string(from: model.snapshot.uptime),
                        color: nil)
            }

            Divider()

            // CTA utama senada hero Beranda; "Buka Respite" tetap sejajar.
            HStack(spacing: DKSpacing.sm) {
                Button {
                    onOpenApp(.smartScan)
                } label: {
                    Label(NSLocalizedString("Pindai Mac Ini", comment: ""), systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.respite)
                .controlSize(.large)

                Button {
                    onOpenApp(nil)
                } label: {
                    Label(NSLocalizedString("Buka Respite", comment: ""), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("o")
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(NSLocalizedString("Keluar Respite", comment: ""), systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .foregroundColor(DKColor.irreversible)

            Button {
                NSWorkspace.shared.open(DonationConfig.donationURL)
            } label: {
                Label("Dukung pengembangan Respite", systemImage: "heart")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(DKSpacing.lg)
        .frame(width: 300)
    }

    // MARK: - Bagian-bagian

    /// Header dengan ring skor mini (senada donut Beranda) — klik untuk
    /// membuka Diagnosis Performa dan melihat rincian skor.
    private var header: some View {
        let score = model.healthScore
        let color = bandColor
        return Button {
            onOpenApp(.diagnostic)
        } label: {
            HStack(spacing: DKSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.09), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(score)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Respite")
                        .font(.headline.weight(.semibold))
                    Text(bandLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Respite. Health score \(score) dari 100, \(bandLabel)")
        .accessibilityHint(NSLocalizedString("Buka Diagnosis Performa", comment: ""))
    }

    private func metricBlock(title: String, value: String, fraction: Double, caption: String) -> some View {
        VStack(spacing: DKSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(value)
                    .font(.dkData(15))
            }
            UsageBar(fraction: fraction, color: barColor(fraction: fraction))
            Text(caption)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value), \(caption)")
    }

    private func infoRow(symbol: String, label: String, value: String, color: Color?) -> some View {
        HStack {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
            Spacer()
            Text(value)
                .font(.dkData(12))
                .foregroundColor(color ?? .primary)
        }
    }

    // MARK: - Warna & label

    /// Temuan paling relevan → satu kalimat pendek buat popover.
    private var topReasonText: String? {
        guard let finding = model.diagnosticFindings.first(where: { $0.severity != .info }) else {
            return nil
        }
        switch finding.kind {
        case .thermalCritical:
            return NSLocalizedString("Suhu tinggi — macOS sedang menurunkan performa.", comment: "")
        case .thermalFair:
            return NSLocalizedString("Suhu mulai meninggi — tutup aplikasi berat.", comment: "")
        case .cpuHigh(let percent):
            return String(
                format: NSLocalizedString("Beban CPU %d%% — ada proses berat yang berjalan.", comment: ""),
                percent
            )
        case .memoryPressure(let percent):
            return String(
                format: NSLocalizedString("Memori terpakai %d%% — tutup aplikasi yang tidak digunakan.", comment: ""),
                percent
            )
        case .diskLow(let percent):
            return String(
                format: NSLocalizedString("Ruang disk tersisa %d%% — bebasakan sebagian.", comment: ""),
                percent
            )
        case .allHealthy:
            return nil
        }
    }

    private var bandLabel: String {
        switch HealthScore.Band.band(for: model.healthScore) {
        case .neutral: return NSLocalizedString("Sehat", comment: "")
        case .attention: return NSLocalizedString("Perlu perhatian", comment: "")
        case .critical: return NSLocalizedString("Perlu tindakan", comment: "")
        }
    }

    private var bandColor: Color {
        switch HealthScore.Band.band(for: model.healthScore) {
        case .neutral: return Color.respite
        case .attention: return DKColor.attention
        case .critical: return DKColor.irreversible
        }
    }

    /// " · 62°C" kalau sensor SMC terbaca; kosong kalau tidak.
    private var celsiusSuffix: String {
        model.cpuCelsius.map { String(format: " · %.0f°C", $0) } ?? ""
    }

    private var thermalLabel: String {
        switch model.snapshot.thermalState {
        case .fair: return NSLocalizedString("Fair — suhu meninggi", comment: "")
        case .serious: return NSLocalizedString("Serious — throttling aktif", comment: "")
        case .critical: return NSLocalizedString("Critical", comment: "")
        case .nominal: return NSLocalizedString("Nominal — tanpa throttling", comment: "")
        @unknown default: return "?"
        }
    }

    /// Nilai CPU baru ada mulai refresh kedua (butuh dua sample untuk delta).
    private var cpuValue: String {
        model.cpuUsageFraction
            .map { "\(Int($0 * 100))%" }
            ?? NSLocalizedString("mengukur…", comment: "")
    }

    /// Bar tetap teal selama masih wajar — amber hanya saat benar-benar
    /// hampir penuh, agar tidak menjadi alarm palsu (anti scare-tactics).
    private func barColor(fraction: Double) -> Color {
        fraction >= 0.85 ? DKColor.attention : Color.respite
    }
}
