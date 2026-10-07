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

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                HStack(spacing: DKSpacing.md) {
                    Button {
                        pickItems()
                    } label: {
                        Label(NSLocalizedString("Pilih file atau folder…", comment: ""), systemImage: "plus")
                    }
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%d item · %@", comment: ""),
                        items.count,
                        ByteFormat.string(from: totalBytes)
                    ))
                    .font(.dkData(12))
                    .foregroundStyle(.secondary)
                    Button {
                        showConfirm = true
                    } label: {
                        Label(
                            String(format: NSLocalizedString("Hapus permanen (%d)", comment: ""), items.count),
                            systemImage: "trash.slash"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DKColor.irreversible)
                    .disabled(items.isEmpty)
                }

                if let resultMessage {
                    Label(resultMessage, systemImage: resultFailed ? "exclamationmark.triangle" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundColor(resultFailed ? DKColor.attention : DKColor.accent)
                }

                if items.isEmpty {
                    EmptyStateView(
                        symbol: "trash.slash",
                        title: NSLocalizedString("Belum ada yang dipilih", comment: ""),
                        message: NSLocalizedString("Pilih file atau folder yang ingin dihapus permanen. Untuk pembersihan biasa, gunakan modul lain — semuanya lewat Trash dan bisa dibatalkan.", comment: "")
                    )
                } else {
                    VStack(spacing: DKSpacing.sm) {
                        ForEach(items) { item in
                            HStack {
                                ReadoutRow(
                                    value: ByteFormat.string(from: item.sizeBytes),
                                    label: item.url.lastPathComponent,
                                    detail: item.url.deletingLastPathComponent().path
                                )
                                .lineLimit(1)
                                Spacer(minLength: DKSpacing.sm)
                                Button {
                                    items.removeAll { $0.id == item.id }
                                } label: {
                                    Label(NSLocalizedString("Keluarkan", comment: ""), systemImage: "minus")
                                        .labelStyle(.iconOnly)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, DKSpacing.xs)
                        }
                    }
                    .padding(DKSpacing.md)
                    .background(DKColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }

                Text(NSLocalizedString("Shredder melewati Trash sepenuhnya — data ditimpa dan tidak bisa dipulihkan oleh utilitas pemulihan. Gunakan hanya untuk dokumen yang benar-benar sensitif; selain itu, biarkan pembersihan biasa lewat Trash yang bisa dibatalkan.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        resultMessage = String(
            format: NSLocalizedString("%@ dihapus permanen", comment: ""),
            ByteFormat.string(from: outcome.freedBytes)
        )
    }
}
