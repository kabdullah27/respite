import Foundation

/// Config statis (TRD §4.18) — link donasi gampang diubah tanpa nyentuh logic.
enum DonationConfig {
    static let appName = "Respite"
    static let donationURL = URL(string: "https://ko-fi.com/kabdullah")!
}
