import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Foto Mirip: cari foto yang tampilannya hampir sama (hasil edit, ubah
/// ukuran, foto beruntun) → tiap kelompok menyisakan satu ("Disimpan") →
/// sisanya ke Trash. Pola halaman mengikuti ToolPage.
/// State di `SimilarPhotosModel.shared` — pindah alat tidak menghentikan scan.
struct SimilarPhotosView: View {

    @ObservedObject private var model = SimilarPhotosModel.shared
    @State private var showConfirm = false
    @State private var search = ""

    /// Kelompok yang lolos pencarian (nama file / folder anggotanya).
    private var visibleGroups: [SimilarPhotoGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.groups }
        return model.groups.filter { group in
            group.files.contains { $0.url.path.localizedCaseInsensitiveContains(query) }
        }
    }

    private var selectedBytes: Int64 {
        model.groups.flatMap(\.files)
            .filter { model.selected.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    /// Perkiraan hemat kalau tiap kelompok hanya menyisakan yang "Disimpan".
    private var reclaimableBytes: Int64 {
        model.groups.reduce(0) { total, group in
            let keepID = (group.files.first(where: \.isSuggestedKeep) ?? group.files.first)?.id
            return total + group.files.filter { $0.id != keepID }.reduce(0) { $0 + $1.sizeBytes }
        }
    }

    private var extraPhotos: Int {
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
                        format: NSLocalizedString("%d foto diperiksa · %d kelompok ditemukan", comment: ""),
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
                UserDefaults.standard.set(true, forKey: SimilarPhotosModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(ToolConfirm.message)
        }
    }

    // MARK: 1. Mulai

    private var startCard: some View {
        ToolStartCard(
            headline: NSLocalizedString("Cari foto yang hampir sama", comment: ""),
            points: [
                NSLocalizedString("Menemukan foto beruntun, hasil edit, atau foto yang diubah ukurannya.", comment: ""),
                NSLocalizedString("Satu foto dari setiap kelompok selalu disimpan.", comment: ""),
                NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
            ],
            buttonSymbol: "photo.on.rectangle",
            isDisabled: model.root == nil,
            action: { model.startScan() }
        ) {
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                Button {
                    pickFolder()
                } label: {
                    Label(
                        model.root.map { $0.lastPathComponent } ?? NSLocalizedString("Pilih folder foto…", comment: ""),
                        systemImage: "folder"
                    )
                }
                if model.root == nil {
                    Text(NSLocalizedString("Pilih folder berisi foto dulu, misalnya Pictures atau Downloads.", comment: ""))
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
                title: NSLocalizedString("Tidak ada foto mirip", comment: ""),
                message: String(
                    format: NSLocalizedString("Semua foto di folder %@ berbeda satu sama lain.", comment: ""),
                    model.root?.lastPathComponent ?? ""
                ),
                onRescan: { model.startScan() }
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d foto mirip · %@", comment: ""),
                    extraPhotos,
                    ByteFormat.string(from: reclaimableBytes)
                ),
                subtitle: NSLocalizedString("Mirip belum tentu sama. Lihat dulu fotonya — klik dua kali untuk memperbesar.", comment: ""),
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
                            photoRow(file)
                        }
                    } header: {
                        Text(String(
                            format: NSLocalizedString("%d foto mirip", comment: ""),
                            group.files.count
                        ))
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 420)

            ToolActionBar(
                selectedCount: model.selected.count,
                selectedBytes: selectedBytes,
                action: requestClean
            )
        }
    }

    /// Baris gaya ToolResultRow + thumbnail supaya bisa dicek sekilas.
    private func photoRow(_ file: DuplicateFile) -> some View {
        let isOn = model.selected.contains(file.id)
        return HStack(spacing: DKSpacing.md) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(file.id) },
                set: { isChecked in
                    if isChecked { model.selected.insert(file.id) } else { model.selected.remove(file.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(file.url.lastPathComponent)

            thumbnail(file)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DKSpacing.sm) {
                    Text(file.url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let badge = badgeText(file, isOn: isOn) {
                        StatusPill(badge, color: file.isSuggestedKeep ? Color.respite : DKColor.attention)
                    }
                }
                Text(String(
                    format: NSLocalizedString("%@ · terakhir diubah %@", comment: ""),
                    file.url.deletingLastPathComponent().lastPathComponent,
                    FriendlyDate.string(file.lastModified)
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: DKSpacing.sm)
            Text(ByteFormat.string(from: file.sizeBytes))
                .font(.dkData(12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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

    private func thumbnail(_ file: DuplicateFile) -> some View {
        Group {
            if let thumb = PhotoThumbnail.image(for: file.url) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.control))
    }

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

    private var details: some View {
        ToolDetails {
            Text(NSLocalizedString("Foto dibandingkan dari tampilannya, bukan dari namanya. Foto yang sama persis ikut terdeteksi.", comment: ""))
            Text(NSLocalizedString("Foto yang ditandai \"Disimpan\" biasanya versi dengan kualitas terbaik. Kalau semua dicentang, satu tetap disisakan.", comment: ""))
            Text(String(
                format: NSLocalizedString("Foto yang diubah %d hari terakhir tidak dicentang otomatis.", comment: ""),
                RecencyGuard.defaultDays
            ))
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
        panel.message = NSLocalizedString("Pilih folder berisi foto yang ingin diperiksa.", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.root = url
            if thenScan { model.startScan() }
        }
    }
}
