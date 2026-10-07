import SwiftUI
import RespiteCore
import DesignKit

@main
struct RespiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            DashboardView(model: .shared)
                .onOpenURL { url in
                    // respite://action/<nama> dari Raycast/Alfred/browser.
                    // Aksinya hanya MEMBUKA modul terkait — tidak pernah
                    // auto-execute apa pun (guardrail tetap berlaje dari luar).
                    let module: Module?
                    switch DeepLink.action(from: url) {
                    case .runDiagnostic: module = .diagnostic
                    case .maintenanceSweep: module = .memoryMonitor
                    case .freeMemory: module = .memoryMonitor
                    case nil: module = nil
                    }
                    Self.openMainWindow(to: module)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(NSLocalizedString("Buka Respite", comment: "")) {
                    Self.openMainWindow()
                }
                .keyboardShortcut("n")
            }

            // Tentang Respite — window custom (icon + versi + janji privasi).
            CommandGroup(replacing: .appInfo) {
                Button(NSLocalizedString("Tentang Respite", comment: "")) {
                    Self.openAboutWindow()
                }
                // Cek pembaruan manual — buka Settings di tab Pembaruan.
                Button(NSLocalizedString("Periksa Pembaruan…", comment: "")) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut("u")
            }

            // ⌘1–⌘9: Beranda + modul Pembersihan, urutan sama dengan sidebar.
            CommandMenu(NSLocalizedString("Ke Modul", comment: "")) {
                ForEach(Array(Self.shortcutModules.enumerated()), id: \.element) { index, module in
                    Button(module.title) {
                        Self.openMainWindow(to: module)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        WindowGroup(id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 420)

        Settings {
            SettingsView()
        }
    }

    /// Modul yang dapat shortcut ⌘1–⌘9 — urutan sidebar: Beranda lalu
    /// section Pembersihan (8 modul) = pas 9.
    private static let shortcutModules: [Module] = [.home]
        + Module.allCases.filter { $0.section == .cleaning }

    /// About window: cari yang udah kebuka dulu biar nggak numpuk.
    /// Kalau opener SwiftUI belum kepasang (main window belum pernah jalan),
    /// fallback ke About panel default — lebih baik daripada diam.
    /// CATATAN: JANGAN NSApp.activate di sini — semua pemanggil (menu app,
    /// chip versi) cuma bisa diklik saat app SUDAH aktif; aktivasi paksa
    /// dari dalam proses malah nge-drop koneksi AX test runner (pelajaran
    /// UI test 2026-09-24) dan berkelahi sama fokus app lain.
    static func openAboutWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("about") == true }) {
            existing.makeKeyAndOrderFront(nil)
        } else if let open = AboutWindowOpener.open {
            open()
        } else {
            NSApp.sendAction(#selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
        }
    }

    /// Buka window utama dari mana aja (menu bar, Dock, ⌘N). Window yang
    /// "ditutup" sebenernya cuma disembunyikan (hide-on-close di AppDelegate),
    /// jadi jalur utamanya tinggal makeKeyAndOrderFront — nggak bergantung
    /// pada hack `newWindowForTab:` yang udah nggak reliable di macOS baru.
    static func openMainWindow(to module: Module? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        let candidates = NSApp.windows.filter {
            !$0.isKind(of: NSPanel.self) && $0.canBecomeMain
        }
        if let existing = candidates.first(where: { $0.title.contains("Respite") }) ?? candidates.first {
            existing.makeKeyAndOrderFront(nil)
        } else if let open = MainWindowOpener.open {
            open()
        } else {
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }

        if let module {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .respiteOpenModule, object: module)
            }
        }
    }
}

/// Jembatan AppKit → SwiftUI: action `openWindow` resmi ditangkap dari dalam
/// scene (DashboardView.onAppear) biar bisa dipanggil dari menu bar walaupun
/// window lagi nggak kebuka.
enum MainWindowOpener {
    static var open: (() -> Void)?
}

/// Sama kayak MainWindowOpener, tapi buat About window (scene-nya beda).
enum AboutWindowOpener {
    static var open: (() -> Void)?
}

extension Notification.Name {
    static let respiteOpenModule = Notification.Name("app.respite.openModule")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusBar: StatusBarController?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Riwayat era "Ringkas" dipindahin ke folder Respite — sekali saja.
        SafetyLedger.migrateLegacyHistory()

        statusBar = StatusBarController(model: .shared) { module in
            RespiteApp.openMainWindow(to: module)
        }

        // Pasang delegate ke window SwiftUI begitu jadi key — dipakai buat
        // hide-on-close.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let window = note.object as? NSWindow,
                  !(window is NSPanel),
                  window.canBecomeMain else { return }
            window.delegate = self
            self.didCreateMainWindow = true
            // JANGAN restorable: hide-on-close bikin state "closed" tersimpan,
            // dan launch tanpa event reopen (direct exec / test runner) lalu
            // TANPA WINDOW SAMA SEKALI (bug reproduksi stabil via XCUITest
            // 2026-09-24). Trade-off: frame window tidak diingat — murah
            // dibanding app yang "buka tapi kosong".
            window.isRestorable = false
        }

        ensureMainWindowVisible(attempt: 0)
    }

    /// Launch tanpa event reopen (direct exec, test runner) tidak membuat
    /// window sama sekali, dan `NSApp.activate` dari dalam proses begitu
    /// diabaikan macOS (anti focus-stealing). Yang terbukti memicu window:
    /// aktivasi lewat LaunchServices. Jadi: coba normal dulu ~2 dtk, lalu
    /// self-heal dengan `open` pada bundle sendiri (mengaktifkan instance
    /// yang SUDAH berjalan — PID sama, tidak spawn baru).
    private var didSelfHealOpen = false
    /// Window pernah tercipta → self-heal TIDAK PERNAH jalan lagi. Tanpa
    /// ini, loop 10-detik pertama bisa membuka ulang window yang user barusan
    /// tutup (bug: tutup window → terbuka sendiri; dan bikin pengukuran
    /// "hidden" tadi ternodai).
    private var didCreateMainWindow = false

    private func ensureMainWindowVisible(attempt: Int) {
        if didCreateMainWindow { return }
        let hasMainWindow = NSApp.windows.contains {
            !$0.isKind(of: NSPanel.self) && $0.canBecomeMain && $0.isVisible
        }
        if hasMainWindow { didCreateMainWindow = true; return }
        RespiteApp.openMainWindow()

        if attempt >= 4, !didSelfHealOpen {
            didSelfHealOpen = true
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [Bundle.main.bundleURL.path]
            try? process.run()
        }

        guard attempt < 20 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ensureMainWindowVisible(attempt: attempt + 1)
        }
    }

    /// Tutup (⌘W / tombol merah) = sembunyikan, bukan destroy.
    /// (Eksperimen 2026-09-21: destroy cuma hemat ~2,4 MB RSS vs hide —
    /// nggak sebanding dengan kehilangan state window. Penghematan nyata
    /// ada di teardown popover menu bar, lihat StatusBarController.)
    func windowShouldClose(_ window: NSWindow) -> Bool {
        if isTerminating { return true }
        window.orderOut(nil)
        return false
    }

    /// Klik icon Dock pas nggak ada window → tampilin lagi.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            RespiteApp.openMainWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }
}
