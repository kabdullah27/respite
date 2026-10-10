import AppKit
import SwiftUI
import Combine
import RespiteCore
import DesignKit

/// Status item native (NSStatusItem) — pengganti MenuBarExtra karena SwiftUI
/// (macOS 13) nggak bisa bedain klik kiri vs klik kanan di icon menu bar.
/// Klik kiri → popover metrik; klik kanan → menu aksi cepat.
@MainActor
final class StatusBarController: NSObject {
    private let popover = NSPopover()
    private let statusItem: NSStatusItem
    private let model: SystemStatsModel
    private let onOpenApp: (Module?) -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(model: SystemStatsModel, onOpenApp: @escaping (Module?) -> Void) {
        self.model = model
        self.onOpenApp = onOpenApp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        // Konten SwiftUI dibuat LAZY saat pertama dibuka dan dilepas saat
        // ditutup (popoverDidClose) — footprint idle menu bar lebih rendah
        // (PRD G2); semua data live di SystemStatsModel bersama anyway.

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        updateButton()

        // objectWillChange memicu sebelum nilai ke-update — terima di tick
        // runloop berikutnya biar baca nilai terbaru.
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                RunLoop.main.perform { MainActor.assumeIsolated { self?.updateButton() } }
            }
            .store(in: &cancellables)
    }

    /// Label menu bar: angka Health Score. Band sehat TANPA tint — ikut warna
    /// native menu bar (putih di dark mode, hitam di light mode) biar nyatu
    /// sama item sistem lain. Amber/merah tetap, buat kondisi yang butuh
    /// perhatian (tetap kontras di kedua tema). Cuma disentuh kalau skornya
    /// BERUBAH — nulis ulang tiap tick bikin invalidasi render sia-sia.
    private var lastRenderedScore: Int?

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let score = model.healthScore
        guard score != lastRenderedScore else { return }
        lastRenderedScore = score
        button.title = "\(score)"
        switch HealthScore.Band.band(for: score) {
        case .neutral: button.contentTintColor = nil
        case .attention: button.contentTintColor = .systemOrange
        case .critical: button.contentTintColor = .systemRed
        }
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }
        if event.type == .rightMouseUp {
            // popUp langsung di posisi kursor — JANGAN utak-atik statusItem.menu
            // (pernah pasang menu lalu di-nil bikin tombol nyangkut mode menu
            // dan semua klik mati setelahnya).
            quickMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            if popover.contentViewController == nil {
                popover.contentViewController = NSHostingController(
                    rootView: MenuBarView(model: model, onOpenApp: onOpenApp)
                )
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func quickMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(
            title: NSLocalizedString("Buka Respite", comment: ""),
            action: #selector(openAppAction),
            keyEquivalent: "o"
        )
        open.target = self
        menu.addItem(open)

        let lockKb = NSMenuItem(
            title: NSLocalizedString("Kunci Keyboard", comment: ""),
            action: #selector(lockKeyboardAction),
            keyEquivalent: ""
        )
        lockKb.target = self
        menu.addItem(lockKb)

        let donate = NSMenuItem(
            title: NSLocalizedString("Dukung Pengembangan", comment: ""),
            action: #selector(donateAction),
            keyEquivalent: ""
        )
        donate.target = self
        menu.addItem(donate)

        let about = NSMenuItem(
            title: NSLocalizedString("Tentang Respite", comment: ""),
            action: #selector(aboutAction),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("Keluar dari Respite", comment: ""),
            action: #selector(quitAppAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func openAppAction() {
        onOpenApp(nil)
    }

    @objc private func donateAction() {
        NSWorkspace.shared.open(DonationConfig.donationURL)
    }

    @objc private func lockKeyboardAction() {
        KeyboardLockController.shared.lock(autoUnlockAfter: 120)
    }

    @objc private func aboutAction() {
        RespiteApp.openAboutWindow()
    }

    @objc private func quitAppAction() {
        NSApp.terminate(nil)
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Lepas view hierarchy SwiftUI — dibangun ulang saat dibuka lagi.
        popover.contentViewController = nil
    }
}
