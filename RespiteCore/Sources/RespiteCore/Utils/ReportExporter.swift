import Foundation

/// Ekspor riwayat aksi (Safety Ledger) ke JSON/CSV — TRD §4.16.
public enum ReportExporter {
    public static func jsonData(from entries: [LedgerEntry]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(entries)
    }

    /// CSV dengan escaping standar (kutip ganda di dalam kutip).
    public static func csv(from entries: [LedgerEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        func escape(_ raw: String) -> String {
            "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        var lines = ["timestamp,action,target,reversible,detail"]
        for entry in entries {
            lines.append([
                formatter.string(from: entry.timestamp),
                escape(entry.actionType),
                escape(entry.target),
                entry.reversible ? "yes" : "no",
                escape(entry.detail),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
