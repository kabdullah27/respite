import Foundation

/// Satu snapshot lokal APFS milik Time Machine.
public struct TMSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    /// "2024-01-15-101010" — tanggal+jam snapshot dibuat.
    public let timestamp: String

    public init(id: String, timestamp: String) {
        self.id = id
        self.timestamp = timestamp
    }
}

public enum TimeMachineSnapshots {
    /// `tmutil listlocalsnapshots /` — shell-out read-only satu kali
    /// (dipanggil saat modul dibuka, bukan polling).
    public static func list() -> [TMSnapshot] {
        parse(runListLocalsnapshots() ?? "")
    }

    static func runListLocalsnapshots() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    /// Pure — diuji unit test. Baris: `com.apple.TimeMachine.2024-01-15-101010.local`.
    public static func parse(_ output: String) -> [TMSnapshot] {
        output
            .split(separator: "\n")
            .compactMap { line -> TMSnapshot? in
                let raw = String(line).trimmingCharacters(in: .whitespaces)
                guard raw.hasPrefix("com.apple.TimeMachine.") else { return nil }
                let middle = raw
                    .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                    .replacingOccurrences(of: ".local", with: "")
                guard !middle.isEmpty else { return nil }
                return TMSnapshot(id: raw, timestamp: middle)
            }
    }
}
