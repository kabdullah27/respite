import AppKit
import SwiftUI
import DesignKit

/// Window yang MENELAN semua event keyboard (keyDown/keyUp/flags/
/// key-equivalent termasuk ⌘Q) — inti dari kunci keyboard ala
/// KeyboardCleanTool: input tidak "dimatikan di hardware", tapi
/// tidak pernah sampai ke aplikasi lain selama overlay aktif.
final class KeyboardLockWindow: NSWindow {
    /// Dipanggil saat user menekan ⌘⌥L — pintasan darurat yang tetap
    /// jalan walau semua ketukan lain ditelan.
    var unlockComboHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // ⌘⌥L (keyCode 37 = L) → buka kunci. Window inilah yang menerima
        // SEMUA keyDown, jadi combo dikenali sebelum ditelan.
        let hasCmdOpt = event.modifierFlags.isSuperset(of: [.command, .option])
        if hasCmdOpt, event.keyCode == 37 || event.charactersIgnoringModifiers?.lowercased() == "l" {
            unlockComboHandler?()
        }
        /* selain itu: telan */
    }
    override func keyUp(with event: NSEvent) { /* telan */ }
    override func flagsChanged(with event: NSEvent) { /* telan */ }
    override func cancelOperation(_ sender: Any?) { /* telan Esc */ }
    /// PENTING: event ber-modifier (⌘/⌥) disalurkan ke performKeyEquivalent
    /// DULU sebelum keyDown — deteksi ⌘⌥L di keyDown saja tidak pernah
    /// terpanggil (bug 2026-10-04). Cek combo di sini.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let hasCmdOpt = event.modifierFlags.isSuperset(of: [.command, .option])
        if hasCmdOpt, event.keyCode == 37 || event.charactersIgnoringModifiers?.lowercased() == "l" {
            unlockComboHandler?()
            return true
        }
        return true // telan semua shortcut lain (⌘Q dsb.)
    }
}

/// State kunci keyboard untuk SwiftUI.
@MainActor
final class KeyboardLockModel: ObservableObject {
    let lockedAt: Date
    /// Bukan nil = ada timer auto-unlock (untuk hitung mundur di layar).
    let unlockAt: Date?
    var onUnlock: () -> Void

    init(lockedAt: Date, unlockAt: Date?, onUnlock: @escaping () -> Void) {
        self.lockedAt = lockedAt
        self.unlockAt = unlockAt
        self.onUnlock = onUnlock
    }

    func unlock() { onUnlock() }
}

/// Mengelola overlay kunci keyboard. PENDAPATAN PENTING: ini overlay yang
/// MENAHAN input, bukan mematikan keyboard di level hardware — artinya
/// 100% reversible (force-quit aplikasi juga otomatis membuka kunci,
/// tidak ada state sistem yang tersisa).
@MainActor
final class KeyboardLockController: ObservableObject {
    static let shared = KeyboardLockController()

    @Published private(set) var isLocked = false

    private var window: KeyboardLockWindow?
    private var observers: [NSObjectProtocol] = []
    private var autoUnlockItem: DispatchWorkItem?
    private var unlockAt: Date?

    /// `autoUnlockAfter` = detik sampai keyboard terbuka sendiri (nil =
    /// tanpa timer — manual via tombol tahan).
    func lock(autoUnlockAfter: TimeInterval?) {
        guard window == nil, let screen = NSScreen.main else { return }

        let lockedAt = Date()
        if let autoUnlockAfter, autoUnlockAfter > 0 {
            unlockAt = lockedAt.addingTimeInterval(autoUnlockAfter)
        } else {
            unlockAt = nil
        }
        let model = KeyboardLockModel(
            lockedAt: lockedAt,
            unlockAt: unlockAt
        ) { [weak self] in
            self?.unlock()
        }

        let w = KeyboardLockWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .screenSaver // di atas menu bar & Dock
        w.backgroundColor = .black
        w.isOpaque = true
        w.appearance = NSAppearance(named: .darkAqua)
        // Tetap hadir di semua Space & fullscreen — user bisa sedang
        // membersihkan di desktop mana pun.
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.unlockComboHandler = { [weak self] in
            self?.unlock()
        }
        w.contentView = NSHostingView(
            rootView: KeyboardLockOverlayView(model: model)
        )
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = w
        isLocked = true

        // Timer auto-unlock — pengaman utama: walau apa pun terjadi,
        // keyboard PASTI kembali dalam batas waktu yang dipilih user.
        if let unlockAt {
            let item = DispatchWorkItem { [weak self] in
                self?.unlock(notify: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + autoUnlockAfter!, execute: item)
            autoUnlockItem = item
        }

        // Kalau fokus dicuri (klik Dock, dsb.) → rebut balik segera.
        // Tanpa ini, ketukan keyboard bisa lolos ke app lain saat user
        // membersihkan. Pola yang sama dipakai KeyboardCleanTool.
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.regainFocus()
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.regainFocus()
        })
    }

    func unlock(notify: Bool = false) {
        autoUnlockItem?.cancel()
        autoUnlockItem = nil
        window?.orderOut(nil)
        window = nil
        isLocked = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if notify {
            Notifier.post(
                title: NSLocalizedString("Keyboard terbuka kembali", comment: ""),
                body: NSLocalizedString("Timer habis — keyboard berfungsi normal lagi.", comment: "")
            )
        }
    }

    private func regainFocus() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Tampilan overlay: layar hitam penuh + info + tombol buka-kunci yang
/// harus DITAHAN 1,2 detik — supaya tidak terbuka karena sapuan kain
/// yang menyentuh trackpad.
private struct KeyboardLockOverlayView: View {
    @ObservedObject var model: KeyboardLockModel
    @State private var pressing = false

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "keyboard")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.white.opacity(0.9))

            Text(NSLocalizedString("Keyboard Terkunci", comment: ""))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let unlockAt = model.unlockAt {
                    let remaining = Int(unlockAt.timeIntervalSince(context.date))
                    Text(String(
                        format: NSLocalizedString("terbuka otomatis dalam %d:%02d", comment: ""),
                        max(0, remaining) / 60, max(0, remaining) % 60
                    ))
                    .font(.dkData(16))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                } else {
                    let elapsed = Int(context.date.timeIntervalSince(model.lockedAt))
                    Text(String(
                        format: NSLocalizedString("terkunci %d:%02d", comment: ""),
                        elapsed / 60, elapsed % 60
                    ))
                    .font(.dkData(16))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                }
            }

            Text(NSLocalizedString("Trackpad & mouse tetap berfungsi. Semua ketukan keyboard ditahan selama layar ini aktif.", comment: ""))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            // BUKAN Button: gesture internal Button menang melawan
            // onLongPressGesture — itulah bug "hold to unlock ga jalan".
            // View polos + gesture sendiri = andal.
            Text(NSLocalizedString("Tahan untuk Buka Kunci", comment: ""))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DKSpacing.xl)
                .padding(.vertical, DKSpacing.md)
                .background(
                    Capsule().fill(Color.white.opacity(pressing ? 0.35 : 0.18))
                )
                .scaleEffect(pressing ? 0.94 : 1.0)
                .animation(.easeInOut(duration: 0.25), value: pressing)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 90) {
                    model.unlock()
                } onPressingChanged: { isPressing in
                    withAnimation { pressing = isPressing }
                }
                .accessibilityHint(NSLocalizedString("Tahan 1 detik untuk membuka kunci keyboard", comment: ""))

            Text(NSLocalizedString("atau tekan ⌘⌥L — pintasan darurat yang tetap jalan saat terkunci", comment: ""))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

            Text(NSLocalizedString("Respite tetap jalan di belakang — membersihkan layar sekarang aman.", comment: ""))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(DKSpacing.xl * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
