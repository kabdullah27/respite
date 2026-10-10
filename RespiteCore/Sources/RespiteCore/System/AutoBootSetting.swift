import Foundation
import Darwin

/// Setting firmware "nyala saat lid dibuka".
///
/// VARIABELNYA BERBEDA PER ARSITEKTUR (kunci bug 2026-10-06):
/// - Apple Silicon: `BootPreference` (AutoBoot diabaikan firmware — itulah
///   kenapa tulis AutoBoot=%00 tidak pernah berefek di Mac modern).
///     %00 = matikan semua pemicu (lid, tombol, charger)
///     %01 = matikan pemicu lid saja · %02 = charger saja
/// - Intel: `AutoBoot` (%00 = matikan).
///
/// Baca TANPA privilege; mengubahnya lewat dialog admin sekali
/// (`with administrator privileges`). Persisten di firmware — reversibel.
public enum AutoBootSetting {
    public enum State: Equatable, Sendable {
        case enabledDefault
        case enabled
        case disabled
        case unknown
    }

    public static let nvramPath = "/usr/sbin/nvram"
    /// Timeout pengaman — spinner UI tidak boleh muter selamanya
    /// (laporan 2026-10-04).
    public static let setTimeout: TimeInterval = 90

    static var isAppleSilicon: Bool {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var value = 0
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }

    static var nvramKey: String {
        isAppleSilicon ? "BootPreference" : "AutoBoot"
    }

    // MARK: Read

    /// Nilai mentah variabel NVRAM (nil = variabel tidak ada / gagal baca).
    /// `launched == false` = nvram gagal dijalankan (status tak diketahui),
    /// beda dengan variabel yang memang tidak ada (perilaku pabrik).
    static func rawValue(_ key: String) -> (launched: Bool, value: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: nvramPath)
        process.arguments = [key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, nil)
        }
        let data = try? pipe.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data,
              let output = String(data: data, encoding: .utf8)
        else { return (true, nil) }
        // Format: "Key\tvalue"
        let parts = output.split(separator: "\t", maxSplits: 1)
        return (true, parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil)
    }

    /// Baca status sekarang — tanpa admin.
    public static func read() -> State {
        let key = nvramKey
        let (launched, value) = rawValue(key)
        guard launched else { return .unknown }
        guard let value else {
            // Variabel tidak ada → perilaku pabrik (aktif). Kecuali di AS,
            // sisa AutoBoot=%00 dari percobaan lama tidak dianggap.
            return .enabledDefault
        }
        return parse(value)
    }

    /// Parse nilai variabel → state. Pure — diuji unit test.
    static func parse(_ value: String) -> State {
        switch value {
        // Dari sudut pandang fitur "nyala saat lid dibuka":
        // %01 (lid dimatikan) = disabled; %02 (cuma charger) = lid tetap aktif.
        case "%00", "%01": return .disabled
        case "%02", "%03": return .enabled
        case "": return .enabledDefault
        default: return .unknown
        }
    }

    // MARK: Set

    /// Ubah setting — memunculkan dialog admin macOS sekali per perubahan.
    public static func set(_ enabled: Bool) throws {
        let shell: String
        if enabled {
            shell = "nvram -d \(nvramKey) 2>/dev/null; true"
        } else {
            shell = "nvram \(nvramKey)=%00"
        }
        let script = "do shell script \"\(shell)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // Drain pipe di background — tanpa ini, output yang menumpuk bisa
        // memblokir proses (deadlock klasik Pipe + waitUntilExit).
        outPipe.fileHandleForReading.readabilityHandler = { $0.readDataToEndOfFile() }
        errPipe.fileHandleForReading.readabilityHandler = { $0.readDataToEndOfFile() }

        try process.run()

        // Tunggu dengan deadline — jangan waitUntilExit tanpa batas.
        let deadline = Date().addingTimeInterval(setTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            throw CocoaError(
                .userCancelled,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "Proses melebihi batas waktu — kemungkinan dialog admin tidak terjawab. Coba lagi dan pastikan dialog password terlihat.", comment: ""
                )]
            )
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw CocoaError(
                .userCancelled,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "Perubahan dibatalkan atau ditolak — setting tidak diubah.", comment: ""
                )]
            )
        }
    }
}
