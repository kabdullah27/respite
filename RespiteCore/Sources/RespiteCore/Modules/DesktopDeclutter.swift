import Foundation

/// Satu item yang bisa diarsip dari Desktop.
public struct DeclutterItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    public let lastModified: Date
    /// Folder tujuan arsip (yyyy-MM dari tanggal modifikasi).
    public let targetFolder: String
    /// Recency Guard: screenshot <7 hari default tidak tercentang.
    public let isSelectedByDefault: Bool

    public init(url: URL, sizeBytes: Int64, lastModified: Date, targetFolder: String, isSelectedByDefault: Bool) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.targetFolder = targetFolder
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public struct DesktopDeclutterOutcome: Sendable, Equatable {
    public let moved: [DeclutterItem]
    public let failedURLs: [String]

    public init(moved: [DeclutterItem], failedURLs: [String]) {
        self.moved = moved
        self.failedURLs = failedURLs
    }
}

/// Desktop & Screenshot Declutter (TRD §4.17): scan TOP-LEVEL ~/Desktop
/// (tidak rekursif — subfolder yang diorganisir user tidak disentuh),
/// cocokkan nama screenshot default macOS, lalu ARSIP (pindah, bukan hapus)
/// ke ~/Desktop Archive/yyyy-MM/ — moveItem antar-folder sama volume = instan.
///
/// Catatan desain: Desktop ada di Protected List buat AUTO-scan; modul ini
/// eksplisit atas permintaan user, hanya memindahkan, dan tercatat di ledger.
public enum DesktopDeclutter {
    static let screenshotPattern = try! NSRegularExpression(
        pattern: #"^(Screen ?[Ss]hot) \d{4}-\d{2}-\d{2}"#
    )

    /// Nama folder arsip (yyyy-MM) dari tanggal modifikasi.
    static func archiveFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// Folder arsip dari TANGGAL DI NAMA FILE (kapan screenshot diambil) —
    /// lebih bermakna dari mtime yang bisa berubah gara-gara edit/salinan.
    /// Fallback ke mtime kalau nama tidak memuat tanggal valid.
    static func archiveFolderName(fromFileName name: String, modified: Date) -> String {
        // "Screenshot 2025-01-01 at ..." → ambil "2025-01-01".
        let parts = name.split(separator: " ")
        guard parts.count >= 2 else { return archiveFolderName(for: modified) }
        let datePart = String(parts[1])
        let subparts = datePart.split(separator: "-")
        guard subparts.count == 3,
              let year = Int(subparts[0]), (1900...2999).contains(year),
              let month = Int(subparts[1]), (1...12).contains(month)
        else { return archiveFolderName(for: modified) }
        return String(format: "%04d-%02d", year, month)
    }

    public static func isScreenshot(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return screenshotPattern.firstMatch(in: name, range: range) != nil
    }

    public static func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        recencyDays: Int = RecencyGuard.defaultDays
    ) -> [DeclutterItem] {
        let desktop = home.appendingPathComponent("Desktop")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: desktop,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        return children
            .compactMap { child -> DeclutterItem? in
                guard isScreenshot(child.lastPathComponent) else { return nil }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else {
                    return nil
                }
                let values = try? child.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                let modified = values?.contentModificationDate ?? .distantPast
                return DeclutterItem(
                    url: child,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    lastModified: modified,
                    targetFolder: archiveFolderName(
                        fromFileName: child.lastPathComponent,
                        modified: modified
                    ),
                    isSelectedByDefault: RecencyGuard.shouldSelectByDefault(
                        lastModified: modified,
                        days: recencyDays
                    )
                )
            }
            .sorted { $0.lastModified < $1.lastModified }
    }

    /// Pindahkan item terpilih ke ~/Desktop Archive/<yyyy-MM>/.
    /// Ledger dicatat sebelum tiap move (reversible: true).
    public static func archive(
        _ items: [DeclutterItem],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> DesktopDeclutterOutcome {
        let archiveRoot = home.appendingPathComponent("Desktop Archive")
        var moved: [DeclutterItem] = []
        var failed: [String] = []

        for item in items {
            let destination = archiveRoot
                .appendingPathComponent(item.targetFolder)
                .appendingPathComponent(item.url.lastPathComponent)

            SafetyLedger.record(
                LedgerEntry(
                    actionType: "archive",
                    target: item.url.path,
                    reversible: true,
                    detail: "Rapikan Desktop: \(item.targetFolder)/\(item.url.lastPathComponent)"
                ),
                to: ledgerURL
            )

            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: item.url, to: destination)
                moved.append(item)
            } catch {
                failed.append(item.url.lastPathComponent)
            }
        }
        return DesktopDeclutterOutcome(moved: moved, failedURLs: failed)
    }
}
