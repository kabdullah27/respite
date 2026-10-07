import SwiftUI
import RespiteCore
import DesignKit

/// Browser Data Cleaner (TRD §4.9) v1 — cache saja. Browser yang masih
/// berjalan TIDAK bisa dibersihkan (cache yang ditimpa bisa korup) —
/// dideteksi via NSWorkspace dan dikunci dengan penjelasan.
struct BrowserCleanerView: View {
    @ObservedObject private var model = BrowserCleanerModel.shared
    @State private var showDryRunPreview = false

    private var selectedBytes: Int64 {
        model.results.reduce(Int64(0)) { total, result in
            total + BrowserDataType.allCases.reduce(Int64(0)) { sum, type in
                model.selected.contains("\(result.bundleID)|\(type.rawValue)")
                    ? sum + result.totalBytes(for: type)
                    : sum
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.lg) {
                HStack(spacing: DKSpacing.md) {
                    Button {
                        model.rescan()
                    } label: {
                        Label(NSLocalizedString("Pindai Ulang", comment: ""), systemImage: "arrow.clockwise")
                    }
                    Spacer()
                    Text(String(
                        format: NSLocalizedString("%d browser", comment: ""),
                        model.results.count
                    ))
                    .font(.dkData(12))
                    .foregroundStyle(.secondary)
                    Button("Bersihkan yang dipilih") { handleCleanRequest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selected.isEmpty)
                }

                if let cleanedBytes = model.cleanedBytes {
                    HStack {
                        Label {
                            Text(String(
                                format: NSLocalizedString("%@ berhasil dibersihkan", comment: ""),
                                ByteFormat.string(from: cleanedBytes)
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
                }

                if model.isLoading {
                    HStack(spacing: DKSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(NSLocalizedString("Memuat…", comment: "")).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else if model.results.isEmpty {
                    EmptyStateView(
                        symbol: "globe",
                        title: NSLocalizedString("Tidak ada browser yang dikenali", comment: ""),
                        message: NSLocalizedString("Browser yang didukung (Chrome, Arc, Brave, Edge, Firefox, Safari) tidak ditemukan di folder Applications.", comment: "")
                    )
                } else {
                    VStack(spacing: DKSpacing.sm) {
                        ForEach(model.results) { result in
                            browserRow(result)
                        }
                    }
                    .padding(DKSpacing.md)
                    .background(DKColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
                }

                Text(NSLocalizedString("Cache dibuat ulang otomatis dan tidak mengeluarkan kamu dari akun. Riwayat dan cookie bersifat lebih sensitif — tidak tercentang bawaan; menghapus cookie akan keluar dari semua situs, dan riwayat yang tersinkron ke akun tetap ada di server. Data browser yang masih berjalan tidak pernah disentuh. Riwayat/cookie Safari tidak didukung (dilindungi TCC).", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { model.loadIfNeeded() }
        .alert(
            NSLocalizedString("Pratinjau sebelum membersihkan", comment: ""),
            isPresented: $showDryRunPreview
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: BrowserCleanerModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d jenis data (%@) akan dipindah ke Trash. Cache dibuat ulang otomatis; menghapus cookie akan MENGELUARKAN kamu dari semua situs; riwayat yang tersinkron ke akun tetap ada di server.",
                    comment: ""
                ),
                model.selected.count,
                ByteFormat.string(from: selectedBytes)
            ))
        }
    }

    /// Gate dry-run: pertama kali → pratinjau dulu; setelah itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showDryRunPreview = true
        }
    }

    // MARK: Row per browser

    private func browserRow(_ result: BrowserScanResult) -> some View {
        let isRunning = model.runningBundleIDs.contains(result.bundleID)

        return VStack(alignment: .leading, spacing: DKSpacing.xs) {
            HStack(spacing: DKSpacing.sm) {
                Image(systemName: "globe")
                    .foregroundStyle(DKColor.accent)
                Text(result.name).font(.callout.weight(.semibold))
                Spacer()
                if isRunning {
                    Text(NSLocalizedString("Masih berjalan", comment: ""))
                        .font(.caption.weight(.medium))
                        .foregroundColor(DKColor.attention)
                }
            }
            if isRunning {
                Text(NSLocalizedString("Tutup browser ini dulu sebelum membersihkan — data yang ditimpa saat browser aktif bisa rusak.", comment: ""))
                    .font(.caption)
                    .foregroundColor(DKColor.attention)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(BrowserDataType.allCases) { type in
                    dataRow(result, type: type)
                }
            }
        }
        .padding(.vertical, DKSpacing.sm)
    }

    private func dataRow(_ result: BrowserScanResult, type: BrowserDataType) -> some View {
        let bytes = result.totalBytes(for: type)
        let key = "\(result.bundleID)|\(type.rawValue)"
        let available = bytes > 0 || !result.urls(for: type).isEmpty
        let isEmptyData = result.urls(for: type).isEmpty && type != .cache

        return HStack(spacing: DKSpacing.sm) {
            Toggle("", isOn: Binding(
                get: { model.selected.contains(key) },
                set: { isOn in
                    if isOn { model.selected.insert(key) } else { model.selected.remove(key) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!available || bytes == 0)

            Text(dataTypeName(type)).font(.callout)
            if type == .cookies {
                Text(NSLocalizedString("— akan keluar dari semua situs", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isEmptyData {
                Text(NSLocalizedString("tidak didukung", comment: ""))
                    .font(.caption2)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            } else if bytes == 0 {
                Text(NSLocalizedString("bersih", comment: ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(ByteFormat.string(from: bytes))
                    .font(.dkData(13))
            }
        }
        .padding(.leading, DKSpacing.lg)
    }

    private func dataTypeName(_ type: BrowserDataType) -> String {
        switch type {
        case .cache: return NSLocalizedString("Cache", comment: "")
        case .history: return NSLocalizedString("Riwayat", comment: "")
        case .cookies: return NSLocalizedString("Cookie", comment: "")
        }
    }

    // MARK: Aksi

}
