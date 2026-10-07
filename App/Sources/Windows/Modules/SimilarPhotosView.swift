import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Similar Photos (TRD §4.15): foto MIRIP secara visual (beda byte) — hasil
/// edit/resize/rekaman ulang. aHash 8×8 + jarak Hamming; duplikat persis
/// otomatis ikut kegrup. Suggested keep = file terbesar (kualitas tertinggi).
struct SimilarPhotosView: View {

    @ObservedObject private var model = SimilarPhotosModel.shared
    @State private var showDryRunPreview = false
    @State private var search = ""

    /// Grup yang lolos filter pencarian (nama file anggotanya).
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

                Text(NSLocalizedString("Perbandingan visual dengan sidik jari ringan (aHash 8×8, tanpa model ML): foto dengan komposisi serupa dikelompokkan — hasil edit, resize, atau rekaman ulang. Kecocokan bukan kepastian: periksa thumbnail sebelum menghapus.", comment: ""))
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
                UserDefaults.standard.set(true, forKey: SimilarPhotosModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d foto (%@) akan dipindah ke Trash dan bisa dikembalikan dari sana.",
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
                        model.root.map { $0.lastPathComponent } ?? NSLocalizedString("Pilih folder foto…", comment: ""),
                        systemImage: "folder.badge.plus"
                    )
                }
                Spacer()
                Button {
                    model.startScan()
                } label: {
                    Label("Mulai Pindai", systemImage: "photo.on.rectangle")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(model.root == nil)
            }

        case .scanning:
            HStack(spacing: DKSpacing.md) {
                ProgressView()
                Text(String(
                    format: NSLocalizedString("%d foto dipindai · %d grup", comment: ""),
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
                    format: NSLocalizedString("%d grup mirip", comment: ""),
                    model.groups.count
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

    // MARK: Kartu grup (dengan thumbnail)

    private func groupCard(_ group: SimilarPhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            Text(String(
                format: NSLocalizedString("%d foto mirip", comment: ""),
                group.files.count
            ))
            .font(.title3.weight(.semibold))

            HStack(alignment: .top, spacing: DKSpacing.md) {
                ForEach(group.files) { file in
                    photoTile(file)
                }
            }
            .padding(DKSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
        }
    }

    private func photoTile(_ file: DuplicateFile) -> some View {
        VStack(spacing: DKSpacing.xs) {
            ZStack(alignment: .topTrailing) {
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
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.control))

                Image(systemName: model.selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, model.selected.contains(file.id) ? DKColor.accent : Color.secondary.opacity(0.6))
                    .padding(DKSpacing.xs)
                    .onTapGesture {
                        if model.selected.contains(file.id) {
                            model.selected.remove(file.id)
                        } else {
                            model.selected.insert(file.id)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(ByteFormat.string(from: file.sizeBytes))
                    .font(.dkData(10))
                    .foregroundColor(.primary)
                Text(file.url.lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(width: 72, alignment: .leading)
                if file.isSuggestedKeep {
                    Text(NSLocalizedString("Simpan", comment: ""))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DKColor.accent)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.selected.contains(file.id) {
                model.selected.remove(file.id)
            } else {
                model.selected.insert(file.id)
            }
        }
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

    // MARK: Aksi

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = NSLocalizedString("Pilih folder berisi foto yang ingin diperiksa kemiripannya.", comment: "")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.root = url
        }
    }

}
