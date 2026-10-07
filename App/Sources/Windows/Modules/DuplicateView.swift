import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Duplicate Finder (TRD §4.7): duplikat persis (byte identik) untuk semua
/// jenis file — termasuk foto. Folder target dipilih user; hasil per grup
/// dengan saran "simpan yang terlama"; hapus salinan lewat Trash.
struct DuplicateView: View {
    private let thresholds: [Int64] = [1_000_000, 10_000_000, 50_000_000]

    @ObservedObject private var model = DuplicateModel.shared
    @State private var showDryRunPreview = false
    @State private var search = ""

    /// Grup yang lolos filter pencarian (nama file / folder anggotanya).
    private var visibleGroups: [DuplicateGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.groups }
        return model.groups.filter { group in
            group.files.contains { $0.url.path.localizedCaseInsensitiveContains(query) }
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                controls

                if case .cleaned(let bytes) = model.phase {
                    HStack {
                        Label {
                            Text(String(
                                format: NSLocalizedString("%@ berhasil dibersihkan", comment: ""),
                                ByteFormat.string(from: bytes)
                            ))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .foregroundStyle(DKColor.accent)
                        Spacer()
                        Button("Buka Trash") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.Trash").expandingTildeInPath))
                        }
                        .controlSize(.small)
                    }
                    .padding(DKSpacing.md)
                    .background(DKColor.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }

                if !model.groups.isEmpty {
                    searchField
                }

                ForEach(visibleGroups) { group in
                    groupCard(group)
                }

                Text(NSLocalizedString("Deteksi duplikat persis (byte identik) — berlaku untuk semua jenis file termasuk foto. Deteksi foto yang mirip secara visual tapi berbeda byte (Similar Photos) menyusul sebagai fitur terpisah.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(
            NSLocalizedString("Pratinjau sebelum membersihkan", comment: ""),
            isPresented: $showDryRunPreview
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: DuplicateModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d salinan (%@) akan dipindah ke Trash dan bisa dikembalikan dari sana.",
                    comment: ""
                ),
                model.selected.count,
                ByteFormat.string(from: selectedBytes)
            ))
        }
    }

    /// Gate dry-run: pertama kali → pratinjau dulu; setelah itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showDryRunPreview = true
        }
    }

    // MARK: Kontrol

    private var searchField: some View {
        HStack(spacing: DKSpacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(
                NSLocalizedString("Cari nama atau folder…", comment: ""),
                text: $search
            )
            .textFieldStyle(.roundedBorder)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Bersihkan pencarian", comment: ""))
            }
        }
        .frame(maxWidth: 260, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            HStack(spacing: DKSpacing.md) {
                Button {
                    pickFolder()
                } label: {
                    Label(
                        model.root.map { $0.lastPathComponent } ?? NSLocalizedString("Pilih folder…", comment: ""),
                        systemImage: "folder.badge.plus"
                    )
                }
                Picker(NSLocalizedString("Minimal", comment: ""), selection: $model.minBytes) {
                    ForEach(thresholds, id: \.self) { bytes in
                        Text(ByteFormat.string(from: bytes)).tag(bytes)
                    }
                }
                .fixedSize()
                Spacer()
                Button {
                    model.startScan()
                } label: {
                    Label("Mulai Pindai", systemImage: "square.on.square")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(model.root == nil)
            }
            if model.root == nil {
                Text(NSLocalizedString("Pilih folder yang sering menumpuk duplikat — misalnya folder foto, Downloads, atau Documents.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .scanning:
            HStack(spacing: DKSpacing.md) {
                ProgressView()
                Text(String(
                    format: NSLocalizedString("%d file dipindai · %d grup", comment: ""),
                    model.scannedCount, model.groups.count
                ))
                .foregroundColor(.secondary)
                Spacer()
                Button("Batalkan") { model.cancelScan() }
            }

        case .results, .cleaned:
            HStack(spacing: DKSpacing.md) {
                Button {
                    model.startScan()
                } label: {
                    Label("Pindai Ulang", systemImage: "arrow.clockwise")
                }
                Text(String(
                    format: NSLocalizedString("%d grup · hemat potensial %@", comment: ""),
                    model.groups.count,
                    ByteFormat.string(from: reclaimableBytes)
                ))
                .font(.dkData(12))
                .foregroundStyle(.secondary)
                Spacer()
                Text(String(
                    format: NSLocalizedString("%@ terpilih", comment: ""),
                    ByteFormat.string(from: selectedBytes)
                ))
                .font(.dkData(13))
                .foregroundStyle(.secondary)
                Button("Bersihkan yang dipilih") { handleCleanRequest() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty)
            }
        }
    }

    // MARK: Kartu grup

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(
                    format: NSLocalizedString("%d salinan · %@ per file", comment: ""),
                    group.files.count,
                    ByteFormat.string(from: group.sizeBytes)
                ))
                .font(.title3.weight(.semibold))
                Spacer()
                Text(String(
                    format: NSLocalizedString("hemat %@", comment: ""),
                    ByteFormat.string(from: group.reclaimableBytes)
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }

            VStack(spacing: DKSpacing.sm) {
                ForEach(group.files) { file in
                    HStack {
                        ReadoutRow(
                            value: ByteFormat.string(from: file.sizeBytes),
                            label: file.url.lastPathComponent,
                            detail: file.url.deletingLastPathComponent().path,
                            badge: badgeText(file)
                        )
                        .lineLimit(1)
                        Spacer(minLength: DKSpacing.sm)
                        Toggle("", isOn: Binding(
                            get: { model.selected.contains(file.id) },
                            set: { isChecked in
                                if isChecked { model.selected.insert(file.id) } else { model.selected.remove(file.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .padding(.vertical, DKSpacing.xs)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        QuickLookCoordinator.shared.show(file.url)
                    }
                    .contextMenu {
                        Button {
                            QuickLookCoordinator.shared.show(file.url)
                        } label: {
                            Label(NSLocalizedString("Pratinjau", comment: ""), systemImage: "eye")
                        }
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        } label: {
                            Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "magnifyingglass")
                        }
                    }
                }
            }
            .padding(DKSpacing.md)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    private func badgeText(_ file: DuplicateFile) -> String? {
        if file.isSuggestedKeep {
            return NSLocalizedString("Simpan", comment: "")
        }
        if !file.isSelectedByDefault {
            return NSLocalizedString("Baru", comment: "")
        }
        return nil
    }

    // MARK: Aksi

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("Pilih folder yang ingin diperiksa duplikatnya.", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.root = url
        }
    }

}
