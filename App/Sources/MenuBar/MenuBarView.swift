import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Dropdown menu bar — ringkas & bahasa sehari-hari: status Mac di atas
/// (kalimat yang sama dengan Beranda), empat baris kondisi, satu tombol
/// utama "Bersihkan Mac", lalu footer kecil (buka, pengaturan, keluar).
/// Ditampilkan sebagai popover oleh StatusBarController.
struct MenuBarView: View {
    @ObservedObject var model: SystemStatsModel
    let onOpenApp: (Module?) -> Void

    var body: some View {
        let band = HealthScore.Band.band(for: model.healthScore)
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                header(band: band)
                // Status "perlu perhatian" tanpa alasan = user bingung → satu
                // kalimat temuan utama (teks sama dengan "Kenapa Mac Lambat?").
                if band != .neutral, let reason = topReasonText {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(MacStatus.color(band))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: DKSpacing.md) {
                statusRow(
                    title: NSLocalizedString("Memori", comment: ""),
                    value: String(
                        format: NSLocalizedString("%1$@ dari %2$@ terpakai", comment: ""),
                        ByteFormat.string(from: Int64(model.snapshot.memory.usedBytes)),
                        ByteFormat.string(from: Int64(model.snapshot.memory.totalBytes))
                    ),
                    fraction: model.snapshot.memory.usedFraction
                )
                statusRow(
                    title: NSLocalizedString("Penyimpanan", comment: ""),
                    value: String(
                        format: NSLocalizedString("%@ masih kosong", comment: ""),
                        ByteFormat.string(from: model.snapshot.disk.availableBytes)
                    ),
                    fraction: 1 - model.snapshot.disk.availableFraction
                )
                statusRow(
                    title: NSLocalizedString("Prosesor", comment: ""),
                    value: MacStatus.cpuText(model.cpuUsageFraction),
                    fraction: model.cpuUsageFraction
                )
                statusRow(
                    title: NSLocalizedString("Suhu", comment: ""),
                    value: MacStatus.thermalText(model.snapshot.thermalState) + celsiusSuffix,
                    fraction: nil,
                    valueColor: model.snapshot.thermalState == .nominal ? nil : DKColor.attention
                )
            }

            Button {
                onOpenApp(.smartScan)
            } label: {
                Label(NSLocalizedString("Bersihkan Mac", comment: ""), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.respite)
            .controlSize(.large)

            Divider()

            footer
        }
        .padding(DKSpacing.lg)
        .frame(width: 300)
    }

    // MARK: - Bagian-bagian

    /// Status Mac — klik untuk membuka "Kenapa Mac Lambat?".
    private func header(band: HealthScore.Band) -> some View {
        Button {
            onOpenApp(.diagnostic)
        } label: {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: MacStatus.symbol(band))
                    .font(.system(size: 24))
                    .foregroundStyle(MacStatus.color(band))
                VStack(alignment: .leading, spacing: 1) {
                    Text(MacStatus.headline(band))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(MacStatus.scoreText(model.healthScore))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
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
        .accessibilityHint(NSLocalizedString("Buka Kenapa Mac Lambat?", comment: ""))
    }

    private func statusRow(title: String, value: String, fraction: Double?, valueColor: Color? = nil) -> some View {
        VStack(spacing: DKSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(value)
                    .font(.callout)
                    .foregroundColor(valueColor ?? .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if let fraction {
                UsageBar(fraction: fraction, color: barColor(fraction: fraction))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Aksi sekunder — kecil dan sejajar, supaya tombol utama tetap jelas.
    private var footer: some View {
        VStack(spacing: DKSpacing.sm) {
            HStack(spacing: DKSpacing.md) {
                Button(NSLocalizedString("Buka Respite", comment: "")) {
                    onOpenApp(nil)
                }
                .keyboardShortcut("o")
                Spacer()
                Button(NSLocalizedString("Pengaturan", comment: "")) {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Spacer()
                Button(NSLocalizedString("Keluar", comment: "")) {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundColor(.secondary)

            Button {
                NSWorkspace.shared.open(DonationConfig.donationURL)
            } label: {
                Label(NSLocalizedString("Dukung pengembangan Respite", comment: ""), systemImage: "heart")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Teks & warna

    /// Temuan paling relevan → satu kalimat pendek (teks sama dengan diagnosis).
    private var topReasonText: String? {
        guard let finding = model.diagnosticFindings.first(where: { $0.severity != .info }) else {
            return nil
        }
        if case .allHealthy = finding.kind { return nil }
        return MacStatus.findingText(finding.kind)
    }

    /// " · 62°C" kalau sensor terbaca; kosong kalau tidak.
    private var celsiusSuffix: String {
        model.cpuCelsius.map { String(format: " · %.0f°C", $0) } ?? ""
    }

    /// Bar tetap teal selama masih wajar — amber hanya saat benar-benar
    /// hampir penuh, agar tidak menjadi alarm palsu (anti scare-tactics).
    private func barColor(fraction: Double) -> Color {
        fraction >= 0.85 ? DKColor.attention : Color.respite
    }
}
