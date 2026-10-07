import Foundation
import Darwin

/// Hentikan proses atas permintaan user (TRD §4.11/§4.20):
/// - Proses kritis (ProtectedList) TIDAK PERNAH bisa, ditolak sebelum apa pun.
/// - Default SIGTERM (graceful — aplikasi sempat cleanup & simpan state).
///   `force: true` → SIGKILL buat proses yang mengabaikan SIGTERM atau macet
///   (permintaan user 2026-09-21: "kenapa ga bisa di stop, apa karena ga
///   kill paksa" — ya, sebagian proses memang butuh paksa).
/// - Ledger dicatat SEBELUM eksekusi. Proses milik root gagal sendiri
///   (EPERM) tanpa privilege — itu jujur, bukan bug.
/// - Proses yang dijaga launchd (KeepAlive) BISA hidup lagi setelah
///   dibunuh — UI menyarankan matikan agent-nya lewat Aplikasi Saat Login.
public enum ProcessKiller {
    public struct Outcome: Sendable, Equatable {
        public let pid: Int32
        public let name: String
        public let succeeded: Bool
        /// Pesan teknis mentah (strerror / "protected-process") —
        /// UI yang localize & bingkai.
        public let rawReason: String
        /// true kalau sinyal terkirim — BUKAN jaminan prosesnya mati
        /// (launchd KeepAlive bisa membangkitkan ulang).
        public let signalDelivered: Bool
    }

    public static func terminate(
        pid: Int32,
        name: String,
        force: Bool = false,
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> Outcome {
        guard !ProtectedList.criticalProcesses.contains(name) else {
            return Outcome(
                pid: pid,
                name: name,
                succeeded: false,
                rawReason: "protected-process",
                signalDelivered: false
            )
        }

        let signal: Int32 = force ? SIGKILL : SIGTERM
        SafetyLedger.record(
            LedgerEntry(
                actionType: "kill-process",
                target: "\(name) (PID \(pid))",
                reversible: false,
                detail: (force ? "SIGKILL" : "SIGTERM") + " atas permintaan user"
            ),
            to: ledgerURL
        )

        let result = kill(pid, signal)
        if result == 0 {
            return Outcome(pid: pid, name: name, succeeded: true, rawReason: "", signalDelivered: true)
        }
        return Outcome(
            pid: pid,
            name: name,
            succeeded: false,
            rawReason: String(cString: strerror(errno)),
            signalDelivered: false
        )
    }
}
