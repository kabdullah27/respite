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
    /// Item 0 byte dibuang — nggak punya luas di treemap.
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

        // Kerja dalam satuan AREA (pt²), bukan fraksi — rasio aspek dan
        // ketebalan baris harus satu unit dengan sisi rect.
        let totalArea = Double(rect.width * rect.height)
        let sorted = sizes.enumerated()
            .map { (area: max(0, $0.element) / total * totalArea, index: $0.offset) }
            .sorted { $0.area > $1.area }

        var rects = [CGRect](repeating: .zero, count: sizes.count)
        var x = Double(rect.minX)
        var y = Double(rect.minY)
        var w = Double(rect.width)
        var h = Double(rect.height)
        var row: [(area: Double, index: Int)] = []

        func worstRatio(_ entries: [(area: Double, index: Int)], _ side: Double) -> Double {
            let sum = entries.reduce(0) { $0 + $1.area }
            guard sum > 0, side > 0 else { return .infinity }
            var worst = 0.0
            for entry in entries where entry.area > 0 {
                let ratio = max(
                    side * side * entry.area / (sum * sum),
                    sum * sum / (side * side * entry.area)
                )
                worst = max(worst, ratio)
            }
            return worst
        }

        func flushRow() {
            let sum = row.reduce(0) { $0 + $1.area }
            guard !row.isEmpty, sum > 0, w > 0, h > 0 else {
                row = []
                return
            }
            if w >= h {
                // Baris jadi kolom vertikal di sisi kiri.
                let thickness = min(w, sum / h)
                var cursor = y
                for entry in row {
                    let height = entry.area / thickness
                    rects[entry.index] = CGRect(x: x, y: cursor, width: thickness, height: height)
                    cursor += height
                }
                x += thickness
                w -= thickness
            } else {
                // Baris jadi strip horizontal di atas.
                let thickness = min(h, sum / w)
                var cursor = x
                for entry in row {
                    let width = entry.area / thickness
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
