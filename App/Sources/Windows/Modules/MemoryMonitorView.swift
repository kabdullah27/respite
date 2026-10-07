import SwiftUI
import RespiteCore
import DesignKit

/// Uptime Guardian versi in-app: status uptime/swap/memori, verdict apakah
/// Maintenance Sweep disarankan, dan sweep tanpa privilege (restart Finder &
/// Dock — kembali sendiri dalam hitungan detik). Langkah sistem-level
/// menyusul bareng privileged helper.
struct MemoryMonitorView: View {
    @ObservedObject var model: SystemStatsModel
    @State private var showConfirm = false
    @State private var isSweeping = false
    @State private var sweepMessage: String?
    @State private var sweepFailed = false

    /// Hanya langkah aman level user — auto-restart sendiri oleh macOS.
    private let sweepSteps = ["Finder", "Dock"]

    private var verdict: UptimeVerdict {
        UptimeGuardian.evaluate(
            uptime: model.snapshot.uptime,
            swapUsedBytes: model.snapshot.swap?.usedBytes ?? 0,
            memoryAvailableFraction: model.snapshot.memory.availableFraction,
            uptimeDays: UptimeGuardian.uptimeDaysThreshold(),
            swapThresholdBytes: UptimeGuardian.swapThresholdBytes()
        )
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            metricsSection
            statusCard
            swapExplanationCard
            verdictCard

            Button {
                showConfirm = true
            } label: {
                Label("Jalankan Maintenance Sweep", systemImage: "sparkles")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isSweeping)

            if isSweeping {
                HStack(spacing: DKSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Sedang menjalankan…").font(.callout).foregroundColor(.secondary)
                }
            }

            if let sweepMessage {
                Label(sweepMessage, systemImage: sweepFailed ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundColor(sweepFailed ? DKColor.attention : DKColor.accent)
            }

            Text(NSLocalizedString("Versi ini hanya menjalankan langkah tanpa privilege. Langkah sistem-level (purge memori, periodic scripts) akan menyusul bersama privileged helper.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        }
        .alert(
            NSLocalizedString("Konfirmasi Maintenance Sweep", comment: ""),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                runSweep()
            }
        } message: {
            Text(NSLocalizedString("Finder dan Dock akan direstart — keduanya hilang sebentar (±2 detik) lalu kembali sendiri. Tidak ada data yang hilang.", comment: ""))
        }
    }

    // MARK: Metrik

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            Text(NSLocalizedString("Sekarang", comment: "")).font(.title3.weight(.semibold))
            HStack(spacing: DKSpacing.lg) {
                MetricCard(
                    title: NSLocalizedString("Memori terpakai", comment: ""),
                    value: ByteFormat.string(from: model.snapshot.memory.usedBytes),
                    unit: String(
                        format: NSLocalizedString("dari %@", comment: "kartu: dari total X GB"),
                        ByteFormat.string(from: model.snapshot.memory.totalBytes)
                    )
                )
                MetricCard(
                    title: NSLocalizedString("Tersedia", comment: ""),
                    value: ByteFormat.string(from: model.snapshot.memory.availableBytes),
                    unit: "free + inactive"
                )
                MetricCard(
                    title: NSLocalizedString("Disk tersedia", comment: ""),
                    value: ByteFormat.string(from: model.snapshot.disk.availableBytes),
                    unit: String(
                        format: NSLocalizedString("dari %@", comment: "kartu: dari total X GB"),
                        ByteFormat.string(from: model.snapshot.disk.totalBytes)
                    )
                )
            }
            factorRow(
                label: NSLocalizedString("CPU", comment: ""),
                fraction: model.cpuUsageFraction ?? 0,
                value: model.cpuUsageFraction
                    .map { String(format: NSLocalizedString("%d%% dipakai", comment: ""), Int($0 * 100)) }
                    ?? NSLocalizedString("mengukur…", comment: "")
            )
            factorRow(
                label: NSLocalizedString("Memori", comment: ""),
                fraction: model.snapshot.memory.usedFraction,
                value: String(
                    format: NSLocalizedString("%d%% dipakai", comment: ""),
                    Int(model.snapshot.memory.usedFraction * 100)
                )
            )
            factorRow(
                label: NSLocalizedString("Disk", comment: ""),
                fraction: 1 - model.snapshot.disk.availableFraction,
                value: String(
                    format: NSLocalizedString("%@ tersedia", comment: ""),
                    ByteFormat.string(from: model.snapshot.disk.availableBytes)
                )
            )
            TopProcessesSection(model: model)

            // PRD G2: hemat RAM itu janji produk — jejaknya ditampilkan terbuka.
            HStack {
                Text(NSLocalizedString("Jejak memori Respite sendiri", comment: ""))
                    .font(.callout)
                Spacer()
                Text(ByteFormat.string(from: model.ownFootprintBytes))
                    .font(.dkData(13))
            }
            Text(NSLocalizedString("Angka yang sama dengan kolom Memory di Activity Monitor. Target kami: tetap jauh lebih ringan dari aplikasi yang dibersihkannya.", comment: ""))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func factorRow(label: String, fraction: Double, value: String, note: String? = nil) -> some View {
        VStack(spacing: DKSpacing.xs) {
            HStack {
                Text(label).font(.callout)
                Spacer()
                Text(value).font(.dkData(12))
                if let note {
                    Text("· \(note)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            UsageBar(fraction: fraction, color: fraction >= 0.85 ? DKColor.attention : DKColor.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Sekarang", comment: "")).font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                ReadoutRow(
                    value: UptimeFormat.string(from: model.snapshot.uptime),
                    unit: nil,
                    label: NSLocalizedString("Uptime", comment: ""),
                    detail: NSLocalizedString("sejak terakhir restart, termasuk waktu sleep", comment: "")
                )
                ReadoutRow(
                    value: ByteFormat.string(from: model.snapshot.swap?.usedBytes ?? 0),
                    unit: nil,
                    label: NSLocalizedString("Swap", comment: ""),
                    detail: swapDetail
                )
                ReadoutRow(
                    value: "\(Int(model.snapshot.memory.availableFraction * 100))%",
                    unit: nil,
                    label: NSLocalizedString("Memori tersedia", comment: ""),
                    detail: NSLocalizedString("free + inactive dari total RAM", comment: "")
                )
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    private var swapDetail: String {
        guard let swap = model.snapshot.swap else { return "—" }
        return String(
            format: NSLocalizedString("dari kapasitas swap %@", comment: ""),
            ByteFormat.string(from: swap.totalBytes)
        )
    }

    // MARK: Penjelasan swap

    /// Jawaban jujur buat "kenapa swap gede & bisa dihapus?" — tanpa tombol
    /// hapus: itu step high-risk tier yang digate privileged helper (PRD §5.1).
    private var swapExplanationCard: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            Label {
                Text(NSLocalizedString("Kenapa swap bisa besar?", comment: ""))
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DKColor.accent)
            }
            VStack(alignment: .leading, spacing: DKSpacing.xs) {
                Text("• " + NSLocalizedString("Saat RAM mulai sempit, macOS memindahkan halaman memori yang jarang dipakai ke disk — itulah swap.", comment: ""))
                Text("• " + NSLocalizedString("Swap tidak otomatis turun setelah memorinya lega — ruangnya tetap terpakai sampai halaman benar-benar tidak dibutuhkan lagi.", comment: ""))
                Text("• " + NSLocalizedString("Cara paling aman mengosongkannya: tutup aplikasi pemakan memori di bawah, atau restart Mac. Penghapusan swapfile manual adalah langkah berisiko yang sengaja tidak disediakan di sini.", comment: ""))
            }
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    // MARK: Verdict

    private var verdictCard: some View {
        let recommended = verdict.kind == .sweepRecommended
        return VStack(alignment: .leading, spacing: DKSpacing.sm) {
            Label {
                Text(recommended
                     ? NSLocalizedString("Maintenance Sweep disarankan", comment: "")
                     : NSLocalizedString("Kondisi belum memerlukan Maintenance Sweep.", comment: ""))
                    .font(.title3.weight(.medium))
            } icon: {
                Image(systemName: recommended ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(recommended ? DKColor.attention : DKColor.accent)

            if recommended {
                VStack(alignment: .leading, spacing: DKSpacing.xs) {
                    ForEach(verdict.reasons, id: \.rawValue) { reason in
                        Text("• " + reasonText(reason))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(DKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((verdict.kind == .sweepRecommended ? DKColor.attention : DKColor.accent).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    private func reasonText(_ reason: UptimeVerdict.Reason) -> String {
        switch reason {
        case .longUptime:
            return String(
                format: NSLocalizedString("Uptime sudah mencapai %d hari", comment: ""),
                UptimeGuardian.uptimeDaysThreshold()
            )
        case .highSwap:
            return String(
                format: NSLocalizedString("Pemakaian swap tinggi (%@)", comment: ""),
                ByteFormat.string(from: model.snapshot.swap?.usedBytes ?? 0)
            )
        case .lowMemory:
            return String(
                format: NSLocalizedString("Memori tersedia tinggal %d%%", comment: ""),
                Int(model.snapshot.memory.availableFraction * 100)
            )
        }
    }

    // MARK: Sweep

    private func runSweep() {
        isSweeping = true
        sweepMessage = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                MaintenanceSweep.restartProcesses(["Finder", "Dock"])
            }.value
            isSweeping = false
            if outcome.failed.isEmpty {
                sweepFailed = false
                sweepMessage = NSLocalizedString("Maintenance Sweep selesai — Finder & Dock sudah direstart.", comment: "")
            } else {
                sweepFailed = true
                sweepMessage = String(
                    format: NSLocalizedString("Step gagal: %@", comment: ""),
                    outcome.failed.map(\.name).joined(separator: ", ")
                )
            }
        }
    }
}
