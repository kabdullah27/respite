import SwiftUI
import RespiteCore
import DesignKit

/// Pembersih Browser: satu kartu per browser, tiga centang (cache, riwayat,
/// cookie). Browser yang masih berjalan TIDAK bisa dibersihkan (data yang
/// ditimpa saat aktif bisa rusak) — dideteksi via NSWorkspace dan dikunci.
/// Pola halaman mengikuti ToolPage (mencari → hasil → selesai).
struct BrowserCleanerView: View {
    @ObservedObject private var model = BrowserCleanerModel.shared
    @State private var showConfirm = false

    private var selectedBytes: Int64 {
        model.results.reduce(Int64(0)) { total, result in
            total + BrowserDataType.allCases.reduce(Int64(0)) { sum, type in
                model.selected.contains("\(result.bundleID)|\(type.rawValue)")
                    ? sum + result.totalBytes(for: type)
                    : sum
            }
        }
    }

    private var totalBytes: Int64 {
        model.results.reduce(Int64(0)) { total, result in
            total + BrowserDataType.allCases.reduce(Int64(0)) { $0 + result.totalBytes(for: $1) }
        }
    }

    private func isSelected(_ type: BrowserDataType) -> Bool {
        model.selected.contains { $0.hasSuffix("|\(type.rawValue)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.lg) {
            if let cleanedBytes = model.cleanedBytes {
                ToolDoneCard(
                    title: String(
                        format: NSLocalizedString("%@ dipindahkan ke Trash", comment: ""),
                        ByteFormat.string(from: cleanedBytes)
                    )
                )
                if model.failureCount > 0 {
                    Text(String(
                        format: NSLocalizedString("%d item gagal dibersihkan", comment: ""),
                        model.failureCount
                    ))
                    .font(.callout)
                    .foregroundColor(DKColor.attention)
                }
            }

            if model.isLoading {
                ToolProgressCard(
                    title: NSLocalizedString("Memeriksa browser…", comment: ""),
                    detail: NSLocalizedString("Sedang menghitung ukuran cache, riwayat, dan cookie.", comment: "")
                )
            } else if model.results.isEmpty {
                ToolEmptyResult(
                    title: NSLocalizedString("Tidak ada browser yang dikenali", comment: ""),
                    message: NSLocalizedString("Browser yang didukung (Chrome, Arc, Brave, Edge, Firefox, Safari) tidak ditemukan di folder Applications.", comment: ""),
                    onRescan: { model.rescan() }
                )
            } else {
                results
            }
        }
        .task { model.loadIfNeeded() }
        .alert(
            ToolConfirm.title(count: model.selected.count, bytes: selectedBytes),
            isPresented: $showConfirm
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Pindahkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: BrowserCleanerModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(confirmMessage)
        }
    }

    /// Cookie & riwayat SELALU lewat konfirmasi (lihat requestClean) —
    /// pesannya harus jelas apa akibatnya.
    private var confirmMessage: String {
        var parts: [String] = []
        if isSelected(.cookies) {
            parts.append(NSLocalizedString("Cookie ikut dihapus: kamu akan keluar dari semua situs dan perlu masuk lagi.", comment: ""))
        }
        if isSelected(.history) {
            parts.append(NSLocalizedString("Riwayat penelusuran di Mac ini akan hilang. Riwayat yang tersinkron ke akun browser tetap ada.", comment: ""))
        }
        if isSelected(.cache) {
            parts.append(NSLocalizedString("Cache aman dihapus — browser membuatnya ulang otomatis.", comment: ""))
        }
        parts.append(ToolConfirm.message)
        return parts.joined(separator: "\n\n")
    }

    /// Pertama kali (atau ada cookie/riwayat) → konfirmasi dulu; selain itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showConfirm = true
        }
    }

    // MARK: Hasil

    @ViewBuilder
    private var results: some View {
        ToolResultHeader(
            title: String(
                format: NSLocalizedString("%d browser · %@", comment: ""),
                model.results.count,
                ByteFormat.string(from: totalBytes)
            ),
            subtitle: NSLocalizedString("Centang apa yang mau dibersihkan di tiap browser. Cache sudah dicentang karena paling aman.", comment: ""),
            onRescan: { model.rescan() }
        )

        ForEach(model.results) { result in
            browserCard(result)
        }

        ToolActionBar(
            selectedCount: model.selected.count,
            selectedBytes: selectedBytes,
            buttonTitle: NSLocalizedString("Bersihkan", comment: ""),
            action: handleCleanRequest
        )

        ToolDetails {
            Text(NSLocalizedString("Browser yang sedang terbuka tidak pernah disentuh.", comment: ""))
            Text(NSLocalizedString("Riwayat yang tersinkron ke akun browser (mis. akun Google) tetap tersimpan di server.", comment: ""))
            Text(NSLocalizedString("Riwayat dan cookie Safari tidak bisa dibersihkan dari sini karena dilindungi macOS.", comment: ""))
        }
    }

    // MARK: Kartu per browser

    private func browserCard(_ result: BrowserScanResult) -> some View {
        let isRunning = model.runningBundleIDs.contains(result.bundleID)

        return ToolCard {
            HStack(spacing: DKSpacing.md) {
                browserIcon(result)
                Text(result.name).font(.headline)
                Spacer()
                if isRunning {
                    StatusPill(NSLocalizedString("Sedang dibuka", comment: ""), color: DKColor.attention)
                }
            }
            if isRunning {
                Label {
                    Text(String(
                        format: NSLocalizedString("Tutup %@ dulu, lalu tekan \"Pindai ulang\". Membersihkan browser yang sedang dibuka bisa merusak datanya.", comment: ""),
                        result.name
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DKColor.attention)
                }
                .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: DKSpacing.sm) {
                    ForEach(BrowserDataType.allCases) { type in
                        dataRow(result, type: type)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func browserIcon(_ result: BrowserScanResult) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: result.bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(Color.respite)
                .frame(width: 28, height: 28)
        }
    }

    private func dataRow(_ result: BrowserScanResult, type: BrowserDataType) -> some View {
        let bytes = result.totalBytes(for: type)
        let key = "\(result.bundleID)|\(type.rawValue)"
        let available = bytes > 0 || !result.urls(for: type).isEmpty
        let isEmptyData = result.urls(for: type).isEmpty && type != .cache

        return HStack(spacing: DKSpacing.sm) {
            Toggle(isOn: Binding(
                get: { model.selected.contains(key) },
                set: { isOn in
                    if isOn { model.selected.insert(key) } else { model.selected.remove(key) }
                }
            )) {
                Text(dataTypeName(type)).font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(!available || bytes == 0)

            Spacer()
            if isEmptyData {
                Text(NSLocalizedString("tidak tersedia", comment: ""))
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            } else if bytes == 0 {
                Text(NSLocalizedString("sudah bersih", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(ByteFormat.string(from: bytes))
                    .font(.dkData(12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func dataTypeName(_ type: BrowserDataType) -> String {
        switch type {
        case .cache: return NSLocalizedString("Cache (aman, dibuat ulang otomatis)", comment: "")
        case .history: return NSLocalizedString("Riwayat penelusuran", comment: "")
        case .cookies: return NSLocalizedString("Cookie (kamu akan keluar dari situs)", comment: "")
        }
    }
}
