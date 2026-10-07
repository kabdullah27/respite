import Foundation

/// Satu lampiran email yang sudah terunduh lokal.
public struct MailAttachment: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Lampiran >90 hari default tercentang; yang lebih baru tidak (guard).
    public let isSelectedByDefault: Bool

    public init(url: URL, sizeBytes: Int64, lastModified: Date, isSelectedByDefault: Bool) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public struct MailAttachmentsOutcome: Sendable, Equatable {
    public let trashed: [MailAttachment]
    public let failedNames: [String]

    public init(trashed: [MailAttachment], failedNames: [String]) {
        self.trashed = trashed
        self.failedNames = failedNames
    }
}

/// Mail Attachments Cleanup (benchmark P1, PRD §4.1).
///
/// PENGECUALIAN TER-SCOPED dari Protected List (~/Library/Mail dilindungi
/// dari AUTO-scan): modul ini user-initiated, hanya menyentuh file di bawah
/// folder `Attachments/`, hanya memindah ke Trash, dan lampiran <90 hari
/// tidak tercentang default. File asli tetap di server mail.
public enum MailAttachments {
    /// True kalau path punya komponen folder "Attachments" — satu-satunya
    /// wilayah yang boleh disentuh modul ini di dalam ~/Library/Mail.
    public static func isAttachmentPath(_ url: URL) -> Bool {
        url.pathComponents.contains("Attachments")
    }

    /// Butuh Full Disk Access untuk membaca ~/Library/Mail.
    public static func isReadable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let mail = home.appendingPathComponent("Library/Mail")
        guard FileManager.default.fileExists(atPath: mail.path) else { return false }
        return FileManager.default.isReadableFile(atPath: mail.path)
    }

    public static func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        minBytes: Int64 = 1_000_000,
        olderThanDays: Int = 90
    ) -> [MailAttachment] {
        let mailRoot = home.appendingPathComponent("Library/Mail")
        guard let enumerator = FileManager.default.enumerator(
            at: mailRoot,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        var results: [MailAttachment] = []

        while let item = enumerator.nextObject() {
            if Task.isCancelled { break }
            guard let url = item as? URL, isAttachmentPath(url) else { continue }
            guard
                let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                ),
                values.isRegularFile == true,
                let size = values.fileSize,
                Int64(size) >= minBytes
            else { continue }

            let modified = values.contentModificationDate ?? .distantPast
            results.append(MailAttachment(
                url: url,
                sizeBytes: Int64(size),
                lastModified: modified,
                isSelectedByDefault: modified < cutoff
            ))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Pindah ke Trash (bukan hapus) — melewati guard ProtectedList milik
    /// CleanExecutor secara SENGAJA lewat jalur khusus ini, karena guard
    /// isAttachmentPath + inisiatif user + usia 90 hari adalah pembatasnya.
    public static func moveToTrash(
        _ items: [MailAttachment],
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> MailAttachmentsOutcome {
        var trashed: [MailAttachment] = []
        var failed: [String] = []

        for item in items {
            guard isAttachmentPath(item.url) else { continue }
            SafetyLedger.record(
                LedgerEntry(
                    actionType: "move-to-trash",
                    target: item.url.path,
                    reversible: true,
                    detail: "Mail Attachments: \(item.url.lastPathComponent) · \(ByteFormat.string(from: item.sizeBytes))"
                ),
                to: ledgerURL
            )
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                trashed.append(item)
            } catch {
                failed.append(item.url.lastPathComponent)
            }
        }
        return MailAttachmentsOutcome(trashed: trashed, failedNames: failed)
    }
}
