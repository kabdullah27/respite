import Foundation

/// Kategori hasil scan. Nama tampilan & alasan "kenapa aman dihapus" ada di
/// layer app (butuh localization).
public enum ScanCategory: String, CaseIterable, Codable, Sendable {
    case userCaches
    case userLogs
    case trash
}

/// Satu item rekomendasi hasil scan — level "owner" (folder app pemilik),
/// bukan per file, biar list-nya manusiawi dan hemat memory.
public struct ScanResult: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let category: ScanCategory
    /// Nama app "pemilik" (nama folder top-level di bawah root kategori).
    public let ownerName: String
    public let sizeBytes: Int64
    /// Modifikasi terbaru dari isi folder — dipakai Recency Guard.
    public let lastModified: Date
    /// False kalau kena Recency Guard (baru dimodifikasi < N hari) —
    /// nggak ke-check pas "select all", user masih bisa pilih manual.
    public let isSelectedByDefault: Bool

    public init(
        url: URL,
        category: ScanCategory,
        ownerName: String,
        sizeBytes: Int64,
        lastModified: Date,
        isSelectedByDefault: Bool
    ) {
        self.id = UUID()
        self.url = url
        self.category = category
        self.ownerName = ownerName
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        self.isSelectedByDefault = isSelectedByDefault
    }
}

/// Respitean satu sesi scan.
public struct ScanSummary: Sendable, Equatable {
    public let resultCount: Int
    public let totalBytes: Int64

    public init(resultCount: Int, totalBytes: Int64) {
        self.resultCount = resultCount
        self.totalBytes = totalBytes
    }
}

/// Event yang di-stream scanner ke UI (TRD §6). Per-item biar list tumbuh
/// live saat scan jalan — user nggak nunggu kategori (apalagi semua kategori)
/// kelar dulu.
public enum ScanEvent: Sendable {
    case categoryStarted(ScanCategory)
    case found(ScanResult)
    case categoryFinished(ScanCategory, count: Int, totalBytes: Int64)
    case finished(ScanSummary)
}

/// Kontrak semua modul scanning (TRD §6) — stream, bukan array gede sekali jalan.
public protocol ScannableModule {
    func scan() -> AsyncThrowingStream<ScanEvent, Error>
}
