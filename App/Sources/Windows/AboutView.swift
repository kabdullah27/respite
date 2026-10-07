import SwiftUI
import RespiteCore
import DesignKit

/// Jendela About — kecil, tenang, jujur: icon, nama, versi, satu tagline,
/// dan janji privasi. Tanpa marketing block.
struct AboutView: View {
    var body: some View {
        VStack(spacing: DKSpacing.lg) {
            appIcon
                .frame(width: 128, height: 128)

            VStack(spacing: DKSpacing.xs) {
                Text("Respite")
                    .font(.system(size: 22, weight: .bold))
                Text(String(
                    format: NSLocalizedString("Versi %@ (build %@)", comment: ""),
                    Self.shortVersion,
                    Self.buildVersion
                ))
                .font(.callout)
                .foregroundColor(.secondary)
            }

            Text(NSLocalizedString("Pembersih Mac yang tenang — lokal & privat.", comment: ""))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Text(NSLocalizedString("Semua proses berjalan di Mac kamu. Tanpa telemetri, tanpa langganan, tanpa fitur terkunci.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: DKSpacing.sm) {
                Button(NSLocalizedString("Dukung Respite", comment: "")) {
                    NSWorkspace.shared.open(DonationConfig.donationURL)
                }
            }
            .controlSize(.regular)
        }
        .padding(DKSpacing.xl)
        .frame(width: 380, height: 420)
    }

    /// Ikon app dari bundle (AppIcon.icns); fallback ke simbol gauge kalau
    /// resource-nya nggak ketemu.
    @ViewBuilder
    private var appIcon: some View {
        if let image = NSImage(named: "AppIcon") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 72))
                .foregroundStyle(Color.respite)
        }
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
