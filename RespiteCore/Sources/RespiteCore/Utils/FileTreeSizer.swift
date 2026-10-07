import Foundation

/// Ukuran total satu path (file = ukurannya, folder = jumlah seluruh isi).
/// Dipakai AppCatalog & LeftoverScanner; SmartScanner punya versi streaming
/// sendiri (nggak nyimpen tree, beda kebutuhan).
public enum FileTreeSizer {
    public static func size(of url: URL) -> Int64 {
        sizeAndLatestModified(of: url).sizeBytes
    }

    /// Ukuran total + tanggal modifikasi TERBARU dari isi (bukan mtime folder
    /// sendiri — folder baru dibikin bisa "keliatan baru" padahal isinya lama).
    static func sizeAndLatestModified(of url: URL) -> (sizeBytes: Int64, lastModified: Date) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (0, .distantPast)
        }
        guard isDirectory.boolValue else {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (
                Int64(values?.fileSize ?? 0),
                values?.contentModificationDate ?? .distantPast
            )
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else { return (0, .distantPast) }

        var total: Int64 = 0
        var latest = Date.distantPast
        while let item = enumerator.nextObject() {
            guard
                let fileURL = item as? URL,
                let values = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
                ),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
            if let date = values.contentModificationDate, date > latest {
                latest = date
            }
        }
        return (total, latest)
    }
}
