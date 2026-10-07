import SwiftUI
import RespiteCore
import DesignKit
import AppKit

/// Developer Cache Cleanup (TRD §4.6): deteksi tool dulu (Xcode/Homebrew/
/// Docker/Node) → scan target yang relevan aja. node_modules cuma di folder
/// yang user pilih. Docker cleanup via CLI menyusul (butuh gate eksekusi
/// command), sekarang cuma informasi kalau terdeteksi.
struct DevCacheView: View {

    @ObservedObject private var model = DevCacheModel.shared
    @State private var showFailedItems = false
    @State private var showDryRunPreview = false

    private var selectedBytes: Int64 {
        model.targets.filter { model.selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                toolChips
                nodeModulesPicker
                controls

                if case .cleaned(let bytes) = model.phase {
                    cleanBanner(bytes)
                }

                if !model.targets.isEmpty {
                    resultList
                } else if model.phase == .scanning {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Memindai…").foregroundColor(.secondary)
                    }
                }

                Text(NSLocalizedString("Docker terdeteksi tapi pembersihannya lewat CLI docker menyusul bersama gate eksekusi command — target di atas semuanya berbasis file, aman dipindah ke Trash dan akan dibuat ulang otomatis saat dibutuhkan.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            model.detectToolsIfNeeded()
        }
        .alert(
            NSLocalizedString("Pratinjau sebelum membersihkan", comment: ""),
            isPresented: $showDryRunPreview
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: DevCacheModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d item (%@) akan dipindah ke Trash — DerivedData, cache, dan node_modules akan dibuat ulang otomatis saat dibutuhkan.",
                    comment: ""
                ),
                model.targets.filter { model.selected.contains($0.id) }.count,
                ByteFormat.string(from: selectedBytes)
            ))
        }
    }

    // MARK: Deteksi tool

    private var toolChips: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            Text(NSLocalizedString("Tool terdeteksi", comment: ""))
                .font(.title3.weight(.semibold))
            Text(NSLocalizedString("Sub-modul hanya ditawarkan untuk tool yang benar-benar terpasang.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: DKSpacing.sm) {
                ForEach(model.tools) { tool in
                    StatusPill(
                        toolName(tool.kind) + (tool.isInstalled ? " ✓" : " —"),
                        color: tool.isInstalled ? DKColor.accent : DKColor.neutral
                    )
                }
            }
        }
        .padding(DKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
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

    // MARK: node_modules picker

    private var nodeModulesPicker: some View {
        HStack(spacing: DKSpacing.md) {
            Button {
                pickNodeRoot()
            } label: {
                Label(NSLocalizedString("Tambah folder project untuk node_modules…", comment: ""), systemImage: "plus")
            }
            .controlSize(.small)
            if !model.nodeRoots.isEmpty {
                Text(String(
                    format: NSLocalizedString("%d folder dipilih", comment: ""),
                    model.nodeRoots.count
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    /// Gate dry-run: pertama kali → pratinjau dulu; setelah itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showDryRunPreview = true
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

    // MARK: Kontrol

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle, .results, .cleaned:
            HStack(spacing: DKSpacing.md) {
                Button {
                    model.startScan()
                } label: {
                    Label(
                        model.phase == .idle ? "Mulai Pindai" : "Pindai Ulang",
                        systemImage: model.phase == .idle ? "magnifyingglass" : "arrow.clockwise"
                    )
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                if model.phase != .idle {
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%@ terpilih", comment: ""),
                        ByteFormat.string(from: selectedBytes)
                    ))
                    .font(.dkData(13))
                    .foregroundStyle(.secondary)
                    Button("Bersihkan yang dipilih") { handleCleanRequest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selected.isEmpty)
                }
            }
        case .scanning:
            HStack(spacing: DKSpacing.md) {
                ProgressView()
                Text("Memindai…").foregroundColor(.secondary)
                Spacer()
                Button("Batalkan") { model.cancelScan() }
            }
        }
    }

    // MARK: Hasil — dikelompokkan per jenis (jangan satu list datar campur aduk)

    private var resultList: some View {
        let grouped = Dictionary(grouping: model.targets, by: \.kind)
        return VStack(alignment: .leading, spacing: DKSpacing.lg) {
            ForEach(DevCacheTarget.Kind.allCases, id: \.rawValue) { kind in
                if let items = grouped[kind], !items.isEmpty {
                    kindSection(kind: kind, items: items.sorted { $0.sizeBytes > $1.sizeBytes })
                }
            }
        }
    }

    private func kindSection(kind: DevCacheTarget.Kind, items: [DevCacheTarget]) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindName(kind)).font(.title3.weight(.semibold))
                Spacer()
                Text(String(
                    format: NSLocalizedString("%d item · %@", comment: ""),
                    items.count,
                    ByteFormat.string(from: items.reduce(0) { $0 + $1.sizeBytes })
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Text(reason(kind))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: DKSpacing.sm) {
                ForEach(items) { target in
                    HStack {
                        ReadoutRow(
                            value: ByteFormat.string(from: target.sizeBytes),
                            label: target.title,
                            detail: nil,
                            badge: target.isSelectedByDefault ? nil : NSLocalizedString("Baru", comment: "")
                        )
                        Spacer(minLength: DKSpacing.sm)
                        Toggle("", isOn: Binding(
                            get: { model.selected.contains(target.id) },
                            set: { isChecked in
                                if isChecked { model.selected.insert(target.id) } else { model.selected.remove(target.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    }
                    .padding(.vertical, DKSpacing.xs)
                    .contextMenu {
                        Button(NSLocalizedString("Selalu kecualikan folder ini", comment: "")) {
                            excludeTarget(target)
                        }
                    }
                }
            }
            .padding(DKSpacing.md)
            .background(DKColor.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
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
        case .xcodeDerivedData: return NSLocalizedString("Xcode DerivedData", comment: "")
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

    @ViewBuilder
    private func cleanBanner(_ bytes: Int64) -> some View {
        HStack {
            Label {
                Text(String(
                    format: NSLocalizedString("%@ berhasil dibersihkan", comment: ""),
                    ByteFormat.string(from: bytes)
                ))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(DKColor.accent)
            Spacer()
            Button("Buka Trash") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: "~/.Trash").expandingTildeInPath))
            }
            .controlSize(.small)
        }
        .padding(DKSpacing.md)
        .background(DKColor.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))

        if !model.failedItems.isEmpty {
            DisclosureGroup(
                isExpanded: $showFailedItems,
                content: {
                    ForEach(Array(model.failedItems.enumerated()), id: \.offset) { _, failed in
                        HStack(alignment: .top) {
                            Text(failed.url.lastPathComponent).font(.caption.weight(.medium))
                            Spacer()
                            Text(failed.reason).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                },
                label: {
                    Text(String(
                        format: NSLocalizedString("%d item gagal dibersihkan — lihat alasannya", comment: ""),
                        model.failedItems.count
                    ))
                    .font(.caption)
                    .foregroundColor(DKColor.attention)
                }
            )
        }
    }

    // MARK: Aksi

}
