import Foundation

/// Satu node peta disk (anak langsung dari folder yang sedang dilihat).
public struct DiskMapItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let isDirectory: Bool

    public init(url: URL, name: String, sizeBytes: Int64, isDirectory: Bool) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
    }
}

public enum DiskMapScanner {
    /// Ukur anak-anak LANGSUNG dari satu folder (per level — dipanggil
    /// ulang tiap drill down, bukan satu pass rekursif full disk).
    /// Item 0 byte tetap dimasukkan biar peta jujur (folder kosong keliatan).
    public static func children(of root: URL) -> [DiskMapItem] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        return children
            .compactMap { child -> DiskMapItem? in
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                let size = isDirectory
                    ? FileTreeSizer.size(of: child)
                    : Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                return DiskMapItem(
                    url: child,
                    name: child.lastPathComponent,
                    sizeBytes: size,
                    isDirectory: isDirectory
                )
            }
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

/// Algoritma squarified treemap (Bruls dkk.) — pure function, tanpa
/// dependency, sesuai TRD §4.14 ("gampang di-implement sendiri & ringan").
public enum Squarify {
    /// Peta proporsi (0...1 bebas, di-normalisasi) ke CGRect berdasarkan
    /// urutan input. Return rect sejajar index input.
    public static func layout(sizes: [Double], in rect: CGRect) -> [CGRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0, !sizes.isEmpty else {
            return [CGRect](repeating: .zero, count: sizes.count)
        }

        let sorted = sizes.enumerated()
            .map { (fraction: $0.element / total, index: $0.offset) }
            .sorted { $0.fraction > $1.fraction }

        var rects = [CGRect](repeating: .zero, count: sizes.count)
        var x = rect.minX
        var y = rect.minY
        var w = rect.width
        var h = rect.height
        var row: [(fraction: Double, index: Int)] = []

        func worstRatio(_ entries: [(fraction: Double, index: Int)], _ side: Double) -> Double {
            let sum = entries.map(\.fraction).reduce(0, +)
            guard sum > 0, side > 0 else { return .infinity }
            var worst = 0.0
            for entry in entries {
                let ratio = max(
                    side * side * entry.fraction / (sum * sum),
                    sum * sum / (side * side * entry.fraction)
                )
                worst = max(worst, ratio)
            }
            return worst
        }

        func flushRow() {
            let sum = row.map(\.fraction).reduce(0, +)
            guard !row.isEmpty, sum > 0, w > 0, h > 0 else {
                row = []
                return
            }
            if w >= h {
                // Baris jadi kolom vertikal di sisi kiri.
                let thickness = w * sum
                var cursor = y
                for entry in row {
                    let height = h * (entry.fraction / sum)
                    rects[entry.index] = CGRect(x: x, y: cursor, width: thickness, height: height)
                    cursor += height
                }
                x += thickness
                w -= thickness
            } else {
                // Baris jadi strip horizontal di atas.
                let thickness = h * sum
                var cursor = x
                for entry in row {
                    let width = w * (entry.fraction / sum)
                    rects[entry.index] = CGRect(x: cursor, y: y, width: width, height: thickness)
                    cursor += width
                }
                y += thickness
                h -= thickness
            }
            row = []
        }

        for entry in sorted {
            let side = min(w, h)
            if row.isEmpty {
                row.append(entry)
            } else if worstRatio(row + [entry], side) <= worstRatio(row, side) {
                row.append(entry)
            } else {
                flushRow()
                row = [entry]
            }
        }
        flushRow()
        return rects
    }
}
