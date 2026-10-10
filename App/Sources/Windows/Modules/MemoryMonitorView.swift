import SwiftUI
import RespiteCore
import DesignKit

/// "Aplikasi Berat": status memori dalam bahasa sehari-hari, daftar aplikasi
/// paling berat (bisa ditutup), lalu perawatan ringan (uptime + "Segarkan
/// tanpa restart" = restart Finder & Dock, kembali sendiri dalam hitungan
/// detik). Istilah teknis (swap, footprint) hanya di "Lihat detail".
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
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            statusCard
            TopProcessesSection(model: model)
            maintenanceSection
            technicalDetails
        }
        .alert(
            NSLocalizedString("Segarkan Mac tanpa restart?", comment: ""),
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

    // MARK: Status memori

    private enum MemoryLevel {
        case relaxed, filling, almostFull
    }

    private var memoryLevel: MemoryLevel {
        let used = model.snapshot.memory.usedFraction
        if used >= 0.85 { return .almostFull }
        if used >= 0.7 { return .filling }
        return .relaxed
    }

    private var statusCard: some View {
        let memory = model.snapshot.memory
        let level = memoryLevel
        let color: Color
        let symbol: String
        let headline: String
        let advice: String
        switch level {
        case .relaxed:
            color = Color.respite
            symbol = "checkmark.seal.fill"
            headline = NSLocalizedString("Memori: cukup lega", comment: "")
            advice = NSLocalizedString("Masih banyak ruang untuk aplikasi lain. Tidak perlu menutup apa pun.", comment: "")
        case .filling:
            color = DKColor.attention
            symbol = "exclamationmark.triangle.fill"
            headline = NSLocalizedString("Memori: mulai penuh", comment: "")
            advice = NSLocalizedString("Masih aman, tapi menutup aplikasi yang tidak dipakai bisa membuat Mac lebih ringan.", comment: "")
        case .almostFull:
            color = DKColor.irreversible
            symbol = "exclamationmark.octagon.fill"
            headline = NSLocalizedString("Memori: hampir penuh", comment: "")
            advice = NSLocalizedString("Mac bisa terasa lambat. Tutup aplikasi berat di bawah yang sedang tidak kamu pakai.", comment: "")
        }
        return ToolCard {
            HStack(spacing: DKSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.title2.weight(.semibold))
                    Text(String(
                        format: NSLocalizedString("%1$@ dari %2$@ terpakai", comment: ""),
                        ByteFormat.string(from: Int64(memory.usedBytes)),
                        ByteFormat.string(from: Int64(memory.totalBytes))
                    ))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }
                Spacer()
            }
            UsageBar(
                fraction: memory.usedFraction,
                color: level == .relaxed ? Color.respite : color
            )
            Text(advice)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Perawatan (uptime + sweep)

    private var maintenanceSection: some View {
        let recommended = verdict.kind == .sweepRecommended
        return VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(NSLocalizedString("Perawatan ringan", comment: ""))
                .font(.headline)

            ToolCard {
                HStack(alignment: .top, spacing: DKSpacing.md) {
                    Image(systemName: "clock")
                        .font(.system(size: 18))
                        .foregroundStyle(recommended ? DKColor.attention : Color.respite)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(
                            format: NSLocalizedString("Sudah menyala selama %@", comment: ""),
                            UptimeFormat.string(from: model.snapshot.uptime)
                        ))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                        Text(NSLocalizedString("Sejak terakhir restart. Mac yang lama tidak direstart kadang terasa makin berat.", comment: ""))
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if recommended {
                    VStack(alignment: .leading, spacing: DKSpacing.xs) {
                        Label {
                            Text(NSLocalizedString("Disarankan menyegarkan Mac sekarang", comment: ""))
                                .font(.callout.weight(.semibold))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundColor(DKColor.attention)
                        ForEach(verdict.reasons, id: \.rawValue) { reason in
                            Text("• " + reasonText(reason))
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider()

                HStack(alignment: .center, spacing: DKSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Segarkan tanpa restart", comment: ""))
                            .font(.callout.weight(.semibold))
                        Text(NSLocalizedString("Finder dan Dock dimulai ulang — hilang sebentar lalu kembali sendiri. Tidak ada data yang hilang.", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        showConfirm = true
                    } label: {
                        Label(NSLocalizedString("Segarkan", comment: ""), systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recommended ? DKColor.attention : Color.respite)
                    .disabled(isSweeping)
                }

                if isSweeping {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Sedang menjalankan…", comment: ""))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }

                if let sweepMessage {
                    Label(sweepMessage, systemImage: sweepFailed ? "exclamationmark.triangle" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundColor(sweepFailed ? DKColor.attention : Color.respite)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func reasonText(_ reason: UptimeVerdict.Reason) -> String {
        switch reason {
        case .longUptime:
            return String(
                format: NSLocalizedString("Mac sudah menyala lebih dari %d hari tanpa restart", comment: ""),
                UptimeGuardian.uptimeDaysThreshold()
            )
        case .highSwap:
            return String(
                format: NSLocalizedString("Mac mulai meminjam ruang penyimpanan sebagai memori cadangan (%@)", comment: ""),
                ByteFormat.string(from: model.snapshot.swap?.usedBytes ?? 0)
            )
        case .lowMemory:
            return String(
                format: NSLocalizedString("Memori yang masih bebas tinggal %d%%", comment: ""),
                Int(model.snapshot.memory.availableFraction * 100)
            )
        }
    }

    // MARK: Detail teknis

    private var technicalDetails: some View {
        ToolDetails {
            detailRow(
                NSLocalizedString("Swap terpakai", comment: ""),
                value: swapValue
            )
            detailRow(
                NSLocalizedString("Memori tersedia (free + inactive)", comment: ""),
                value: String(
                    format: NSLocalizedString("%1$@ (%2$d%%)", comment: ""),
                    ByteFormat.string(from: model.snapshot.memory.availableBytes),
                    Int(model.snapshot.memory.availableFraction * 100)
                )
            )
            // PRD G2: hemat RAM itu janji produk — jejaknya ditampilkan terbuka.
            detailRow(
                NSLocalizedString("Jejak memori Respite sendiri (footprint)", comment: ""),
                value: ByteFormat.string(from: model.ownFootprintBytes)
            )
            Text(NSLocalizedString("Swap: saat RAM mulai sempit, macOS memindahkan isi memori yang jarang dipakai ke disk. Swap tidak otomatis turun setelah memori lega — cara paling aman mengosongkannya adalah menutup aplikasi berat atau restart Mac. Penghapusan swapfile manual sengaja tidak disediakan karena berisiko.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("\"Segarkan tanpa restart\" (Maintenance Sweep) versi ini hanya menjalankan langkah tanpa privilege: restart Finder dan Dock. Langkah sistem-level (purge memori, periodic scripts, memori compressed) akan menyusul bersama privileged helper.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("Jejak memori Respite memakai angka yang sama dengan kolom Memory di Activity Monitor. Target kami: tetap jauh lebih ringan dari aplikasi yang dibersihkannya.", comment: ""))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var swapValue: String {
        guard let swap = model.snapshot.swap else { return "—" }
        return String(
            format: NSLocalizedString("%1$@ dari %2$@", comment: ""),
            ByteFormat.string(from: swap.usedBytes),
            ByteFormat.string(from: swap.totalBytes)
        )
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    // MARK: Sweep

    private func runSweep() {
        isSweeping = true
        sweepMessage = nil
        let steps = sweepSteps
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                MaintenanceSweep.restartProcesses(steps)
            }.value
            isSweeping = false
            if outcome.failed.isEmpty {
                sweepFailed = false
                sweepMessage = NSLocalizedString("Selesai — Finder dan Dock sudah dimulai ulang.", comment: "")
            } else {
                sweepFailed = true
                sweepMessage = String(
                    format: NSLocalizedString("Ada yang gagal: %@", comment: ""),
                    outcome.failed.map(\.name).joined(separator: ", ")
                )
            }
        }
    }
}
