import Foundation

/// Heuristik status Full Disk Access (PRD §8) — tanpa FDA, folder yang
/// dilindungi TCC (mis. ~/Library/Safari) tidak bisa dibaca.
public enum FullDiskAccess {
    /// `true` = hampir pasti sudah diaktifkan, `false` = ditolak TCC,
    /// `nil` = tidak bisa dinilai (folder probe tidak ada).
    ///
    /// Probe-nya harus open() sungguhan: `isReadableFile` cuma ngecek
    /// permission POSIX via stat, dan pemilik folder tetap user kita —
    /// jadi lolos padahal TCC bakal nolak pas baca beneran.
    public static func likelyGranted() -> Bool? {
        let fm = FileManager.default
        let safari = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
        guard fm.fileExists(atPath: safari.path) else { return nil }

        // Listing dir saja sudah kena gate TCC tanpa FDA.
        guard let entries = try? fm.contentsOfDirectory(atPath: safari.path) else {
            return false
        }
        // Kalau ada file, coba baca beneran — beberapa versi macOS
        // membiarkan listing tapi tetap memblokir isi file.
        if let probeName = entries.first(where: { !$0.hasPrefix(".") }) {
            let probe = safari.appendingPathComponent(probeName)
            guard let handle = FileHandle(forReadingAtPath: probe.path) else { return false }
            try? handle.close()
        }
        return true
    }
}
