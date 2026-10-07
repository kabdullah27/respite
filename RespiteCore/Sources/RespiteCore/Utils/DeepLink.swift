import Foundation

/// Deep link `respite://action/<nama>` (TRD §4.13.2) — dipicu dari
/// Raycast/Alfred/browser. Aksinya dibatasi yang aman: semua hanya membuka
/// modul terkait, TIDAK ADA auto-execute (Maintenance Sweep tetap harus
/// dikonfirmasi user di dalam app — guardrail tetap berlaku dari luar).
public enum DeepLink {
    public enum Action: String, Equatable, Sendable {
        /// Buka Monitor Memori + daftar pemakai memori terbesar
        /// (aksi purge memori sungguhan menyusul bareng privileged helper).
        case freeMemory = "free-memory"
        case runDiagnostic = "run-diagnostic"
        case maintenanceSweep = "maintenance-sweep"
    }

    public static func action(from url: URL) -> Action? {
        guard url.scheme?.lowercased() == "respite" else { return nil }
        guard url.host?.lowercased() == "action" else { return nil }
        // pathComponents diawali "/" (non-empty!) — jangan pake predikat
        // isEmpty; split path langsung lebih aman.
        let segments = url.path.split(separator: "/").map(String.init)
        guard let name = segments.first else { return nil }
        return Action(rawValue: name)
    }
}
