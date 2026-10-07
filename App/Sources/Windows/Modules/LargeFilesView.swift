import SwiftUI
import RespiteCore
import DesignKit

/// Large & Old Files Finder (TRD §4.3): pindai home directory, list virtualized,
/// sort ukuran/tanggal, double-click = QuickLook (klik kanan = Finder), hapus
/// ke Trash. State-nya di `LargeFilesModel.shared` — pindah modul tidak
/// mematikan scan yang sedang berjalan (banner + stop ada di Dashboard).
struct LargeFilesView: View {
    private static let dryRunKey = "app.respite.dryRunConfirmed.largeFiles"

    private enum Sort: String, CaseIterable, Identifiable {
        case largest
        case oldest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .largest: return NSLocalizedString("Terbesar", comment: "")
            case .oldest: return NSLocalizedString("Terlama", comment: "")
            }
        }
    }

    private let thresholds: [Int64] = [
        100 * 1_000_000,
        250 * 1_000_000,
        500 * 1_000_000,
        1_000 * 1_000_000,
    ]

    @ObservedObject private var model = LargeFilesModel.shared
    @State private var sort: Sort = .largest
    @State private var showFailedItems = false
    @State private var search = ""
    @State private var showDryRunPreview = false

    private var sortedHits: [FileHit] {
        switch sort {
        case .largest: return model.hits.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest: return model.hits.sorted { $0.lastModified < $1.lastModified }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DKSpacing.lg) {
                    controls

                    if case .cleaned(let bytes) = model.phase {
                        cleanBanner(bytes)
                    }

                    if !model.hits.isEmpty {
                        resultList
                    } else if model.phase == .scanning {
                        HStack(spacing: DKSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Memindai…").foregroundColor(.secondary)
                        }
                    }

                    Text(NSLocalizedString("Folder pribadi (Documents, Desktop, Keychain, Mail, Messages, Photos) tidak ikut discan — itu batas keras Protected List.", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DKSpacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert(
            NSLocalizedString("Pratinjau sebelum membersihkan", comment: ""),
            isPresented: $showDryRunPreview
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                model.performClean(dryRunKey: Self.dryRunKey)
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d file (%@) akan dipindah ke Trash dan bisa dikembalikan dari sana.",
                    comment: ""
                ),
                model.hits.filter { model.selected.contains($0.id) }.count,
                ByteFormat.string(from: model.selectedBytes)
            ))
            + Text(" ")
            + Text(NSLocalizedString("Folder sistem dan dokumen pribadi tidak pernah disentuh oleh aksi ini.", comment: ""))
        }
    }

    // MARK: Kontrol

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            HStack(spacing: DKSpacing.md) {
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
                    Label("Mulai Pindai", systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }

        case .scanning:
            HStack(spacing: DKSpacing.md) {
                ProgressView()
                Text("Memindai…").foregroundColor(.secondary)
                Spacer()
                Text(String(
                    format: NSLocalizedString("%d file · %@", comment: ""),
                    model.hits.count,
                    ByteFormat.string(from: model.scannedBytes)
                ))
                .font(.dkData(12))
                .foregroundStyle(.secondary)
                Button("Batalkan") { model.cancelScan() }
            }

        case .results, .cleaned:
            HStack(spacing: DKSpacing.md) {
                Button {
                    model.startScan()
                } label: {
                    Label("Pindai Ulang", systemImage: "arrow.clockwise")
                }
                Picker(NSLocalizedString("Urut", comment: ""), selection: $sort) {
                    ForEach(Sort.allCases) { s in Text(s.label).tag(s) }
                }
                .fixedSize()
                Spacer()
                Text(String(
                    format: NSLocalizedString("%@ terpilih", comment: ""),
                    ByteFormat.string(from: model.selectedBytes)
                ))
                .font(.dkData(13))
                .foregroundStyle(.secondary)
                Button("Bersihkan yang dipilih") { requestClean() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty)
            }
        }
    }

    // MARK: List hasil (virtualized)

    private var resultList: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack(spacing: DKSpacing.md) {
                Text(String(
                    format: NSLocalizedString("%d file · %@", comment: ""),
                    visibleHits.count == model.hits.count
                        ? model.hits.count
                        : visibleHits.count,
                    ByteFormat.string(from: model.scannedBytes)
                ))
                .font(.title3.weight(.semibold))
                Spacer()
                // Pencarian hasil — list bisa ratusan baris (pola PureMac).
                HStack(spacing: DKSpacing.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(
                        NSLocalizedString("Cari nama atau folder…", comment: ""),
                        text: $search
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(NSLocalizedString("Klik dua kali untuk pratinjau. Klik kanan untuk menampilkan di Finder.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            List(visibleHits) { hit in
                HStack {
                    ReadoutRow(
                        value: ByteFormat.string(from: hit.sizeBytes),
                        label: hit.url.lastPathComponent,
                        detail: hit.url.deletingLastPathComponent().path,
                        badge: hit.isSelectedByDefault ? nil : NSLocalizedString("Baru", comment: "")
                    )
                    Spacer(minLength: DKSpacing.sm)
                    Toggle("", isOn: Binding(
                        get: { model.selected.contains(hit.id) },
                        set: { model.toggle(hit.id, isOn: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    QuickLookCoordinator.shared.show(hit.url)
                }
                .contextMenu {
                    Button {
                        QuickLookCoordinator.shared.show(hit.url)
                    } label: {
                        Label(NSLocalizedString("Pratinjau", comment: ""), systemImage: "eye")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([hit.url])
                    } label: {
                        Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "magnifyingglass")
                    }
                    Divider()
                    Button {
                        excludeHit(hit)
                    } label: {
                        Label(NSLocalizedString("Selalu kecualikan folder ini", comment: ""), systemImage: "hand.slash")
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 240, maxHeight: .infinity)
        }
    }

    /// Whitelist permanen + keluar dari hasil sekarang (model shared —
    /// nyerahin row juga biar nggak kebawa scan yang lagi jalan).
    private func excludeHit(_ hit: FileHit) {
        var whitelist = UserWhitelist.load()
        whitelist.add(hit.url.deletingLastPathComponent().path)
        whitelist.save()
        LargeFilesModel.shared.remove(hit.id)
    }

    /// Daftar yang lolos filter pencarian (nama file atau folder).
    private var visibleHits: [FileHit] {
        let sorted = sortedHits
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func cleanBanner(_ bytes: Int64) -> some View {
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

        if !model.failedItems.isEmpty {
            DisclosureGroup(
                isExpanded: $showFailedItems,
                content: {
                    ForEach(Array(model.failedItems.enumerated()), id: \.offset) { _, failed in
                        HStack(alignment: .top) {
                            Text(failed.url.lastPathComponent).font(.caption.weight(.medium))
                            Spacer()
                            Text(failed.reason).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                },
                label: {
                    Text(String(
                        format: NSLocalizedString("%d item gagal dibersihkan — lihat alasannya", comment: ""),
                        model.failedItems.count
                    ))
                    .font(.caption)
                    .foregroundColor(DKColor.attention)
                }
            )
        }
    }

    private func requestClean() {
        if UserDefaults.standard.bool(forKey: Self.dryRunKey) {
            model.performClean(dryRunKey: Self.dryRunKey)
        } else {
            showDryRunPreview = true
        }
    }
}
