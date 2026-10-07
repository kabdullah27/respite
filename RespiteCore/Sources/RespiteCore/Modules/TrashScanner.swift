import Foundation

/// Satu item di Trash milik user.
public struct TrashEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let sizeBytes: Int64
    /// Perkiraan waktu dibuang (mtime — macOS nyimpen info asal "Put Back"
    /// secara proprietary di .DS_Store, nggak bisa dibaca legal).
    public let lastModified: Date

    public init(url: URL, sizeBytes: Int64, lastModified: Date) {
        self.id = UUID()
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

public enum TrashScanner {
    /// Enumerasi item top-level ~/.Trash, ukuran penuh, sorted terbesar dulu.
    /// `home` injectable buat unit test.
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [TrashEntry] {
        let trash = home.appendingPathComponent(".Trash")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        return children
            .map { child in
                let measured = FileTreeSizer.sizeAndLatestModified(of: child)
                return TrashEntry(
                    url: child,
                    sizeBytes: measured.sizeBytes,
                    lastModified: measured.lastModified
                )
            }
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
