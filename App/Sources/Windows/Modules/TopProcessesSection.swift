import SwiftUI
import RespiteCore
import DesignKit

/// Daftar proses pemakai memori & CPU terbesar — dipakai Uptime Guardian &
/// Memory Monitor. Tab Memori (footprint, refresh manual) + tab CPU (beban
/// delta per tick, live). Tiap baris ada tombol Hentikan (konfirmasi dulu,
/// SIGTERM graceful, proses kritis nggak pernah bisa).
struct TopProcessesSection: View {
    @ObservedObject var model: SystemStatsModel
    @State private var mode = 0
    @State private var groups: [ProcessGroup] = []
    @State private var isLoading = false
    @State private var pendingKillName: String?
    @State private var pendingKillPids: [Int32] = []
    @State private var killMessage: String?
    @State private var killFailed = false
    @State private var pendingKillForce = false

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack {
                Text(NSLocalizedString("Pemakai memori terbesar", comment: ""))
                    .font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $mode) {
                    Text(NSLocalizedString("Memori", comment: "")).tag(0)
                    Text(NSLocalizedString("CPU", comment: "")).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Button {
                    if mode == 0 {
                        Task { await load() }
                    } else {
                        model.refreshNow()
                    }
                } label: {
                    Label(NSLocalizedString("Segarkan", comment: ""), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            if !model.runaway.isEmpty {
                runawayBanner
            }

            Text(mode == 0
                 ? NSLocalizedString("Proses-proses ini penyumbang tekanan memori terbesar — penyebab utama swap bertambah. Proses dengan nama sama digabung jadi satu baris. Atribusi swap per-proses tidak tersedia di API publik macOS.", comment: "")
                 : NSLocalizedString("Beban CPU per proses, dihitung dari delta waktu CPU antar pembaruan (metrik yang sama dengan Activity Monitor), diperbarui otomatis tiap 2 detik. Status \"Not Responding\" hanya bisa dibaca lewat API privat — app yang macet justru turun ke 0%.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let killMessage {
                Label(killMessage, systemImage: killFailed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundColor(killFailed ? DKColor.attention : DKColor.accent)
            }

            if mode == 0 {
                memoryList
            } else {
                cpuList
            }
        }
        .task {
            if groups.isEmpty { await load() }
        }
        .alert(
            NSLocalizedString("Hentikan proses", comment: ""),
            isPresented: Binding(
                get: { pendingKillName != nil },
                set: { if !$0 { pendingKillName = nil } }
            )
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Hentikan Paksa", comment: ""), role: .destructive) {
                if let name = pendingKillName {
                    performKill(name: name, pids: pendingKillPids, force: true)
                }
                pendingKillName = nil
            }
            Button(NSLocalizedString("Hentikan", comment: ""), role: .destructive) {
                if let name = pendingKillName {
                    performKill(name: name, pids: pendingKillPids, force: false)
                }
                pendingKillName = nil
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "%1$@ (%2$d proses). \"Hentikan\" mengirim sinyal sopan (SIGTERM) — aplikasi sempat menyimpan pekerjaan; \"Hentikan Paksa\" (SIGKILL) langsung mematikan tanpa kesempatan menyimpan, untuk proses yang macet atau mengabaikan sinyal sopan. Pekerjaan belum tersimpan bisa hilang. Proses milik sistem/root tetap tidak bisa tanpa privilege; proses yang dijaga launchd bisa hidup lagi — matikan agent-nya di Aplikasi Saat Login.",
                    comment: ""
                ),
                pendingKillName ?? "",
                pendingKillPids.count
            ))
        }
    }

    // MARK: Banner proses liar (watchdog)

    private var runawayBanner: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            ForEach(model.runaway) { verdict in
                HStack(alignment: .top, spacing: DKSpacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DKColor.attention)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(
                            format: NSLocalizedString("%1$@ — CPU tinggi berkelanjutan (rata-rata %2$d%% selama ±%3$d menit)", comment: ""),
                            verdict.name,
                            Int(verdict.averageFraction * 100),
                            Int(verdict.sustainedMinutes)
                        ))
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        Text(NSLocalizedString("Proses berat yang berjalan terus-menerus — bukan spike sesaat. Periksa apakah masih diperlukan.", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(NSLocalizedString("Hentikan", comment: "")) {
                        if let current = model.topCPUGroups.first(where: { $0.name == verdict.name }) {
                            pendingKillName = verdict.name
                            pendingKillPids = current.pids
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(DKSpacing.md)
        .background(DKColor.attention.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    // MARK: Tab memori

    @ViewBuilder
    private var memoryList: some View {
        if isLoading && groups.isEmpty {
            HStack(spacing: DKSpacing.sm) {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("Memuat…", comment: "")).font(.callout).foregroundColor(.secondary)
            }
        } else if groups.isEmpty {
            Text(NSLocalizedString("Tidak ada proses dengan memori cukup besar untuk ditampilkan.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: DKSpacing.sm) {
                ForEach(groups) { group in
                    processRow(
                        value: ByteFormat.string(from: group.totalFootprintBytes),
                        name: group.name,
                        pids: group.pids
                    )
                }
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    // MARK: Tab CPU (live dari model)

    @ViewBuilder
    private var cpuList: some View {
        if model.topCPUGroups.isEmpty {
            Text(NSLocalizedString("Beban CPU seimbang — tidak ada proses dominan.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: DKSpacing.sm) {
                ForEach(model.topCPUGroups) { group in
                    processRow(
                        value: String(
                            format: NSLocalizedString("%d%%", comment: ""),
                            Int(group.fraction * 100)
                        ),
                        name: group.name,
                        pids: group.pids
                    )
                }
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    private func processRow(value: String, name: String, pids: [Int32]) -> some View {
        HStack {
            ReadoutRow(value: value, label: name, detail: nil)
                .lineLimit(1)
            Spacer(minLength: DKSpacing.sm)
            Text(pids.count > 1
                 ? String(format: NSLocalizedString("%d proses", comment: ""), pids.count)
                 : "PID \(pids.first ?? 0)"
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            Button(NSLocalizedString("Hentikan", comment: "")) {
                pendingKillName = name
                pendingKillPids = pids
            }
            .controlSize(.small)
        }
    }

    private func load() async {
        isLoading = true
        let result = await Task.detached(priority: .userInitiated) {
            TopProcesses.groupedByMemoryFootprint()
        }.value
        groups = result
        isLoading = false
    }

    private func performKill(name: String, pids: [Int32], force: Bool) {
        var terminated = 0
        var lastReason = ""
        for pid in pids {
            let outcome = ProcessKiller.terminate(pid: pid, name: name, force: force)
            if outcome.succeeded {
                terminated += 1
            } else {
                lastReason = outcome.rawReason
            }
        }
        if terminated == pids.count {
            killFailed = false
            killMessage = pids.count > 1
                ? String(
                    format: NSLocalizedString("Sinyal penghentian dikirim ke %d proses %@.", comment: ""),
                    terminated, name
                )
                : String(
                    format: NSLocalizedString("Sinyal penghentian dikirim ke %@.", comment: ""),
                    name
                )
        } else {
            killFailed = true
            let alasan: String
            switch lastReason {
            case "protected-process":
                alasan = NSLocalizedString("proses ini dilindungi sistem dan tidak pernah bisa dihentikan", comment: "")
            case "Operation not permitted":
                alasan = NSLocalizedString("prosesnya milik root/sistem — butuh privilege yang Respite sengaja tidak minta", comment: "")
            case "No such process":
                alasan = NSLocalizedString("prosesnya sudah berhenti sendiri", comment: "")
            default:
                alasan = lastReason
            }
            killMessage = String(
                format: NSLocalizedString("Gagal menghentikan %1$@ (%2$d dari %3$d terkirim) — %4$@. Kalau prosesnya hidup lagi setelah dihentikan, dia dijaga launchd: matikan agent-nya di Aplikasi Saat Login.", comment: ""),
                name, terminated, pids.count, alasan
            )
        }
        Task { await load() }
    }
}
