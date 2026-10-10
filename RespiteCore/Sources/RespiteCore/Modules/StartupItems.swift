import Foundation

/// Referensi app terinstall ringan (tanpa sizing — buat matching owner).
public struct AppRef: Sendable, Equatable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Satu item startup (LaunchAgent/LaunchDaemon).
public struct StartupItem: Identifiable, Sendable, Equatable {
    public enum Source: String, Sendable, CaseIterable {
        case userLaunchAgent
        case systemLaunchAgent
        case systemLaunchDaemon
    }

    public let id: UUID
    /// Path file .plist-nya.
    public let url: URL
    /// Key `Label` — biasanya reverse-DNS (com.vendor.app).
    public let label: String
    /// Nama binary yang dijalankan (jika ada).
    public let programPath: String?
    public let source: Source
    /// App terinstall yang cocok — nil kalau tidak ketahuan asalnya.
    public let owner: AppRef?

    public init(url: URL, label: String, programPath: String?, source: Source, owner: AppRef?) {
        self.id = UUID()
        self.url = url
        self.label = label
        self.programPath = programPath
        self.source = source
        self.owner = owner
    }
}

public enum StartupItems {
    /// Enumerasi plist launchd dari 3 lokasi standar (TRD §4.8) + cocokkan
    /// owner-nya ke app terinstall. SMAppService (login items modern) tampil
    /// di System Settings — dianter lewat tombol deep-link di UI.
    public static func scan(
        userAgentsDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents"),
        systemAgentsDir: URL = URL(fileURLWithPath: "/Library/LaunchAgents"),
        systemDaemonsDir: URL = URL(fileURLWithPath: "/Library/LaunchDaemons"),
        apps: [AppRef] = AppCatalog.quickCatalog()
    ) -> [StartupItem] {
        var items: [StartupItem] = []
        items += loadItems(from: userAgentsDir, source: .userLaunchAgent, apps: apps)
        items += loadItems(from: systemAgentsDir, source: .systemLaunchAgent, apps: apps)
        items += loadItems(from: systemDaemonsDir, source: .systemLaunchDaemon, apps: apps)
        return items
    }

    static func loadItems(from dir: URL, source: StartupItem.Source, apps: [AppRef]) -> [StartupItem] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "plist" }
            .compactMap { plistURL in
                guard let dict = NSDictionary(contentsOf: plistURL),
                      let label = dict["Label"] as? String, !label.isEmpty
                else { return nil }
                let program: String?
                if let raw = dict["Program"] as? String {
                    program = raw
                } else if let args = dict["ProgramArguments"] as? [String], let first = args.first {
                    program = first
                } else {
                    program = nil
                }
                return StartupItem(
                    url: plistURL,
                    label: label,
                    programPath: program,
                    source: source,
                    owner: owner(of: label, program: program, apps: apps)
                )
            }
            .sorted { $0.label < $1.label }
    }

    /// Cocokkan app pemilik — pure, diuji unit test:
    /// 1. Label persis bundle ID, 2. Label = bundleID + suffix,
    /// 3. Path program nongol di dalam /Applications/<Nama>.app/.
    static func owner(of label: String, program: String?, apps: [AppRef]) -> AppRef? {
        if let exact = apps.first(where: { $0.bundleID == label }) {
            return exact
        }
        // Prefix paling spesifik: "com.foo.bar.helper" milik com.foo.bar, bukan com.foo.
        if let prefixed = apps
            .filter({ label.hasPrefix($0.bundleID + ".") })
            .max(by: { $0.bundleID.count < $1.bundleID.count }) {
            return prefixed
        }
        if let program {
            if let byPath = apps.first(where: { program.contains("/\($0.name).app/") }) {
                return byPath
            }
        }
        return nil
    }
}

extension AppCatalog {
    /// Katalog ringan: bundle ID + nama saja, tanpa deep-size — buat matching.
    public static func quickCatalog(searchPaths: [URL]? = nil) -> [AppRef] {
        // App bawaan (/System/Applications) juga pemilik — Notes, Photos, dst.
        let paths = searchPaths ?? (defaultPaths + [URL(fileURLWithPath: "/System/Applications")])
        var refs: [AppRef] = []

        // Turun sampai 2 level: "/Applications/Adobe Photoshop 2024/…app",
        // "/Applications/Utilities/…app", Setapp, JetBrains Toolbox.
        func collect(in directory: URL, depth: Int) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for child in children {
                if child.pathExtension == "app" {
                    guard let dict = NSDictionary(contentsOf: child.appendingPathComponent("Contents/Info.plist")),
                          let bundleID = dict["CFBundleIdentifier"] as? String
                    else { continue }
                    let rawName = (dict["CFBundleName"] as? String) ?? ""
                    let name = rawName.isEmpty
                        ? child.deletingPathExtension().lastPathComponent
                        : rawName
                    refs.append(AppRef(bundleID: bundleID, name: name))
                } else if depth > 0,
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    collect(in: child, depth: depth - 1)
                }
            }
        }
        for root in paths { collect(in: root, depth: 2) }
        return refs
    }
}

// MARK: - Pengaturan startup (user-level, tanpa privilege)

extension StartupItem {
    /// Agent dikelola Respite (dibuat lewat tombol Tambah).
    public var isManagedByRespite: Bool { label.hasPrefix(StartupManager.managedPrefix) }
}

public enum StartupManager {
    public static let managedPrefix = "app.respite.startup."
    public static let disabledKey = "Disabled"

    static var userAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    /// Jalankan launchctl — injectable biar unit test hermetic (jangan
    /// sentuh DB launchd beneran). Default: /bin/launchctl beneran.
    static var launchctlRunner: ([String]) -> (code: Int32, output: String?) = { args in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, nil)
        }
        // Baca SEBELUM waitUntilExit — output > buffer pipe (~64 KB) bikin
        // launchctl blok nulis sementara kita blok nunggu dia exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8))
    }

    /// Toggle agent milik USER.
    ///
    /// Pelajaran penting (bug 2026-09-21): launchd modern menyimpan status
    /// disabled di DB sendiri (`/var/db/com.apple.xpc.launchd/disabled.*`)
    /// dan MENG-OVERRIDE key `Disabled` di plist untuk agent yang sudah
    /// load. Nulis plist doang = toggle nggak ngaruh. Jadi:
    /// 1. `launchctl disable/enable gui/<uid>/<label>` — status persisten
    ///    (inilah yang dibaca launchd saat login).
    /// 2. `launchctl bootout/bootstrap` — terapkan KE SESI BERJALAN.
    /// 3. Plist tetap ditulis — kompatibilitas launchd lama + keterbacaan
    ///    alat lain (dan unit test).
    public static func setAgentEnabled(plistURL: URL, enabled: Bool) throws {
        guard let dict = NSMutableDictionary(contentsOf: plistURL),
              let label = dict["Label"] as? String, !label.isEmpty
        else {
            throw CocoaError(.fileReadUnknown)
        }
        let domain = "gui/\(getuid())"
        _ = launchctlRunner([enabled ? "enable" : "disable", domain, label])
        invalidateDisabledCache()

        if enabled {
            dict.removeObject(forKey: disabledKey)
        } else {
            dict[disabledKey] = true
        }
        if !dict.write(to: plistURL, atomically: true) {
            throw CocoaError(.fileWriteUnknown)
        }

        // Sesi berjalan: bootout gagal wajar kalau memang belum ke-load;
        // bootstrap gagal wajar kalau sudah ke-load. Dua-duanya diabaikan.
        if enabled {
            _ = launchctlRunner(["bootstrap", domain, plistURL.path])
        } else {
            _ = launchctlRunner(["bootout", domain + "/" + label])
        }
    }

    /// Daftarkan app agar jalan saat login — LaunchAgent dikelola Respite
    /// (`open -a <app>` dengan RunAtLoad). Idempotent: yang sudah ada dilewati.
    @discardableResult
    /// `agentsDir` di-inject buat unit test — JANGAN pernah menulis ke
    /// LaunchAgents asli dari test (pelajaran: tes lama meninggalkan
    /// app.respite.startup.toolbagus.plist di folder asli user).
    public static func addLoginApp(
        appPath: String,
        slug: String? = nil,
        agentsDir: URL? = nil
    ) throws -> URL {
        let dir = agentsDir ?? userAgentsDir
        let appName = ((appPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        let sanitized = slug ?? appName
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let plistURL = dir
            .appendingPathComponent("\(managedPrefix)\(sanitized).plist")

        let dict: [String: Any] = [
            "Label": "\(managedPrefix)\(sanitized)",
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
        ]
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: plistURL.path) {
            return plistURL // sudah terdaftar — idempotent
        }
        if !(dict as NSDictionary).write(to: plistURL, atomically: true) {
            throw CocoaError(.fileWriteUnknown)
        }
        return plistURL
    }

    /// Hapus agent dikelola Respite — menolak plist di luar prefix kita.
    public static func removeManagedAgent(plistURL: URL) throws {
        guard let dict = NSDictionary(contentsOf: plistURL),
              let label = dict["Label"] as? String,
              label.hasPrefix(managedPrefix)
        else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Bukan agent yang dikelola Respite",
            ])
        }
        try FileManager.default.removeItem(at: plistURL)
    }

    // MARK: Auto-start Respite sendiri

    /// Plist auto-start Respite (dipakai toggle "Jalankan saat login").
    public static var respiteAutoStartPlistURL: URL {
        userAgentsDir.appendingPathComponent("\(managedPrefix)respite.plist")
    }

    public static func isRespiteAutoStartEnabled() -> Bool {
        let url = respiteAutoStartPlistURL
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return isEnabled(plistURL: url)
    }

    /// Toggle auto-start Respite. `appPath` di-inject biar bisa ditest;
    /// default = bundle aplikasi yang jalan.
    public static func setRespiteAutoStart(
        _ enabled: Bool,
        appPath: String = Bundle.main.bundleURL.path,
        agentsDir: URL? = nil
    ) throws {
        let url: URL
        if let agentsDir {
            url = agentsDir.appendingPathComponent("\(managedPrefix)respite.plist")
        } else {
            url = respiteAutoStartPlistURL
        }
        if enabled {
            if !FileManager.default.fileExists(atPath: url.path) {
                // Slug tetap — nama bundle ("Respite Beta.app") nggak boleh
                // menggeser nama plist yang dicek isRespiteAutoStartEnabled.
                _ = try addLoginApp(appPath: appPath, slug: "respite", agentsDir: agentsDir)
            } else {
                try setAgentEnabled(plistURL: url, enabled: true)
            }
        } else if FileManager.default.fileExists(atPath: url.path) {
            try setAgentEnabled(plistURL: url, enabled: false)
        }
    }

    /// Status enabled: gabungan DB launchd (authoritative) + key plist.
    /// Disabled kalau SALAH SATU bilang disabled.
    public static func isEnabled(plistURL: URL) -> Bool {
        guard let dict = NSDictionary(contentsOf: plistURL),
              let label = dict["Label"] as? String
        else { return true }
        if (dict[disabledKey] as? Bool) == true { return false }
        if launchctlDisabled(label) { return false }
        return true
    }

    /// Cache `launchctl print-disabled` — SATU panggilan buat semua baris.
    /// Tanpa ini, view memanggil isEnabled per baris per render = spawn
    /// proses launchctl terus-menerus di main thread → UI macet (bug
    /// "disuruh reopen" 2026-09-23). TTL pendek; di-invalidate tiap tulis.
    private static var disabledCache: (at: Date, labels: Set<String>)?
    private static let cacheLock = NSLock()
    private static let disabledCacheTTL: TimeInterval = 5

    static func invalidateDisabledCache() {
        cacheLock.lock(); defer { cacheLock.unlock() }
        disabledCache = nil
    }

    static func disabledLabels() -> Set<String> {
        cacheLock.lock()
        if let cache = disabledCache, Date().timeIntervalSince(cache.at) < disabledCacheTTL {
            cacheLock.unlock()
            return cache.labels
        }
        cacheLock.unlock()

        guard let output = launchctlRunner(["print-disabled", "gui/\(getuid())"]).output else {
            return []
        }
        // Format baris: `"com.vendor.agent" => disabled`.
        // CATATAN: split(separator:) default membuang komponen kosong, jadi
        // label ada di komponen PERTAMA (kutip pembuka menghasilkan komponen
        // kosong yang dibuang) — bug klasik yang sempat bikin parse kosong.
        var labels = Set<String>()
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasSuffix("=> disabled") else { continue }
            let parts = line.split(separator: "\"")
            guard let label = parts.first, !label.isEmpty else { continue }
            labels.insert(String(label))
        }
        cacheLock.lock()
        disabledCache = (Date(), labels)
        cacheLock.unlock()
        return labels
    }

    /// Label tertentu disabled menurut DB launchd (via cache).
    static func launchctlDisabled(_ label: String) -> Bool {
        disabledLabels().contains(label)
    }
}
