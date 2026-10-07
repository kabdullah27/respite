import SwiftUI
import RespiteCore
import DesignKit

/// Smart Scan end-to-end: pindai → hasil tumbuh live per owner + strip status
/// per kategori → dry-run preview (sekali per jenis aksi) → pindah ke Trash +
/// tercatat di Safety Ledger.
struct SmartScanView: View {


    @ObservedObject private var model = SmartScanModel.shared
    @State private var showFailedItems = false
    @State private var showDryRunPreview = false

    private var selectedBytes: Int64 {
        model.results.filter { model.selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DKSpacing.xl) {
                controls

                if case .cleaned(let bytes) = model.phase {
                    cleanBanner(bytes)
                }

                if model.phase != .idle {
                    progressStrip
                }

                ForEach(ScanCategory.allCases, id: \.rawValue) { category in
                    categorySection(category)
                }
            }
            .padding(DKSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert(
            NSLocalizedString("Pratinjau sebelum membersihkan", comment: ""),
            isPresented: $showDryRunPreview
        ) {
            Button(NSLocalizedString("Batal", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Lanjutkan", comment: "")) {
                UserDefaults.standard.set(true, forKey: SmartScanModel.dryRunKey)
                model.performClean()
            }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "Dry-run: %d item (%@) akan dipindah ke Trash dan bisa dikembalikan dari sana.",
                    comment: ""
                ),
                model.results.filter { model.selected.contains($0.id) }.count,
                ByteFormat.string(from: selectedBytes)
            ))
            + Text(" ")
            + Text(NSLocalizedString("Folder sistem dan dokumen pribadi tidak pernah disentuh oleh aksi ini.", comment: ""))
        }
    }

    /// Gate dry-run: pertama kali → pratinjau dulu; setelah itu langsung.
    private func handleCleanRequest() {
        if !model.requestClean() {
            showDryRunPreview = true
        }
    }

    // MARK: Kontrol atas

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            Button {
                model.startScan()
            } label: {
                Label("Mulai Pindai", systemImage: "magnifyingglass")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

        case .scanning:
            HStack(spacing: DKSpacing.md) {
                ProgressView()
                Text("Memindai…").foregroundStyle(.secondary)
                Spacer()
                Text(runningTotalText)
                    .font(.dkData(12))
                    .foregroundStyle(.secondary)
                Button("Batalkan") {
                    model.cancelScan()
                }
            }

        case .results:
            toolbar

        case .cleaned:
            toolbar
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: DKSpacing.xs) {
            HStack(spacing: DKSpacing.md) {
                Button {
                    model.startScan()
                } label: {
                    Label("Pindai Ulang", systemImage: "arrow.clockwise")
                }
                Spacer()
                Text(String(
                    format: NSLocalizedString("%@ terpilih", comment: ""),
                    ByteFormat.string(from: selectedBytes)
                ))
                .font(.dkData(13))
                .foregroundStyle(.secondary)
                Button("Bersihkan yang dipilih") {
                    handleCleanRequest()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty)
            }
            if !model.selected.isEmpty {
                Label(
                    NSLocalizedString("Dipindah ke Trash — bisa dipulihkan dari Finder kapan saja.", comment: ""),
                    systemImage: "arrow.uturn.left.circle"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var runningTotalText: String {
        let bytes = model.results.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return String(
            format: NSLocalizedString("%d item · %@", comment: "total sementara saat scan"),
            model.results.count,
            ByteFormat.string(from: bytes)
        )
    }

    // MARK: Strip model.progress per kategori

    private var progressStrip: some View {
        VStack(spacing: DKSpacing.sm) {
            ForEach(ScanCategory.allCases, id: \.rawValue) { category in
                let state = model.progress[category] ?? SmartScanModel.CategoryProgress()
                HStack(spacing: DKSpacing.sm) {
                    Group {
                        switch state.status {
                        case .pending:
                            Image(systemName: "clock")
                                .foregroundStyle(.tertiary)
                        case .running:
                            ProgressView()
                                .controlSize(.small)
                        case .done:
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(state.count > 0 ? AnyShapeStyle(DKColor.accent) : AnyShapeStyle(.tertiary))
                        }
                    }
                    .frame(width: 16)
                    Text(categoryName(category))
                        .font(.callout)
                    Spacer()
                    Text(statusText(state))
                        .font(.dkData(12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    private func statusText(_ state: SmartScanModel.CategoryProgress) -> String {
        switch state.status {
        case .pending:
            return NSLocalizedString("Menunggu", comment: "")
        case .running:
            return state.count > 0
                ? String(
                    format: NSLocalizedString("%d item · %@", comment: ""),
                    state.count,
                    ByteFormat.string(from: state.bytes)
                )
                : NSLocalizedString("Memindai…", comment: "")
        case .done:
            return state.count > 0
                ? String(
                    format: NSLocalizedString("%d item · %@", comment: ""),
                    state.count,
                    ByteFormat.string(from: state.bytes)
                )
                : NSLocalizedString("Tidak ada", comment: "")
        }
    }

    // MARK: Hasil per kategori

    @ViewBuilder
    private func categorySection(_ category: ScanCategory) -> some View {
        let rows = model.results.filter { $0.category == category }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: DKSpacing.md) {
                Text(categoryName(category))
                    .font(.title3.weight(.semibold))
                VStack(spacing: DKSpacing.sm) {
                    ForEach(rows.sorted { $0.sizeBytes > $1.sizeBytes }) { result in
                        resultRow(result)
                        if result.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(DKSpacing.md)
                .background(DKColor.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
            }
        }
    }

    private func resultRow(_ result: ScanResult) -> some View {
        HStack(alignment: .center) {
            ReadoutRow(
                value: ByteFormat.string(from: result.sizeBytes),
                label: result.ownerName,
                detail: reason(result.category),
                badge: result.isSelectedByDefault
                    ? nil
                    : NSLocalizedString("Baru", comment: "")
            )
            Spacer(minLength: DKSpacing.sm)
            Toggle("", isOn: Binding(
                get: { model.selected.contains(result.id) },
                set: { isChecked in
                    if isChecked {
                        model.selected.insert(result.id)
                    } else {
                        model.selected.remove(result.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(result.ownerName)
        }
        .padding(.vertical, DKSpacing.xs)
        .contextMenu {
            Button(NSLocalizedString("Selalu kecualikan folder ini", comment: "")) {
                excludeResult(result)
            }
        }
    }

    /// Klik kanan → whitelist permanen + keluar dari hasil sekarang.
    private func excludeResult(_ result: ScanResult) {
        var whitelist = UserWhitelist.load()
        whitelist.add(result.url.path)
        whitelist.save()
        model.exclude(result)
    }

    private func cleanBanner(_ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
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
                    let trash = (NSString(string: "~/.Trash").expandingTildeInPath) as String
                    NSWorkspace.shared.open(URL(fileURLWithPath: trash))
                }
                .controlSize(.small)
            }
            Text(NSLocalizedString("Semua item masih bisa dipulihkan dari Trash.", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
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
        .padding(DKSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DKColor.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card))
    }

    // MARK: Aksi


    // MARK: Teks kategori

    private func categoryName(_ category: ScanCategory) -> String {
        switch category {
        case .userCaches: return NSLocalizedString("Cache", comment: "")
        case .userLogs: return NSLocalizedString("Log", comment: "")
        case .trash: return NSLocalizedString("Trash", comment: "")
        }
    }

    private func reason(_ category: ScanCategory) -> String {
        switch category {
        case .userCaches:
            return NSLocalizedString("Cache aman dibuat ulang oleh aplikasi pemiliknya.", comment: "")
        case .userLogs:
            return NSLocalizedString("Log lama hanya berguna untuk investigasi masalah yang sudah lewat.", comment: "")
        case .trash:
            return NSLocalizedString("Sudah berada di Trash — menunggu dikosongkan.", comment: "")
        }
    }
}
