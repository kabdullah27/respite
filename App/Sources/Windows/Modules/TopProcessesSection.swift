import SwiftUI
import RespiteCore
import DesignKit

/// Daftar aplikasi paling berat (memori & tenaga prosesor) — dipakai halaman
/// "Aplikasi Berat". Tiap baris ada tombol Tutup (konfirmasi dulu; tutup
/// sopan = SIGTERM, Tutup Paksa = SIGKILL; proses kritis nggak pernah bisa).
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
                Text(NSLocalizedString("Aplikasi yang paling berat", comment: ""))
                    .font(.headline)
                Spacer()
                Picker("", selection: $mode) {
                    Text(NSLocalizedString("Memori", comment: "")).tag(0)
                    Text(NSLocalizedString("Prosesor", comment: "")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
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

            Text(mode == 0
                 ? NSLocalizedString("Aplikasi yang paling banyak memakai memori. Tutup yang tidak sedang kamu pakai supaya Mac lebih lega.", comment: "")
                 : NSLocalizedString("Aplikasi yang sedang paling sibuk bekerja. Angkanya diperbarui sendiri setiap 2 detik.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.runaway.isEmpty {
                runawayBanner
            }

            if let killMessage {
                Label(killMessage, systemImage: killFailed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundColor(killFailed ? DKColor.attention : Color.respite)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode == 0 {
                memoryList
            } else {
                cpuList
            }

            ToolDetails(title: NSLocalizedString("Lihat detail daftar ini", comment: "")) {
                Text(NSLocalizedString("Proses-proses ini penyumbang tekanan memori terbesar — penyebab utama swap bertambah. Proses dengan nama sama digabung jadi satu baris. Atribusi swap per-proses tidak tersedia di API publik macOS.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("Beban CPU per proses, dihitung dari delta waktu CPU antar pembaruan (metrik yang sama dengan Activity Monitor), diperbarui otomatis tiap 2 detik. Status \"Not Responding\" hanya bisa dibaca lewat API privat — app yang macet justru turun ke 0%.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("100% berarti satu inti prosesor penuh; aplikasi yang memakai beberapa inti bisa lebih dari 100%.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("\"Tutup\" mengirim SIGTERM (aplikasi sempat menyimpan pekerjaan). \"Tutup Paksa\" mengirim SIGKILL — langsung mati tanpa menyimpan. Proses milik sistem/root tidak bisa dihentikan tanpa privilege; proses yang dijaga launchd bisa hidup lagi — matikan agent-nya di Aplikasi Saat Login.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            if groups.isEmpty { await load() }
        }
        .alert(
            String(
                format: NSLocalizedString("Tutup %@?", comment: ""),
                pendingKillName ?? ""
            ),
            isPresented: Binding(
                get: { pendingKillName != nil },
                set: { if !$0 { pendingKillName = nil } }
            )
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Tutup Paksa", comment: ""), role: .destructive) {
                if let name = pendingKillName {
                    performKill(name: name, pids: pendingKillPids, force: true)
                }
                pendingKillName = nil
            }
            Button(NSLocalizedString("Tutup", comment: ""), role: .destructive) {
                if let name = pendingKillName {
                    performKill(name: name, pids: pendingKillPids, force: false)
                }
                pendingKillName = nil
            }
        } message: {
            Text(NSLocalizedString(
                "\"Tutup\" meminta aplikasi menutup dengan sopan, jadi pekerjaanmu sempat disimpan. Pakai \"Tutup Paksa\" hanya kalau aplikasinya macet — pekerjaan yang belum disimpan bisa hilang.",
                comment: ""
            ))
        }
    }

    // MARK: Banner aplikasi yang terus sibuk (watchdog)

    private var runawayBanner: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            ForEach(model.runaway) { verdict in
                HStack(alignment: .top, spacing: DKSpacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DKColor.attention)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(
                            format: NSLocalizedString("%1$@ terus bekerja keras selama ±%3$d menit (rata-rata %2$d%% tenaga prosesor)", comment: ""),
                            verdict.name,
                            Int(verdict.averageFraction * 100),
                            Int(verdict.sustainedMinutes)
                        ))
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        Text(NSLocalizedString("Bukan lonjakan sesaat. Kalau kamu tidak sedang memakainya, sebaiknya ditutup.", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(NSLocalizedString("Tutup", comment: "")) {
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
            Text(NSLocalizedString("Tidak ada aplikasi yang memakai banyak memori.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
        } else {
            processList(groups.map { group in
                (
                    name: group.name,
                    usage: String(
                        format: NSLocalizedString("memakai %@", comment: ""),
                        ByteFormat.string(from: group.totalFootprintBytes)
                    ),
                    pids: group.pids
                )
            })
        }
    }

    // MARK: Tab prosesor (live dari model)

    @ViewBuilder
    private var cpuList: some View {
        if model.topCPUGroups.isEmpty {
            Text(NSLocalizedString("Tidak ada aplikasi yang membebani prosesor.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
        } else {
            processList(model.topCPUGroups.map { group in
                (
                    name: group.name,
                    usage: String(
                        format: NSLocalizedString("memakai %d%% tenaga prosesor", comment: ""),
                        Int(group.fraction * 100)
                    ),
                    pids: group.pids
                )
            })
        }
    }

    private func processList(_ rows: [(name: String, usage: String, pids: [Int32])]) -> some View {
        VStack(spacing: DKSpacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.element.name) { index, row in
                processRow(name: row.name, usage: row.usage, pids: row.pids)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(DKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    private func processRow(name: String, usage: String, pids: [Int32]) -> some View {
        HStack(spacing: DKSpacing.md) {
            HStack(spacing: 0) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(" · " + usage)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            Spacer(minLength: DKSpacing.sm)
            Button(NSLocalizedString("Tutup", comment: "")) {
                pendingKillName = name
                pendingKillPids = pids
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
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
            case "pid-reused":
                alasan = NSLocalizedString("prosesnya sudah berhenti dan PID-nya kini dipakai proses lain — tidak dihentikan", comment: "")
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
