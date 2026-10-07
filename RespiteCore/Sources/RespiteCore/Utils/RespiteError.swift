import Foundation

/// Error terpusat — tiap kasus punya pesan yang bisa langsung ditampilin
/// ke user (TRD §7), bukan raw NSError.
public enum RespiteError: LocalizedError {
    case protectedPath(String)
    case diskSpaceInsufficient
    case moduleUnavailable(String)
    case scanCancelled

    public var errorDescription: String? {
        switch self {
        case .protectedPath(let path):
            return "'\(path)' ada di protected list dan nggak bisa disentuh oleh Respite."
        case .diskSpaceInsufficient:
            return "Ruang disk nggak cukup buat operasi ini. Bebasin space dulu, lalu coba lagi."
        case .moduleUnavailable(let reason):
            return "Modul ini lagi nggak bisa dipakai: \(reason)"
        case .scanCancelled:
            return "Scan dibatalkan."
        }
    }
}
