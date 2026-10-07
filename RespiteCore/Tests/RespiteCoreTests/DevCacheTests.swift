import XCTest
@testable import RespiteCore

final class DevCacheTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-dev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func makeFile(_ relativePath: String, size: Int, daysAgo: Int) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
        let date = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testDerivedDataPerProjectDanArchives90Hari() async throws {
        try makeFile("Library/Developer/Xcode/DerivedData/ProjA-build/index", size: 300, daysAgo: 30)
        try makeFile("Library/Developer/Xcode/DerivedData/ProjB-build/index", size: 200, daysAgo: 1)
        // Arsip 40 hari lalu → masih "baru" buat Recency 90 hari (nggak ke-check).
        try makeFile("Library/Developer/Xcode/Archives/BuildLama.xcarchive/file", size: 500, daysAgo: 40)
        try makeFile("Library/Caches/CocoaPods/pods.db", size: 100, daysAgo: 60)

        let scanner = DevCacheScanner(roots: .standard(home: home))
        var targets: [DevCacheTarget] = []
        for try await event in scanner.scan() {
            if case .found(let target) = event { targets.append(target) }
        }

        XCTAssertEqual(targets.count, 4)

        let projA = targets.first { $0.title == "ProjA-build" }
        XCTAssertEqual(projA?.kind, .xcodeDerivedData)
        XCTAssertEqual(projA?.isSelectedByDefault, true, "30 hari > 7 hari → terpilih")

        let projB = targets.first { $0.title == "ProjB-build" }
        XCTAssertEqual(projB?.isSelectedByDefault, false, "baru disentuh 1 hari → Recency Guard")

        // Arsip 40 hari: di bawah ambang 90 hari → TIDAK terpilih default.
        let archive = targets.first { $0.kind == .xcodeArchives }
        XCTAssertEqual(archive?.isSelectedByDefault, false, "arsip <90 hari jangan auto-hapus")

        XCTAssertEqual(targets.first { $0.kind == .cocoapodsCache }?.title, "CocoaPods")
    }

    func testNodeModulesHanyaDiRootPilihanDanTidakNested() async throws {
        try makeFile("Projects/WebA/node_modules/pkg/index.js", size: 100, daysAgo: 60)
        // Nested node_modules di dalam node_modules → nggak boleh dobel.
        try makeFile("Projects/WebA/node_modules/foo/node_modules/bar/index.js", size: 50, daysAgo: 60)
        try makeFile("Projects/deep/a/b/WebB/node_modules/pkg/index.js", size: 80, daysAgo: 60)
        // Node_modules di LUAR root pilihan → nggak discan.
        try makeFile("Lain/node_modules/pkg/index.js", size: 999, daysAgo: 60)

        let scanner = DevCacheScanner(roots: .init(
            nodeModulesSearchRoots: [home.appendingPathComponent("Projects")]
        ))
        var targets: [DevCacheTarget] = []
        for try await event in scanner.scan() {
            if case .found(let target) = event { targets.append(target) }
        }

        let nodeTargets = targets.filter { $0.kind == .nodeModules }
        XCTAssertEqual(nodeTargets.count, 2, "WebA + WebB (nested & luar root dikecualikan)")
        XCTAssertFalse(nodeTargets.contains { $0.url.path.contains("/Lain/") })
    }

    func testDeteksiTool() {
        let tools = DevTools.detect(
            xcodePaths: [home.appendingPathComponent("Xcode.app")],
            brewPaths: [home.appendingPathComponent("bin/brew")],
            dockerPaths: [],
            nodePaths: [],
            composerPaths: [],
            goPaths: [],
            rustPaths: []
        )
        // Belum bikin filenya → semua false dulu.
        XCTAssertTrue(tools.allSatisfy { !$0.isInstalled })

        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: home.appendingPathComponent("bin/brew").path, contents: nil)
        let recheck = DevTools.detect(
            xcodePaths: [home.appendingPathComponent("Xcode.app")],
            brewPaths: [home.appendingPathComponent("bin/brew")],
            dockerPaths: [],
            nodePaths: [],
            composerPaths: [],
            goPaths: [],
            rustPaths: []
        )
        XCTAssertTrue(recheck.first { $0.kind == .homebrew }?.isInstalled ?? false)
        XCTAssertFalse(recheck.first { $0.kind == .docker }?.isInstalled ?? true)
    }
}

final class DerivedDataNameTests: XCTestCase {
    func testHashDibuang() {
        XCTAssertEqual(DevCacheScanner.prettyDerivedDataName("MyProject-abcdefghij"), "MyProject")
        XCTAssertEqual(DevCacheScanner.prettyDerivedDataName("Respite-9x8y7z6w5v4u"), "Respite")
    }

    func testNamaTanpaHashDibiarkan() {
        XCTAssertEqual(DevCacheScanner.prettyDerivedDataName("ProjA-build"), "ProjA-build")
        XCTAssertEqual(DevCacheScanner.prettyDerivedDataName("BiasaSaja"), "BiasaSaja")
    }
}

final class DevCacheEcosystemTests: XCTestCase {
    func testComposerGoRustCacheKetemu() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-eco-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        func file(_ path: String, _ size: Int) throws {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(count: size).write(to: url)
        }
        try file(".composer/cache/pack/a.tgz", 100)
        try file("Library/Caches/go-build/xx/x.o", 200)
        try file("go/pkg/mod/example.com/pkg@v1/a.go", 300)
        try file(".cargo/registry/cache/a.crate", 400)
        try file(".cargo/git/checkouts/dep/abc/file.rs", 500)

        let scanner = DevCacheScanner(roots: .standard(home: home))
        var kinds: Set<String> = []
        for try await event in scanner.scan() {
            if case .found(let target) = event { kinds.insert(target.kind.rawValue) }
        }
        XCTAssertTrue(kinds.contains("composerCache"))
        XCTAssertTrue(kinds.contains("goBuildCache"))
        XCTAssertTrue(kinds.contains("goModCache"))
        XCTAssertTrue(kinds.contains("cargoRegistry"))
        XCTAssertTrue(kinds.contains("cargoGitCache"))
    }

    func testDeteksiLewatFolderCacheSendiri() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-detect-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches/go-build"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let tools = DevTools.detect(
            xcodePaths: [], brewPaths: [], dockerPaths: [], nodePaths: [],
            composerPaths: [], goPaths: [home.appendingPathComponent("Library/Caches/go-build")],
            rustPaths: []
        )
        XCTAssertTrue(tools.first { $0.kind == .go }?.isInstalled ?? false)
        XCTAssertFalse(tools.first { $0.kind == .rust }?.isInstalled ?? true)
    }
}

final class DevCacheRecencyPolicyTests: XCTestCase {
    func testCacheMurniSelaluDirekomendasikanMeskiBaru() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("respite-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        // Homebrew cache disentuh BARU SEMANA INI (1 hari lalu).
        let brewPath = home.appendingPathComponent("Library/Caches/Homebrew/downloads/x.bottle")
        try FileManager.default.createDirectory(
            at: brewPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(count: 100).write(to: brewPath)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-86_400)],
            ofItemAtPath: brewPath.path
        )
        // Go module cache juga baru → TETAP dijaga (mahal di-redownload).
        let modPath = home.appendingPathComponent("go/pkg/mod/example.com/a@v1/x.go")
        try FileManager.default.createDirectory(
            at: modPath.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(count: 100).write(to: modPath)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-86_400)],
            ofItemAtPath: modPath.path
        )

        let scanner = DevCacheScanner(roots: .standard(home: home))
        var found: [DevCacheTarget] = []
        for try await event in scanner.scan() {
            if case .found(let target) = event { found.append(target) }
        }

        XCTAssertEqual(
            found.first { $0.kind == .homebrewCache }?.isSelectedByDefault, true,
            "cache murni selalu kecentang walau barusan dipakai"
        )
        XCTAssertEqual(
            found.first { $0.kind == .goModCache }?.isSelectedByDefault, false,
            "go mod cache yang masih hangat dijaga Recency Guard (mahal diunduh ulang)"
        )
    }
}
