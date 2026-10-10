import SwiftUI
import RespiteCore
import DesignKit

/// File Besar: cari file besar/lama di folder pribadi → centang → Trash.
/// Pola halaman mengikuti ToolPage (mulai → mencari → hasil → selesai).
/// State di `LargeFilesModel.shared` — pindah alat tidak menghentikan scan.
struct LargeFilesView: View {
    private static let dryRunKey = "app.respite.dryRunConfirmed.largeFiles"

    private enum Sort: String, CaseIterable, Identifiable {
        case largest
        case oldest

        var id: String { rawValue }

        var label: String {
            switch self {
            case .largest: return NSLocalizedString("Terbesar dulu", comment: "")
            case .oldest: return NSLocalizedString("Terlama dulu", comment: "")
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
    @State private var search = ""
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            switch model.phase {
            case .idle:
                startCard
            case .scanning:
                ToolProgressCard(
                    detail: String(
                        format: NSLocalizedString("%d file ditemukan · %@", comment: ""),
                        model.hits.count,
                        ByteFormat.string(from: model.scannedBytes)
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
                    failed: model.failedItems,
                    onRescan: { model.startScan() }
                )
                if !model.hits.isEmpty { results }
            }
        }
        .alert(
            ToolConfirm.title(count: model.selected.count, bytes: model.selectedBytes),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                model.performClean(dryRunKey: Self.dryRunKey)
            }
        } message: {
            Text(ToolConfirm.message)
        }
    }

    // MARK: 1. Mulai

    private var startCard: some View {
        ToolStartCard(
            headline: NSLocalizedString("Cari file besar yang jarang kamu buka", comment: ""),
            points: [
                NSLocalizedString("Dokumen, Desktop, Foto, dan Mail tidak ikut diperiksa.", comment: ""),
                String(
                    format: NSLocalizedString("File yang dipakai %d hari terakhir tidak dicentang otomatis.", comment: ""),
                    RecencyGuard.thresholdDays()
                ),
                NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
            ],
            action: { model.startScan() }
        ) {
            Picker(NSLocalizedString("Tampilkan file mulai dari", comment: ""), selection: $model.minBytes) {
                ForEach(thresholds, id: \.self) { bytes in
                    Text(ByteFormat.string(from: bytes)).tag(bytes)
                }
            }
            .fixedSize()
        }
    }

    // MARK: 3. Hasil

    @ViewBuilder
    private var results: some View {
        if model.hits.isEmpty {
            ToolEmptyResult(
                message: String(
                    format: NSLocalizedString("Tidak ada file di atas %@ di luar folder pribadimu.", comment: ""),
                    ByteFormat.string(from: model.minBytes)
                ),
                onRescan: { model.startScan() }
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d file besar · %@", comment: ""),
                    model.hits.count,
                    ByteFormat.string(from: model.scannedBytes)
                ),
                subtitle: NSLocalizedString("Centang file yang tidak kamu butuhkan lagi. Klik dua kali untuk melihat isinya.", comment: ""),
                onRescan: { model.startScan() }
            ) {
                HStack(spacing: DKSpacing.md) {
                    Picker("", selection: $sort) {
                        ForEach(Sort.allCases) { s in Text(s.label).tag(s) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(NSLocalizedString("Cari nama file…", comment: ""), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Spacer()
                }
            }

            List(visibleHits) { hit in
                ToolResultRow(
                    title: hit.url.lastPathComponent,
                    subtitle: String(
                        format: NSLocalizedString("%@ · terakhir diubah %@", comment: ""),
                        hit.url.deletingLastPathComponent().lastPathComponent,
                        FriendlyDate.string(hit.lastModified)
                    ),
                    size: hit.sizeBytes,
                    badge: hit.isSelectedByDefault ? nil : NSLocalizedString("Baru dipakai", comment: ""),
                    isOn: Binding(
                        get: { model.selected.contains(hit.id) },
                        set: { model.toggle(hit.id, isOn: $0) }
                    )
                )
                .onTapGesture(count: 2) {
                    QuickLookCoordinator.shared.show(hit.url)
                }
                .contextMenu { rowMenu(hit) }
            }
            .listStyle(.inset)
            .frame(height: 360)

            ToolActionBar(
                selectedCount: model.selected.count,
                selectedBytes: model.selectedBytes,
                action: requestClean
            )
        }
    }

    @ViewBuilder
    private func rowMenu(_ hit: FileHit) -> some View {
        Button {
            QuickLookCoordinator.shared.show(hit.url)
        } label: {
            Label(NSLocalizedString("Lihat isi", comment: ""), systemImage: "eye")
        }
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([hit.url])
        } label: {
            Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
        }
        Divider()
        Button {
            excludeHit(hit)
        } label: {
            Label(NSLocalizedString("Jangan tampilkan folder ini lagi", comment: ""), systemImage: "hand.raised")
        }
    }

    private var visibleHits: [FileHit] {
        let sorted: [FileHit]
        switch sort {
        case .largest: sorted = model.hits.sorted { $0.sizeBytes > $1.sizeBytes }
        case .oldest: sorted = model.hits.sorted { $0.lastModified < $1.lastModified }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.url.path.localizedCaseInsensitiveContains(query) }
    }

    /// Whitelist permanen + keluar dari hasil sekarang.
    private func excludeHit(_ hit: FileHit) {
        var whitelist = UserWhitelist.load()
        whitelist.add(hit.url.deletingLastPathComponent().path)
        whitelist.save()
        LargeFilesModel.shared.remove(hit.id)
    }

    private func requestClean() {
        if UserDefaults.standard.bool(forKey: Self.dryRunKey) {
            model.performClean(dryRunKey: Self.dryRunKey)
        } else {
            showConfirm = true
        }
    }
}
