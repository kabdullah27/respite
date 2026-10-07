import Foundation
import SQLite3

/// Satu entri izin dari TCC.db.
public struct TCCEntry: Identifiable, Sendable, Equatable {
    public let service: String       // raw: kTCCServiceCamera
    public let client: String        // bundle ID pemohon
    public let allowed: Bool

    public var id: String { "\(service)|\(client)" }
}

public enum PrivacyAudit {
    public static var defaultDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    }

    /// Baca TCC.db READ-ONLY via SQLite C API (TRD §2). Schema TCC private —
    /// kalau berubah (atau tanpa Full Disk Access), return kosong dengan
    /// alasan, JANGAN crash (mitigasi risiko PRD §10).
    public static func list(dbURL: URL = PrivacyAudit.defaultDBURL) -> (entries: [TCCEntry], readable: Bool) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return ([], false)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT service, client, auth_value FROM access", -1, &statement, nil
        ) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return ([], false)
        }
        defer { sqlite3_finalize(statement) }

        var entries: [TCCEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let serviceC = sqlite3_column_text(statement, 0),
                let clientC = sqlite3_column_text(statement, 1)
            else { continue }
            let service = String(cString: serviceC)
            let client = String(cString: clientC)
            let authValue = Int(sqlite3_column_int64(statement, 2))
            // 0 = ditolak, 2 = diizinkan, 3 = dibatasi (mis. foto terpilih).
            entries.append(TCCEntry(service: service, client: client, allowed: authValue >= 2))
        }
        return (entries.sorted { $0.service < $1.service }, true)
    }

    /// Nama tampilan per service — unknown ditulis apa adanya (jujur).
    public static func serviceName(_ raw: String) -> String {
        switch raw {
        case "kTCCServiceCamera": return "Kamera"
        case "kTCCServiceMicrophone": return "Mikrofon"
        case "kTCCServiceScreenCapture": return "Rekam Layar"
        case "kTCCServiceSystemPolicyAllFiles": return "Akses Disk Penuh"
        case "kTCCServiceAccessibility": return "Aksesibilitas"
        case "kTCCServiceSystemPolicyDesktopFolder": return "Folder Desktop"
        case "kTCCServiceSystemPolicyDocumentsFolder": return "Folder Documents"
        case "kTCCServiceSystemPolicyDownloadsFolder": return "Folder Downloads"
        case "kTCCServiceListenEvent": return "Input Monitoring"
        case "kTCCServicePostEvent": return "Input Monitoring"
        case "kTCCServiceAppleEvents": return "Otomasi"
        default: return raw
        }
    }
}
