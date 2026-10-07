import XCTest
@testable import RespiteCore

final class StartupItemsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-startup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makePlist(
        _ dir: String, _ fileName: String, label: String, program: String?
    ) throws {
        let dirURL = root.appendingPathComponent(dir)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        var dict: [String: Any] = ["Label": label]
        if let program {
            dict["Program"] = program
        }
        (dict as NSDictionary).write(
            to: dirURL.appendingPathComponent(fileName),
            atomically: true
        )
    }

    private let apps = [
        AppRef(bundleID: "com.google.Chrome", name: "Google Chrome"),
        AppRef(bundleID: "com.vendor.toolbagus", name: "ToolBagus"),
    ]

    func testMatchingOwnerTigaJalur() {
        // 1) Label = bundle ID persis.
        XCTAssertEqual(
            StartupItems.owner(of: "com.google.Chrome", program: nil, apps: apps)?.name,
            "Google Chrome"
        )
        // 2) Label = bundleID + suffix (helper).
        XCTAssertEqual(
            StartupItems.owner(of: "com.google.Chrome.helper.1234", program: nil, apps: apps)?.name,
            "Google Chrome"
        )
        // 3) Lewat path program di dalam .app bundle.
        XCTAssertEqual(
            StartupItems.owner(
                of: "net.anonym.launcher",
                program: "/Applications/ToolBagus.app/Contents/MacOS/helper",
                apps: apps
            )?.name,
            "ToolBagus"
        )
        // Tidak ketahuan.
        XCTAssertNil(StartupItems.owner(of: "com.unknown.what", program: "/usr/libexec/thing", apps: apps))
    }

    func testScanTigaLokasiDenganOwner() throws {
        try makePlist("user/LaunchAgents", "com.google.Chrome.plist",
                      label: "com.google.Chrome", program: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        try makePlist("system/Agents", "net.anonym.launcher.plist",
                      label: "net.anonym.launcher", program: "/usr/libexec/thingd")
        try makePlist("system/Daemons", "com.vendor.toolbagus.daemon.plist",
                      label: "com.vendor.toolbagus.daemon", program: nil)

        let items = StartupItems.scan(
            userAgentsDir: root.appendingPathComponent("user/LaunchAgents"),
            systemAgentsDir: root.appendingPathComponent("system/Agents"),
            systemDaemonsDir: root.appendingPathComponent("system/Daemons"),
            apps: apps
        )

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.source == .userLaunchAgent }.count, 1)
        XCTAssertEqual(items.filter { $0.source == .systemLaunchDaemon }.count, 1)

        let chrome = items.first { $0.label == "com.google.Chrome" }
        XCTAssertEqual(chrome?.owner?.name, "Google Chrome")
        let daemon = items.first { $0.source == .systemLaunchDaemon }
        XCTAssertEqual(daemon?.owner?.name, "ToolBagus", "label ber-prefix bundle ID harus match")
        let anon = items.first { $0.label == "net.anonym.launcher" }
        XCTAssertNil(anon?.owner, "tidak diketahui — jujur, bukan dikira-kira")
    }
}

final class StartupManagerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-startupmgr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        StartupManager.launchctlRunner = { _ in (0, "") } // pulihkan
        StartupManager.invalidateDisabledCache()
    }

    /// launchctl beneran JANGAN disentuh dari test — stub murni.
    private func stubLaunchctl() {
        StartupManager.launchctlRunner = { _ in (0, "") }
        StartupManager.invalidateDisabledCache()
    }

    func testToggleDisabledKey() throws {
        stubLaunchctl()
        let plist = dir.appendingPathComponent("com.vendor.x.plist")
        try (["Label": "com.vendor.x"] as NSDictionary).write(to: plist)

        XCTAssertTrue(StartupManager.isEnabled(plistURL: plist))
        try StartupManager.setAgentEnabled(plistURL: plist, enabled: false)
        XCTAssertFalse(StartupManager.isEnabled(plistURL: plist))
        try StartupManager.setAgentEnabled(plistURL: plist, enabled: true)
        XCTAssertTrue(StartupManager.isEnabled(plistURL: plist))
    }

    /// DB launchd (print-disabled) bilang disabled → disabled, walau key
    /// plist-nya nggak ada — ini kasus nyata yang bikin toggle lama bocor.
    func testLaunchctlDBDisabledMenang() throws {
        stubLaunchctl()
        let plist = dir.appendingPathComponent("com.vendor.y.plist")
        try (["Label": "com.vendor.y"] as NSDictionary).write(to: plist)
        StartupManager.launchctlRunner = { args in
            if args.first == "print-disabled" {
                return (0, "\"com.vendor.y\" => disabled\n")
            }
            return (0, "")
        }
        StartupManager.invalidateDisabledCache()
        XCTAssertFalse(StartupManager.isEnabled(plistURL: plist))
    }

    func testTambahLoginAppIdempotent() throws {
        stubLaunchctl()
        let url1 = try StartupManager.addLoginApp(appPath: "/Applications/ToolBagus.app", agentsDir: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path))
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url1))
        XCTAssertEqual(dict["Label"] as? String, "app.respite.startup.toolbagus")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/usr/bin/open", "-a", "/Applications/ToolBagus.app"])
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)

        // Kedua kali → dilewati (idempotent), tetap satu file.
        let url2 = try StartupManager.addLoginApp(appPath: "/Applications/ToolBagus.app", agentsDir: dir)
        XCTAssertEqual(url1, url2)
    }

    func testHapusHanyaAgentSendiri() throws {
        let ours = try StartupManager.addLoginApp(appPath: "/Applications/ToolBagus.app", agentsDir: dir)
        let foreign = dir.appendingPathComponent("com.vendor.y.plist")
        try (["Label": "com.vendor.y"] as NSDictionary).write(to: foreign)

        try StartupManager.removeManagedAgent(plistURL: ours)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ours.path))

        XCTAssertThrowsError(try StartupManager.removeManagedAgent(plistURL: foreign),
                             "plist asing wajib ditolak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }
}
