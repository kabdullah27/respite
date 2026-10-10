import SwiftUI
import RespiteCore
import DesignKit

// MARK: - Pola halaman alat
//
// SEMUA alat pembersih memakai alur yang sama, supaya sekali paham satu
// alat = paham semuanya:
//   1. ToolStartCard   — penjelasan singkat + tombol "Mulai Pindai"
//   2. ToolProgressCard — sedang mencari (bisa dihentikan)
//   3. ToolResultHeader + daftar + ToolActionBar — ringkasan "X bisa
//      dibebaskan", centang, satu tombol aksi utama
//   4. ToolDoneCard     — hasilnya, plus cara membatalkan
// Hal teknis disimpan di ToolDetails ("Lihat detail") — tidak di depan.

/// Kartu pembungkus standar (latar lembut + sudut membulat).
struct ToolCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.md) {
            content
        }
        .padding(DKSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DKColor.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: DKRadius.card + 2)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 2))
    }
}

/// Langkah 1 — sebelum pindai: apa yang akan dicek, kenapa aman, satu tombol.
struct ToolStartCard<Options: View>: View {
    let headline: String
    /// Maks. 3 poin pendek, bahasa sehari-hari.
    let points: [String]
    var buttonTitle: String = NSLocalizedString("Mulai Pindai", comment: "")
    var buttonSymbol: String = "magnifyingglass"
    var isDisabled = false
    let action: () -> Void
    @ViewBuilder var options: Options

    var body: some View {
        ToolCard {
            Text(headline)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                ForEach(points, id: \.self) { point in
                    Label {
                        Text(point)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.respite)
                    }
                    .font(.callout)
                }
            }
            options
            Button(action: action) {
                Label(buttonTitle, systemImage: buttonSymbol)
                    .frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Color.respite)
            .disabled(isDisabled)
            .padding(.top, DKSpacing.xs)
        }
    }
}

extension ToolStartCard where Options == EmptyView {
    init(
        headline: String,
        points: [String],
        buttonTitle: String = NSLocalizedString("Mulai Pindai", comment: ""),
        buttonSymbol: String = "magnifyingglass",
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            headline: headline,
            points: points,
            buttonTitle: buttonTitle,
            buttonSymbol: buttonSymbol,
            isDisabled: isDisabled,
            action: action,
            options: { EmptyView() }
        )
    }
}

/// Langkah 2 — sedang mencari.
struct ToolProgressCard: View {
    var title: String = NSLocalizedString("Sedang mencari…", comment: "")
    /// Mis. "12 file ditemukan · 3,2 GB".
    var detail: String?
    var onStop: (() -> Void)?

    var body: some View {
        ToolCard {
            HStack(spacing: DKSpacing.md) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail ?? NSLocalizedString("Ini bisa memakan waktu beberapa menit. Kamu boleh pindah ke alat lain.", comment: ""))
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if let onStop {
                    Button(NSLocalizedString("Hentikan", comment: ""), action: onStop)
                }
            }
        }
    }
}

/// Langkah 3 — ringkasan di atas daftar hasil.
struct ToolResultHeader<Accessory: View>: View {
    /// Mis. "12 file · 8,4 GB bisa dibebaskan".
    let title: String
    var subtitle: String?
    var onRescan: (() -> Void)?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: DKSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                if let onRescan {
                    Button {
                        onRescan()
                    } label: {
                        Label(NSLocalizedString("Pindai ulang", comment: ""), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory
        }
    }
}

extension ToolResultHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, onRescan: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, onRescan: onRescan, accessory: { EmptyView() })
    }
}

/// Langkah 3 — satu tombol aksi utama + catatan cara membatalkan.
struct ToolActionBar: View {
    let selectedCount: Int
    var selectedBytes: Int64?
    var buttonTitle: String = NSLocalizedString("Pindahkan ke Trash", comment: "")
    var note: String? = NSLocalizedString("Bisa dikembalikan dari Trash kapan saja.", comment: "")
    /// Merah — hanya untuk aksi yang TIDAK bisa dibatalkan.
    var isIrreversible = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: DKSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionSummary)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(isIrreversible ? DKColor.irreversible : .secondary)
                }
            }
            Spacer()
            Button(action: action) {
                Text(buttonLabel)
                    .frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(isIrreversible ? DKColor.irreversible : Color.respite)
            .disabled(selectedCount == 0)
        }
        .padding(DKSpacing.md)
        .background(DKColor.surfaceSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: DKRadius.card + 2)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DKRadius.card + 2))
    }

    private var selectionSummary: String {
        if selectedCount == 0 {
            return NSLocalizedString("Belum ada yang dipilih", comment: "")
        }
        if let selectedBytes {
            return String(
                format: NSLocalizedString("%d dipilih · %@", comment: ""),
                selectedCount, ByteFormat.string(from: selectedBytes)
            )
        }
        return String(format: NSLocalizedString("%d dipilih", comment: ""), selectedCount)
    }

    private var buttonLabel: String {
        guard let selectedBytes, selectedCount > 0 else { return buttonTitle }
        return "\(buttonTitle) (\(ByteFormat.string(from: selectedBytes)))"
    }
}

/// Langkah 4 — selesai: berapa yang dibebaskan, cara membatalkan, yang gagal.
struct ToolDoneCard: View {
    let title: String
    var message: String? = NSLocalizedString("File ada di Trash. Berubah pikiran? Buka Trash lalu pilih \"Kembalikan\".", comment: "")
    var failed: [CleanExecutor.FailedItem] = []
    var showOpenTrash = true
    var onRescan: (() -> Void)?

    @State private var showFailed = false

    var body: some View {
        ToolCard {
            HStack(alignment: .top, spacing: DKSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.respite)
                VStack(alignment: .leading, spacing: DKSpacing.xs) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if let message {
                        Text(message)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            HStack(spacing: DKSpacing.md) {
                if showOpenTrash {
                    Button(NSLocalizedString("Buka Trash", comment: "")) {
                        NSWorkspace.shared.open(
                            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
                        )
                    }
                }
                if let onRescan {
                    Button(NSLocalizedString("Pindai lagi", comment: ""), action: onRescan)
                }
            }
            if !failed.isEmpty {
                DisclosureGroup(isExpanded: $showFailed) {
                    VStack(alignment: .leading, spacing: DKSpacing.xs) {
                        ForEach(Array(failed.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top) {
                                Text(item.url.lastPathComponent).font(.caption.weight(.medium))
                                Spacer()
                                // Alasan dari core = kunci lokalisasi (kalau ada terjemahannya).
                                Text(NSLocalizedString(item.reason, comment: "")).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    Text(String(
                        format: NSLocalizedString("%d item tidak bisa dipindahkan — lihat kenapa", comment: ""),
                        failed.count
                    ))
                    .font(.callout)
                    .foregroundColor(DKColor.attention)
                }
            }
        }
    }
}

/// Hasil kosong — kabar baik, bukan error.
struct ToolEmptyResult: View {
    var title: String = NSLocalizedString("Tidak ada yang perlu dibersihkan", comment: "")
    var message: String
    var onRescan: (() -> Void)?

    var body: some View {
        ToolCard {
            HStack(alignment: .top, spacing: DKSpacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.respite)
                VStack(alignment: .leading, spacing: DKSpacing.xs) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(message)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if let onRescan {
                Button(NSLocalizedString("Pindai lagi", comment: ""), action: onRescan)
            }
        }
    }
}

/// Info teknis disembunyikan sampai diminta.
struct ToolDetails<Content: View>: View {
    var title: String = NSLocalizedString("Lihat detail", comment: "")
    @ViewBuilder var content: Content
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DKSpacing.sm) {
                content
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DKSpacing.xs)
        } label: {
            Text(title)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

/// Baris hasil standar: centang · nama + keterangan · ukuran.
struct ToolResultRow: View {
    let title: String
    var subtitle: String?
    var size: Int64?
    /// Label kecil (mis. "Baru", "Disarankan disimpan").
    var badge: String?
    var badgeColor: Color = DKColor.attention
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DKSpacing.md) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DKSpacing.sm) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let badge {
                        StatusPill(badge, color: badgeColor)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DKSpacing.sm)
            if let size {
                Text(ByteFormat.string(from: size))
                    .font(.dkData(12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// "3 hari lalu", "2 tahun lalu" — lebih mudah dicerna dari tanggal mentah.
enum FriendlyDate {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func string(_ date: Date) -> String {
        guard date > Date.distantPast.addingTimeInterval(86_400) else {
            return NSLocalizedString("tanggal tidak diketahui", comment: "")
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Konfirmasi standar sebelum memindah ke Trash (pengganti "Dry-run").
enum ToolConfirm {
    static func title(count: Int, bytes: Int64) -> String {
        String(
            format: NSLocalizedString("Pindahkan %d item (%@) ke Trash?", comment: ""),
            count, ByteFormat.string(from: bytes)
        )
    }

    static let message = NSLocalizedString("Kamu masih bisa mengembalikannya dari Trash. Folder sistem dan dokumen pribadi tidak pernah disentuh.", comment: "")
}
