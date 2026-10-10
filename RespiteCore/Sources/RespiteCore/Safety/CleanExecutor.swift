import Foundation

// MARK: - Safety Ledger (TRD §4.20 p4, §7)

/// Satu catatan aksi di Undo Ledger — source of truth buat SEMUA aksi
/// destructive (bukan cuma file): ada jejak "apa yang berubah" sebelum
/// eksekusi, bukan sesudah.
public struct LedgerEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let actionType: String
    public let target: String
    public let timestamp: Date
    public let reversible: Bool
    public let detail: String

    public init(
        actionType: String,
        target: String,
        timestamp: Date = Date(),
        reversible: Bool,
        detail: String
    ) {
        self.id = UUID()
        self.actionType = actionType
        self.target = target
        self.timestamp = timestamp
        self.reversible = reversible
        self.detail = detail
    }
}

public enum SafetyLedger {
    public static var defaultURL: URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ))?
            .appendingPathComponent("Respite/history.json")
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("respite-history.json")
    }

    /// Pindahin riwayat era "Ringkas" (nama lama app) ke folder Respite —
    /// sekali saja, dipanggil saat launch. Audit trail nggak boleh hilang
    /// cuma gara-gara ganti nama.
    public static func migrateLegacyHistory() {
        let fm = FileManager.default
        guard let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return }
        let legacy = base.appendingPathComponent("Ringkas/history.json")
        let current = base.appendingPathComponent("Respite/history.json")
        guard fm.fileExists(atPath: legacy.path),
              !fm.fileExists(atPath: current.path) else { return }
        // Merge keduanya kalau ternyata sudah ada isi: gabung + urut waktu.
        let legacyEntries = load(from: legacy)
        let currentEntries = load(from: current)
        let merged = (legacyEntries + currentEntries).sorted { $0.timestamp < $1.timestamp }
        // Encoder yang SAMA dengan record() — JSONEncoder polos menulis
        // tanggal sebagai angka, load() (.iso8601) gagal decode → riwayat
        // dianggap kosong lalu ketimpa entry baru pertama.
        if let data = try? makeEncoder().encode(merged) {
            try? fm.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: current, options: .atomic)
        }
    }

    /// Serialisasi read-modify-write antar pemanggil (UI + maintenance
    /// terjadwal) — tanpa ini dua record bersamaan saling menimpa.
    private static let lock = NSLock()

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func record(_ entry: LedgerEntry, to fileURL: URL = defaultURL) {
        record([entry], to: fileURL)
    }

    /// Catat banyak entry dalam SATU tulis — clean 10k file nggak lagi
    /// baca-decode-encode-tulis seluruh riwayat 10k kali.
    public static func record(_ newEntries: [LedgerEntry], to fileURL: URL = defaultURL) {
        guard !newEntries.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = load(from: fileURL)
        entries.append(contentsOf: newEntries)
        guard let data = try? makeEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    public static func load(from fileURL: URL = defaultURL) -> [LedgerEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LedgerEntry].self, from: data)) ?? []
    }

    /// Hapus riwayat (log-nya aja — file di Trash nggak tersentuh).
    public static func clear(to fileURL: URL = defaultURL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Clean Executor (soft delete, PRD §6.6)

/// Eksekusi pembersihan: file PINDAH ke Trash (bukan rm permanen) — itu
/// mekanismenya undo. Ledger dicatat SEBELUM tiap eksekusi (TRD §7).
public enum CleanExecutor {
    public struct CleanedItem: Sendable, Equatable {
        public let url: URL
        public let bytes: Int64
    }

    public struct FailedItem: Sendable, Equatable {
        public let url: URL
        public let reason: String
    }

    /// Item generik buat modul mana pun (Smart Scan pakai ScanResult,
    /// Large Files pakai FileHit — dua-duanya dipetakan ke sini).
    public struct TrashItem: Sendable, Equatable {
        public let url: URL
        public let bytes: Int64
        public let label: String

        public init(url: URL, bytes: Int64, label: String) {
            self.url = url
            self.bytes = bytes
            self.label = label
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let cleaned: [CleanedItem]
        public let failed: [FailedItem]

        public var freedBytes: Int64 {
            cleaned.reduce(0) { $0 + $1.bytes }
        }
    }

    /// Soft-delete ke Trash untuk modul mana pun. Protected List tetap
    /// ditolak di sini (level operasi), ledger dicatat SEBELUM eksekusi.
    public static func move(
        _ items: [TrashItem],
        module: String,
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> Outcome {
        var cleaned: [CleanedItem] = []
        var failed: [FailedItem] = []

        var allowed: [TrashItem] = []
        for item in items {
            // Terlindungi: tolak, tapi LAPORKAN — dulu di-skip diam-diam
            // sehingga UI bilang "berhasil" padahal file masih ada.
            if ProtectedList.isProtected(item.url) {
                failed.append(FailedItem(url: item.url, reason: protectedReason))
                continue
            }
            // Sudah di Trash → trashItem cuma no-op/rename, nggak membebaskan
            // byte apa pun. Laporkan jujur, jangan dihitung "freed".
            if isInsideTrash(item.url) {
                failed.append(FailedItem(
                    url: item.url,
                    reason: "Sudah ada di Trash — kosongkan lewat Trash Manager"
                ))
            } else {
                allowed.append(item)
            }
        }
        // Ledger dicatat SEBELUM eksekusi — satu tulis buat seluruh batch.
        SafetyLedger.record(
            allowed.map { item in
                LedgerEntry(
                    actionType: "move-to-trash",
                    target: item.url.path,
                    reversible: true,
                    detail: "\(module): \(item.label) · \(ByteFormat.string(from: item.bytes))"
                )
            },
            to: ledgerURL
        )
        for item in allowed {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                cleaned.append(CleanedItem(url: item.url, bytes: item.bytes))
            } catch {
                failed.append(FailedItem(url: item.url, reason: error.localizedDescription))
            }
        }
        return Outcome(cleaned: cleaned, failed: failed)
    }

    static let protectedReason = "Dilindungi (Protected List) — tidak disentuh"

    static func isInsideTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    public static func moveToTrash(
        _ results: [ScanResult],
        module: String = "Smart Scan",
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> Outcome {
        move(
            results.map { TrashItem(url: $0.url, bytes: $0.sizeBytes, label: $0.ownerName) },
            module: module,
            ledgerURL: ledgerURL
        )
    }

    /// Hapus permanen (bypass Trash) — SATU-SATUNYA jalur irreversible di app.
    /// UI wajib sudah melewati konfirmasi berlapis (type-to-confirm) sebelum
    /// manggil ini; ledger tercatat `reversible: false` sebelum eksekusi.
    public static func permanentlyDelete(
        _ items: [TrashEntry],
        module: String = "Trash Manager",
        ledgerURL: URL = SafetyLedger.defaultURL
    ) -> Outcome {
        var cleaned: [CleanedItem] = []
        var failed: [FailedItem] = []

        let allowed = items.filter { !ProtectedList.isProtected($0.url) }
        failed += items
            .filter { ProtectedList.isProtected($0.url) }
            .map { FailedItem(url: $0.url, reason: protectedReason) }
        SafetyLedger.record(
            allowed.map { item in
                LedgerEntry(
                    actionType: "delete-permanent",
                    target: item.url.path,
                    reversible: false,
                    detail: "\(module): \(item.url.lastPathComponent) · \(ByteFormat.string(from: item.sizeBytes))"
                )
            },
            to: ledgerURL
        )
        for item in allowed {
            do {
                try FileManager.default.removeItem(at: item.url)
                cleaned.append(CleanedItem(url: item.url, bytes: item.sizeBytes))
            } catch {
                failed.append(FailedItem(url: item.url, reason: error.localizedDescription))
            }
        }
        return Outcome(cleaned: cleaned, failed: failed)
    }
}
