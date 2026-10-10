import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Shredder (PRD §4.1 benchmark, P2): hapus permanen buat file yang user
/// emang TIDAK mau bisa dipulihkan (dokumen sensitif). Tidak pernah jadi
/// jalur default — semua modul lain tetap ke Trash. Konfirmasi berlapis
/// (ketik "hapus") via PermanentDeleteConfirmSheet.
struct ShredderView: View {
    @State private var items: [TrashEntry] = []
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var resultFailed = false
    @State private var failedItems: [CleanExecutor.FailedItem] = []

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            if let resultMessage {
                ToolDoneCard(
                    title: resultMessage,
                    message: resultFailed
                        ? nil
                        : NSLocalizedString("File sudah dihapus selamanya dan tidak ada di Trash.", comment: ""),
                    failed: failedItems,
                    showOpenTrash: false
                )
            }

            ToolStartCard(
                headline: NSLocalizedString("Hapus file rahasia selamanya", comment: ""),
                points: [
                    NSLocalizedString("File langsung dihapus — tidak lewat Trash.", comment: ""),
                    NSLocalizedString("Tidak bisa dibatalkan atau dikembalikan.", comment: ""),
                    NSLocalizedString("Untuk pembersihan biasa, pakai alat lain — semuanya lewat Trash dan aman.", comment: ""),
                ],
                buttonTitle: NSLocalizedString("Pilih file…", comment: ""),
                buttonSymbol: "plus",
                action: pickItems
            )

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: DKSpacing.sm) {
                    Text(String(
                        format: NSLocalizedString("%d item · %@", comment: ""),
                        items.count,
                        ByteFormat.string(from: totalBytes)
                    ))
                    .font(.headline)
                    .monospacedDigit()
                    Text(NSLocalizedString("Hapus centang untuk mengeluarkan file dari daftar.", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ToolCard {
                        ForEach(items) { item in
                            ToolResultRow(
                                title: item.url.lastPathComponent,
                                subtitle: item.url.deletingLastPathComponent().path,
                                size: item.sizeBytes,
                                isOn: inListBinding(for: item)
                            )
                        }
                    }
                }
            }

            ToolActionBar(
                selectedCount: items.count,
                selectedBytes: totalBytes,
                buttonTitle: NSLocalizedString("Hapus Permanen", comment: ""),
                note: NSLocalizedString("Tidak bisa dibatalkan", comment: ""),
                isIrreversible: true
            ) {
                showConfirm = true
            }

            ToolDetails {
                Text(NSLocalizedString("Shredder melewati Trash sepenuhnya — file langsung dihapus permanen dan tidak bisa di-Put Back. Di SSD/APFS isi lama tidak ditimpa: FileVault dan snapshot lokal Time Machine yang menentukan apakah sisanya masih bisa dipulihkan. Gunakan hanya untuk dokumen yang benar-benar sensitif; selain itu, biarkan pembersihan biasa lewat Trash yang bisa dibatalkan.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showConfirm) {
            PermanentDeleteConfirmSheet(
                itemCount: items.count,
                totalBytes: totalBytes,
                onConfirm: {
                    performDelete()
                    showConfirm = false
                },
                onCancel: { showConfirm = false }
            )
        }
    }

    /// Centang = masih di daftar. Hapus centang = keluarkan dari daftar
    /// (sama seperti tombol "Keluarkan" sebelumnya — tidak menghapus apa pun).
    private func inListBinding(for item: TrashEntry) -> Binding<Bool> {
        Binding(
            get: { true },
            set: { isOn in
                if !isOn { items.removeAll { $0.id == item.id } }
            }
        )
    }

    private func pickItems() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = NSLocalizedString("Pilih file atau folder yang ingin dihapus permanen — tidak bisa dibatalkan.", comment: "")
        panel.begin { response in
            guard response == .OK else { return }
            let existing = Set(items.map(\.url.path))
            for url in panel.urls where !existing.contains(url.path) {
                let size = FileTreeSizer.size(of: url)
                items.append(TrashEntry(
                    url: url,
                    sizeBytes: size,
                    lastModified: Date()
                ))
            }
        }
    }

    private func performDelete() {
        let outcome = CleanExecutor.permanentlyDelete(items, module: "Shredder")
        let deletedURLs = Set(outcome.cleaned.map(\.url))
        items.removeAll { deletedURLs.contains($0.url) }
        resultFailed = !outcome.failed.isEmpty
        failedItems = outcome.failed
        resultMessage = String(
            format: NSLocalizedString("%@ dihapus permanen", comment: ""),
            ByteFormat.string(from: outcome.freedBytes)
        )
    }
}
