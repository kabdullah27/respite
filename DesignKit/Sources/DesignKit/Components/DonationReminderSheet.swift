import SwiftUI
import AppKit

/// Nudge donasi ala-WinRAR — reusable buat semua app donationware.
/// State "udah tampil sesi ini" sengaja disimpen di caller (in-memory, bukan disk)
/// biar tiap app bisa atur sendiri kapan reset-nya, sesuai spek per-app.
public struct DonationReminderSheet: View {
    let appName: String
    let donationURL: URL
    let onDismiss: () -> Void

    public init(appName: String, donationURL: URL, onDismiss: @escaping () -> Void) {
        self.appName = appName; self.donationURL = donationURL; self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: DKSpacing.lg) {
            Text("Terima kasih telah menggunakan \(appName)").font(.headline)
            Text("\(appName) sepenuhnya gratis tanpa fitur terkunci. Pengembangannya didukung oleh donasi jika kamu merasa terbantu.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            HStack {
                Button("Lain kali", action: onDismiss)
                Button("Dukung") { NSWorkspace.shared.open(donationURL); onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DKSpacing.xl)
        .frame(width: 320)
    }
}
