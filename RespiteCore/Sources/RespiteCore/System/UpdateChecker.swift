import Foundation

/// Hasil satu pemeriksaan pembaruan.
public struct UpdateInfo: Sendable, Equatable {
    public let currentVersion: String
    public let latestVersion: String
    /// Halaman rilis (dibuka di browser — download & install bukan urusan v1).
    public let releasePageURL: URL?
    public let publishedAt: Date?

    public init(
        currentVersion: String,
        latestVersion: String,
        releasePageURL: URL?,
        publishedAt: Date?
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releasePageURL = releasePageURL
        self.publishedAt = publishedAt
    }

    public var isUpdateAvailable: Bool {
        UpdateChecker.isVersion(latestVersion, newerThan: currentVersion)
    }
}

/// Pemeriksa pembaruan — SATU-SATUNYA fitur yang menyentuh jaringan
/// (keputusan desain menyusul PureMac), dan tetap PRIVASI-DULU:
/// - HANYA jalan saat user klik "Periksa Pembaruan" (tidak ada polling
///   background, tidak ada telemetri versi).
/// - Feed-nya GitHub Releases API — bisa diganti lewat UserDefaults.
/// - V1 hanya MEMBERITAHU + membuka halaman unduhan di browser.
///   Auto-update (Sparkle + appcast) menunggu signing/notarization.
public enum UpdateChecker {
    public static let feedURLKey = "app.respite.update.feedURL"

    /// Default: repo publik Respite (pengganti kalau repo-nya pindah).
    public static let defaultFeedURLString =
        "https://api.github.com/repos/kabdullah27/respite/releases/latest"

    public static func feedURL(defaults: UserDefaults = .standard) -> URL? {
        let raw = defaults.string(forKey: feedURLKey) ?? defaultFeedURLString
        return URL(string: raw)
    }

    /// Injector buat unit test — jangan ada network beneran di test.
    public static var dataProvider: (URL) async throws -> Data = { url in
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    public enum CheckError: LocalizedError, Equatable {
        case badFeed
        case badPayload

        public var errorDescription: String? {
            switch self {
            case .badFeed: return "Feed URL tidak valid"
            case .badPayload: return "Respons feed tidak bisa dibaca"
            }
        }
    }

    /// Cek pembaruan sekarang. Versi pembanding dibaca dari Info.plist
    /// (CFBundleShortVersionString).
    public static func check(
        feedURL: URL? = nil,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        defaults: UserDefaults = .standard
    ) async throws -> UpdateInfo {
        guard let feed = feedURL ?? Self.feedURL(defaults: defaults) else {
            throw CheckError.badFeed
        }
        let data = try await dataProvider(feed)

        struct ReleasePayload: Decodable {
            let tagName: String
            let htmlURL: String?
            let publishedAt: Date?

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case htmlURL = "html_url"
                case publishedAt = "published_at"
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(ReleasePayload.self, from: data),
              !payload.tagName.isEmpty
        else {
            throw CheckError.badPayload
        }
        return UpdateInfo(
            currentVersion: normalize(currentVersion),
            latestVersion: normalize(payload.tagName),
            releasePageURL: payload.htmlURL.flatMap(URL.init(string:)),
            publishedAt: payload.publishedAt
        )
    }

    /// Buang prefix "v"/"V" dan whitespace.
    public static func normalize(_ version: String) -> String {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }

    /// Bandingkan dua versi secara numerik per komponen ("1.10.0" > "1.9.2",
    /// "1.0" < "1.0.1"). Komponen non-numerik diabaikan (dianggap 0).
    /// Pure & teruji — jangan sentuh tanpa update test.
    /// Pre-release ("1.2.0-beta.2") < rilis final dengan inti sama.
    public static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let (lCore, lPre) = split(lhs)
        let (rCore, rPre) = split(rhs)
        let count = max(lCore.count, rCore.count)
        for i in 0..<count {
            let a = i < lCore.count ? lCore[i] : 0
            let b = i < rCore.count ? rCore[i] : 0
            if a != b { return a > b }
        }
        switch (lPre, rPre) {
        case (nil, nil): return false
        case (nil, _?): return true          // final > pre-release
        case (_?, nil): return false
        case let (l?, r?):
            return l.compare(r, options: .numeric) == .orderedDescending
        }
    }

    /// Inti numerik + suffix pre-release (tanpa build metadata "+...").
    /// Dulu "1.2.0-beta.2" dibaca [1,2,0,2] — lebih baru dari 1.2.0.
    private static func split(_ version: String) -> ([Int], String?) {
        let withoutBuild = normalize(version).split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""
        let parts = withoutBuild.split(separator: "-", maxSplits: 1).map(String.init)
        let core = (parts.first ?? "")
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        return (core, parts.count > 1 ? parts[1] : nil)
    }
}
