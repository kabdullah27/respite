import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Sisa Pengembang: deteksi tool dulu (Xcode/Homebrew/Node/…) → scan target
/// yang relevan saja. node_modules hanya dicari di folder proyek yang user
/// pilih. Docker belum dibersihkan (butuh perintah CLI) — hanya informasi.
/// Pola halaman mengikuti ToolPage (mulai → mencari → hasil → selesai).
struct DevCacheView: View {

    @ObservedObject private var model = DevCacheModel.shared
    @State private var showConfirm = false

    private var selectedBytes: Int64 {
        model.targets.filter { model.selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalBytes: Int64 {
        model.targets.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            switch model.phase {
            case .idle:
                startCard
            case .scanning:
                ToolProgressCard(
                    detail: String(
                        format: NSLocalizedString("%d item ditemukan · %@", comment: ""),
                        model.targets.count,
                        ByteFormat.string(from: totalBytes)
                    ),
                    onStop: { model.cancelScan() }
                )
            case .results:
                results
            case .cleaned(let bytes):
                ToolDoneCard(
                    title: String(
                        format: NSLocalizedString("%@ dipindahkan ke Trash", comment: ""),
                        ByteFormat.string(from: bytes)
                    ),
                    failed: model.failedItems,
                    onRescan: { model.startScan() }
                )
                if !model.targets.isEmpty { results }
            }
        }
        .onAppear {
            model.detectToolsIfNeeded()
        }
        .alert(
            ToolConfirm.title(
                count: model.targets.filter { model.selected.contains($0.id) }.count,
                bytes: selectedBytes
            ),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: DevCacheModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(NSLocalizedString("Semua ini akan dibuat ulang otomatis saat dibutuhkan (mis. saat build atau install berikutnya).", comment: "")
                 + " " + ToolConfirm.message)
        }
    }

    // MARK: 1. Mulai

    private var startCard: some View {
        ToolStartCard(
            headline: NSLocalizedString("Bersihkan sisa build dan cache alat developer", comment: ""),
            points: [
                NSLocalizedString("Hanya cache yang bisa dibuat ulang otomatis — kode proyekmu tidak disentuh.", comment: ""),
                NSLocalizedString("node_modules hanya dicari di folder proyek yang kamu pilih.", comment: ""),
                NSLocalizedString("Semua dipindah ke Trash, jadi masih bisa dikembalikan.", comment: ""),
            ],
            action: { model.startScan() }
        ) {
            VStack(alignment: .leading, spacing: DKSpacing.md) {
                detectedTools
                projectFolders
            }
        }
    }

    // MARK: Alat terdeteksi

    @ViewBuilder
    private var detectedTools: some View {
        let installed = model.tools.filter(\.isInstalled)
        if !installed.isEmpty {
            HStack(spacing: DKSpacing.sm) {
                Text(NSLocalizedString("Ditemukan di Mac kamu:", comment: ""))
                    .font(.callout)
                    .foregroundColor(.secondary)
                ForEach(installed) { tool in
                    StatusPill(toolName(tool.kind), color: DKColor.accent)
                }
            }
        }
    }

    private func toolName(_ kind: DevTools.Tool.Kind) -> String {
        switch kind {
        case .xcode: return "Xcode"
        case .homebrew: return "Homebrew"
        case .docker: return "Docker"
        case .node: return "Node"
        case .composer: return "Composer"
        case .go: return "Go"
        case .rust: return "Rust"
        }
    }

    // MARK: Folder proyek (node_modules)

    private var projectFolders: some View {
        HStack(spacing: DKSpacing.md) {
            Text(NSLocalizedString("Folder proyek", comment: ""))
                .font(.callout.weight(.medium))
            Button {
                pickNodeRoot()
            } label: {
                Label(NSLocalizedString("Tambah folder…", comment: ""), systemImage: "plus")
            }
            .controlSize(.small)
            Text(model.nodeRoots.isEmpty
                 ? NSLocalizedString("Belum ada — node_modules tidak dicari", comment: "")
                 : model.nodeRoots.map(\.lastPathComponent).joined(separator: ", ")
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(model.nodeRoots.map(\.path).joined(separator: "\n"))
        }
    }

    /// Pertama kali → konfirmasi dulu; setelah itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showConfirm = true
        }
    }

    private func pickNodeRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = NSLocalizedString("Pilih folder tempat project JavaScript/TypeScript kamu berada — Respite mencari node_modules di dalamnya (maksimal 4 level).", comment: "")
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            model.addNodeRoots(panel.urls)
        }
    }

    // MARK: 3. Hasil — dikelompokkan per jenis

    @ViewBuilder
    private var results: some View {
        if model.targets.isEmpty {
            ToolEmptyResult(
                message: NSLocalizedString("Tidak ada cache developer yang perlu dibersihkan saat ini.", comment: ""),
                onRescan: { model.startScan() }
            )
            projectFolders
        } else {
            ToolResultHeader(
                title: String(
                    format: NSLocalizedString("%d item · %@", comment: ""),
                    model.targets.count,
                    ByteFormat.string(from: totalBytes)
                ),
                subtitle: NSLocalizedString("Semua di bawah ini dibuat ulang otomatis saat dibutuhkan. Yang baru dipakai tidak dicentang otomatis.", comment: ""),
                onRescan: { model.startScan() }
            ) {
                projectFolders
            }

            let grouped = Dictionary(grouping: model.targets, by: \.kind)
            List {
                ForEach(DevCacheTarget.Kind.allCases, id: \.rawValue) { kind in
                    if let items = grouped[kind], !items.isEmpty {
                        kindSection(kind: kind, items: items.sorted { $0.sizeBytes > $1.sizeBytes })
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 400)

            ToolActionBar(
                selectedCount: model.selected.count,
                selectedBytes: selectedBytes,
                action: handleCleanRequest
            )

            ToolDetails {
                Text(NSLocalizedString("Docker belum bisa dibersihkan dari sini — pembersihannya butuh perintah docker dan akan menyusul.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("Model AI (Ollama, LM Studio) dan toolchain di ~/.cargo/bin tidak pernah disentuh.", comment: ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func kindSection(kind: DevCacheTarget.Kind, items: [DevCacheTarget]) -> some View {
        Section {
            ForEach(items) { target in
                ToolResultRow(
                    title: target.title,
                    subtitle: String(
                        format: NSLocalizedString("terakhir diubah %@", comment: ""),
                        FriendlyDate.string(target.lastModified)
                    ),
                    size: target.sizeBytes,
                    badge: target.isSelectedByDefault ? nil : NSLocalizedString("Baru dipakai", comment: ""),
                    isOn: Binding(
                        get: { model.selected.contains(target.id) },
                        set: { isChecked in
                            if isChecked { model.selected.insert(target.id) } else { model.selected.remove(target.id) }
                        }
                    )
                )
                .help(target.url.path)
                .contextMenu {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([target.url])
                    } label: {
                        Label(NSLocalizedString("Tampilkan di Finder", comment: ""), systemImage: "folder")
                    }
                    Divider()
                    Button {
                        excludeTarget(target)
                    } label: {
                        Label(NSLocalizedString("Jangan tampilkan folder ini lagi", comment: ""), systemImage: "hand.raised")
                    }
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kindName(kind)).font(.headline)
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%d item · %@", comment: ""),
                        items.count,
                        ByteFormat.string(from: items.reduce(0) { $0 + $1.sizeBytes })
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }
                Text(reason(kind))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DKSpacing.xs)
        }
    }

    private func excludeTarget(_ target: DevCacheTarget) {
        var whitelist = UserWhitelist.load()
        whitelist.add(target.url.path)
        whitelist.save()
        model.exclude(target)
    }

    private func kindName(_ kind: DevCacheTarget.Kind) -> String {
        switch kind {
        case .xcodeDerivedData: return NSLocalizedString("Hasil build Xcode", comment: "")
        case .xcodeArchives: return NSLocalizedString("Arsip Xcode", comment: "")
        case .cocoapodsCache: return NSLocalizedString("Cache CocoaPods", comment: "")
        case .spmCache: return NSLocalizedString("Cache Swift Package Manager", comment: "")
        case .homebrewCache: return NSLocalizedString("Cache Homebrew", comment: "")
        case .nodeModules: return NSLocalizedString("node_modules", comment: "")
        case .composerCache: return NSLocalizedString("Cache Composer (PHP)", comment: "")
        case .goBuildCache: return NSLocalizedString("Cache build Go", comment: "")
        case .goModCache: return NSLocalizedString("Cache modul Go", comment: "")
        case .cargoRegistry: return NSLocalizedString("Registry Cargo (Rust)", comment: "")
        case .cargoGitCache: return NSLocalizedString("Dependensi git Cargo", comment: "")
        case .aiLogs: return NSLocalizedString("Log aplikasi AI", comment: "")
        }
    }

    private func reason(_ kind: DevCacheTarget.Kind) -> String {
        switch kind {
        case .xcodeDerivedData:
            return NSLocalizedString("Hasil build Xcode — dibuat ulang otomatis saat build berikutnya.", comment: "")
        case .xcodeArchives:
            return NSLocalizedString("Arsip build lama — pastikan tidak ada yang masih perlu di-submit.", comment: "")
        case .cocoapodsCache:
            return NSLocalizedString("Cache CocoaPods — pod akan diunduh ulang saat dibutuhkan.", comment: "")
        case .spmCache:
            return NSLocalizedString("Cache Swift Package Manager — diunduh ulang otomatis.", comment: "")
        case .homebrewCache:
            return NSLocalizedString("Cache unduhan Homebrew — aman dihapus, brew mengunduh ulang bila perlu.", comment: "")
        case .nodeModules:
            return NSLocalizedString("Dependensi Node — install ulang dengan npm/pnpm/yarn bila project dipakai lagi.", comment: "")
        case .composerCache:
            return NSLocalizedString("Cache paket Composer — diunduh ulang otomatis saat composer install.", comment: "")
        case .goBuildCache:
            return NSLocalizedString("Cache build Go — dikompilasi ulang otomatis saat build berikutnya.", comment: "")
        case .goModCache:
            return NSLocalizedString("Cache modul Go (bisa berukuran GB) — modul diunduh ulang saat dibutuhkan.", comment: "")
        case .cargoRegistry:
            return NSLocalizedString("Registry crate Cargo — diunduh ulang saat dibutuhkan. ~/.cargo/bin (toolchain) tidak pernah disentuh.", comment: "")
        case .cargoGitCache:
            return NSLocalizedString("Dependensi git Cargo — di-clone ulang saat dibutuhkan.", comment: "")
        case .aiLogs:
            return NSLocalizedString("Log Ollama & LM Studio — aman dihapus. Model AI (GB-an, mahal diunduh ulang) tidak pernah disentuh.", comment: "")
        }
    }
}
