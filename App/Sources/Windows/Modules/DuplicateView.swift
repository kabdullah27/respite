import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// File Ganda: cari file yang isinya sama persis di folder pilihan user →
/// tiap kelompok menyisakan satu salinan ("Disimpan") → sisanya ke Trash.
/// Pola halaman mengikuti ToolPage (mulai → mencari → hasil → selesai).
/// State di `DuplicateModel.shared` — pindah alat tidak menghentikan scan.
struct DuplicateView: View {
    private let thresholds: [Int64] = [1_000_000, 10_000_000, 50_000_000]

    @ObservedObject private var model = DuplicateModel.shared
    @State private var showConfirm = false
    @State private var search = ""

    /// Kelompok yang lolos pencarian, paling hemat dulu.
    private var visibleGroups: [DuplicateGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty
            ? model.groups
            : model.groups.filter { group in
                group.files.contains { $0.url.path.localizedCaseInsensitiveContains(query) }
            }
        return filtered.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private var selectedBytes: Int64 {
        var total: Int64 = 0
        for group in model.groups {
            for file in group.files where model.selected.contains(file.id) {
                total += file.sizeBytes
            }
        }
        return total
    }

    private var reclaimableBytes: Int64 {
        model.groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    private var extraCopies: Int {
        model.groups.reduce(0) { $0 + max(0, $1.files.count - 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            switch model.phase {
            case .idle:
                startCard
            case .scanning:
                ToolProgressCard(
                    detail: String(
                        format: NSLocalizedString("%d file diperiksa · %d kelompok ditemukan", comment: ""),
                        model.scannedCount, model.groups.count
                    ),
                    onStop: { model.cancelScan() }
                )
            case .results:
                results
            case .cleaned(let bytes):
                ToolDoneCard(
                    title: String(
                        format: NSLocalizedString("%@ dipindahkan ke Trash", comment: ""),
                        ByteFormat.string(from: bytes)
                    ),
                    message: doneMessage,
                    onRescan: { model.startScan() }
                )
                if !model.groups.isEmpty { results }
            }

            details
        }
        .alert(
            ToolConfirm.title(count: model.selected.count, bytes: selectedBytes),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: DuplicateModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(ToolConfirm.message)
        }
    }

    // MARK: 1. Mulai

    private var startCard: some View {
        ToolStartCard(
            headline: NSLocalizedString("Cari file yang tersimpan lebih dari sekali", comment: ""),
            points: [
                NSLocalizedString("Mencari file yang isinya sama persis, walau namanya beda.", comment: ""),
                NSLocalizedString("Satu salinan dari setiap file selalu disimpan.", comment: ""),
                NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
            ],
            isDisabled: model.root == nil,
            action: { model.startScan() }
        ) {
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                HStack(spacing: DKSpacing.md) {
                    Button {
                        pickFolder()
                    } label: {
                        Label(
                            model.root.map { $0.lastPathComponent } ?? NSLocalizedString("Pilih folder…", comment: ""),
                            systemImage: "folder"
                        )
                    }
                    Picker(NSLocalizedString("Tampilkan file mulai dari", comment: ""), selection: $model.minBytes) {
                        ForEach(thresholds, id: \.self) { bytes in
                            Text(ByteFormat.string(from: bytes)).tag(bytes)
                        }
                    }
                    .fixedSize()
                }
                if model.root == nil {
                    Text(NSLocalizedString("Pilih folder dulu — misalnya Downloads, Documents, atau folder foto.", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: 3. Hasil

    @ViewBuilder
    private var results: some View {
        if model.groups.isEmpty {
            ToolEmptyResult(
                title: NSLocalizedString("Tidak ada file ganda", comment: ""),
                message: String(
                    format: NSLocalizedString("Semua file di folder %@ hanya ada satu salinan.", comment: ""),
                    model.root?.lastPathComponent ?? ""
                ),
                onRescan: { model.startScan() }
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d salinan ganda · %@", comment: ""),
                    extraCopies,
                    ByteFormat.string(from: reclaimableBytes)
                ),
                subtitle: NSLocalizedString("Yang ditandai \"Disimpan\" tetap ada. Centang salinan yang mau dibuang. Klik dua kali untuk melihat isinya.", comment: ""),
                onRescan: { model.startScan() }
            ) {
                HStack(spacing: DKSpacing.md) {
                    TextField(NSLocalizedString("Cari nama atau folder…", comment: ""), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Button {
                        pickFolder(thenScan: true)
                    } label: {
                        Label(NSLocalizedString("Ganti folder…", comment: ""), systemImage: "folder")
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }

            List {
                ForEach(visibleGroups) { group in
                    Section {
                        ForEach(group.files) { file in
                            fileRow(file)
                        }
                    } header: {
                        Text(String(
                            format: NSLocalizedString("%d salinan · hemat %@", comment: ""),
                            group.files.count,
                            ByteFormat.string(from: group.reclaimableBytes)
                        ))
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 360)

            ToolActionBar(
                selectedCount: model.selected.count,
                selectedBytes: selectedBytes,
                action: requestClean
            )
        }
    }

    private func fileRow(_ file: DuplicateFile) -> some View {
        let isOn = model.selected.contains(file.id)
        return ToolResultRow(
            title: file.url.lastPathComponent,
            subtitle: String(
                format: NSLocalizedString("%@ · terakhir diubah %@", comment: ""),
                file.url.deletingLastPathComponent().path,
                FriendlyDate.string(file.lastModified)
            ),
            size: file.sizeBytes,
            badge: badgeText(file, isOn: isOn),
            badgeColor: file.isSuggestedKeep ? Color.respite : DKColor.attention,
            isOn: Binding(
                get: { model.selected.contains(file.id) },
                set: { isChecked in
                    if isChecked { model.selected.insert(file.id) } else { model.selected.remove(file.id) }
                }
            )
        )
        .onTapGesture(count: 2) {
            QuickLookCoordinator.shared.show(file.url)
        }
        .contextMenu {
            Button {
                QuickLookCoordinator.shared.show(file.url)
            } label: {
                Label(NSLocalizedString("Lihat isi", comment: ""), systemImage: "eye")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
            }
        }
    }

    /// "Disimpan" untuk salinan yang disarankan tetap ada; kalau user ikut
    /// mencentangnya, labelnya jadi saran saja.
    private func badgeText(_ file: DuplicateFile, isOn: Bool) -> String? {
        if file.isSuggestedKeep {
            return isOn
                ? NSLocalizedString("Disarankan disimpan", comment: "")
                : NSLocalizedString("Disimpan", comment: "")
        }
        if !file.isSelectedByDefault {
            return NSLocalizedString("Baru dipakai", comment: "")
        }
        return nil
    }

    private var doneMessage: String {
        let base = NSLocalizedString("File ada di Trash. Berubah pikiran? Buka Trash lalu pilih \"Kembalikan\".", comment: "")
        guard model.failureCount > 0 else { return base }
        return base + " " + String(
            format: NSLocalizedString("%d file tidak bisa dipindahkan.", comment: ""),
            model.failureCount
        )
    }

    private var details: some View {
        ToolDetails {
            Text(NSLocalizedString("Dua file dianggap ganda kalau isinya sama persis, bukan cuma namanya.", comment: ""))
            Text(NSLocalizedString("Salinan paling lama ditandai \"Disimpan\". Kalau semua salinan dicentang, satu tetap disisakan.", comment: ""))
            Text(String(
                format: NSLocalizedString("File yang diubah %d hari terakhir tidak dicentang otomatis.", comment: ""),
                RecencyGuard.defaultDays
            ))
            Text(NSLocalizedString("Foto yang hanya mirip (bukan sama persis) dicari di alat Foto Mirip.", comment: ""))
        }
    }

    // MARK: Aksi

    /// Pertama kali → konfirmasi dulu; setelah disetujui, langsung.
    private func requestClean() {
        if !model.requestClean() {
            showConfirm = true
        }
    }

    private func pickFolder(thenScan: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("Pilih folder yang ingin diperiksa file gandanya.", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.root = url
            if thenScan { model.startScan() }
        }
    }
}
