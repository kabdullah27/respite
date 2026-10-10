import SwiftUI
import RespiteCore
import DesignKit

/// Bersihkan Cepat: cari cache & log lama → centang → Trash.
/// Pola halaman mengikuti ToolPage (mulai → mencari → hasil → selesai).
/// State di `SmartScanModel.shared` — pindah alat tidak menghentikan scan.
struct SmartScanView: View {
    /// Filter kategori di atas daftar hasil (nil = semua).
    private enum Filter: Hashable {
        case all
        case category(ScanCategory)
    }

    @ObservedObject private var model = SmartScanModel.shared
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var showConfirm = false

    private var selectedResults: [ScanResult] {
        model.results.filter { model.selected.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedResults.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalBytes: Int64 {
        model.results.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            switch model.phase {
            case .idle:
                startCard
            case .scanning:
                ToolProgressCard(
                    detail: String(
                        format: NSLocalizedString("%d item ditemukan · %@", comment: ""),
                        model.results.count,
                        ByteFormat.string(from: totalBytes)
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
                if !model.results.isEmpty { results }
            }

            details
        }
        .alert(
            ToolConfirm.title(count: selectedResults.count, bytes: selectedBytes),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: SmartScanModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(ToolConfirm.message)
        }
    }

    // MARK: 1. Mulai

    private var startCard: some View {
        ToolStartCard(
            headline: NSLocalizedString("Buang file sementara yang menumpuk", comment: ""),
            points: [
                NSLocalizedString("Memeriksa cache dan catatan lama dari aplikasi.", comment: ""),
                NSLocalizedString("Dokumen, foto, dan file pribadimu tidak disentuh.", comment: ""),
                NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
            ],
            action: { model.startScan() }
        )
    }

    // MARK: 3. Hasil

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            ToolEmptyResult(
                message: NSLocalizedString("Cache dan catatan lama di Mac kamu sudah bersih.", comment: ""),
                onRescan: { model.startScan() }
            )
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d item · %@", comment: ""),
                    model.results.count,
                    ByteFormat.string(from: totalBytes)
                ),
                subtitle: NSLocalizedString("Yang dicentang aman dihapus. Aplikasi akan membuatnya lagi saat dibutuhkan.", comment: ""),
                onRescan: { model.startScan() }
            ) {
                HStack(spacing: DKSpacing.md) {
                    Picker("", selection: $filter) {
                        Text(NSLocalizedString("Semua", comment: "")).tag(Filter.all)
                        ForEach(presentCategories, id: \.rawValue) { category in
                            Text(categoryName(category)).tag(Filter.category(category))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField(NSLocalizedString("Cari nama aplikasi…", comment: ""), text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Spacer()
                }
            }

            List {
                ForEach(visibleCategories, id: \.rawValue) { category in
                    Section {
                        ForEach(visibleResults(in: category)) { result in
                            ToolResultRow(
                                title: result.ownerName,
                                subtitle: reason(result.category),
                                size: result.sizeBytes,
                                badge: badge(for: result),
                                isOn: Binding(
                                    get: { model.selected.contains(result.id) },
                                    set: { isChecked in
                                        if isChecked {
                                            model.selected.insert(result.id)
                                        } else {
                                            model.selected.remove(result.id)
                                        }
                                    }
                                )
                            )
                            .accessibilityLabel(result.ownerName)
                            .contextMenu { rowMenu(result) }
                        }
                    } header: {
                        Text(categoryName(category))
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 360)

            ToolActionBar(
                selectedCount: selectedResults.count,
                selectedBytes: selectedBytes,
                action: requestClean
            )
        }
    }

    @ViewBuilder
    private func rowMenu(_ result: ScanResult) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([result.url])
        } label: {
            Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
        }
        Divider()
        Button {
            excludeResult(result)
        } label: {
            Label(NSLocalizedString("Jangan tampilkan folder ini lagi", comment: ""), systemImage: "hand.raised")
        }
    }

    private var details: some View {
        ToolDetails {
            Text(NSLocalizedString("Cache adalah file sementara yang dibuat aplikasi supaya lebih cepat. Kalau dihapus, aplikasi membuatnya lagi.", comment: ""))
            Text(NSLocalizedString("Catatan lama (log) hanya berguna untuk melacak masalah yang sudah lewat.", comment: ""))
            Text(NSLocalizedString("Isi Trash hanya ditampilkan. Untuk mengosongkannya, pakai alat Trash.", comment: ""))
        }
    }

    // MARK: Data

    private var presentCategories: [ScanCategory] {
        ScanCategory.allCases.filter { category in
            model.results.contains { $0.category == category }
        }
    }

    private var visibleCategories: [ScanCategory] {
        let candidates: [ScanCategory]
        if case .category(let category) = filter, presentCategories.contains(category) {
            candidates = [category]
        } else {
            candidates = presentCategories
        }
        return candidates.filter { !visibleResults(in: $0).isEmpty }
    }

    private func visibleResults(in category: ScanCategory) -> [ScanResult] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.results
            .filter { $0.category == category }
            .filter { query.isEmpty || $0.ownerName.localizedCaseInsensitiveContains(query) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func badge(for result: ScanResult) -> String? {
        if result.category == .trash || result.isSelectedByDefault { return nil }
        return NSLocalizedString("Baru dipakai", comment: "")
    }

    // MARK: Aksi

    /// Klik kanan → whitelist permanen + keluar dari hasil sekarang.
    private func excludeResult(_ result: ScanResult) {
        var whitelist = UserWhitelist.load()
        whitelist.add(result.url.path)
        whitelist.save()
        model.exclude(result)
    }

    /// Pertama kali → konfirmasi dulu; setelah disetujui, langsung.
    private func requestClean() {
        if !model.requestClean() {
            showConfirm = true
        }
    }

    // MARK: Teks kategori

    private func categoryName(_ category: ScanCategory) -> String {
        switch category {
        case .userCaches: return NSLocalizedString("Cache aplikasi", comment: "")
        case .userLogs: return NSLocalizedString("Catatan lama", comment: "")
        case .trash: return NSLocalizedString("Isi Trash", comment: "")
        }
    }

    private func reason(_ category: ScanCategory) -> String {
        switch category {
        case .userCaches:
            return NSLocalizedString("Dibuat ulang otomatis oleh aplikasinya.", comment: "")
        case .userLogs:
            return NSLocalizedString("Tidak dibutuhkan untuk pemakaian sehari-hari.", comment: "")
        case .trash:
            return NSLocalizedString("Sudah di Trash — kosongkan lewat alat Trash.", comment: "")
        }
    }
}
