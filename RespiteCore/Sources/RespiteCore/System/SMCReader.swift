import Foundation
import IOKit

/// Pembaca suhu via SMC (System Management Controller).
///
/// KEJUJURAN TEKNIS: macOS tidak menyediakan API PUBLIK untuk suhu CPU.
/// Semua aplikasi suhu (iStat Menus, Stats, dst.) membaca sensor lewat
/// IOService "AppleSMC" — antarmuka yang tidak didokumentasikan Apple tapi
/// sudah jadi standar de-facto bertahun-tahun dan sepenuhnya BACA-SAJA.
/// Kebijakan Respite selama ini menolak API privat untuk atribusi/data;
/// suhu dibuat pengecualian atas permintaan eksplisit user (2026-09-24)
/// dengan syarat: read-only, gagal secara diam-diam, dan UI tetap jujur
/// menampilkan thermalState saat sensor tidak terbaca.
public enum SMCReader {
    /// Kunci sensor CPU yang umum (Intel: TC0x; Apple Silicon: Tp0x/Tcx).
    /// Diambil semuanya, difilter ke rentang masuk akal, dipakai nilai
    /// tertinggi — itu indikasi panas CPU yang paling relevan.
    public static let cpuKeys: [String] = [
        // Intel
        "TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TC0X", "TCAD", "TCSC",
        // Apple Silicon (P-core/E-core/proximity)
        "Tp01", "Tp05", "Tp0D", "Tp0F", "Tp11", "Tp15",
        "Tc0p", "TC0p", "TC1C", "TC2C", "TC3C", "TC4C",
    ]

    /// Koneksi SMC dibuka sekali dan dipakai ulang — bukan spawn proses
    /// (pelajaran ioreg-baterai): IOConnectCall = syscall mikrodetik.
    private static var cachedConn: io_connect_t?
    private static let connLock = NSLock()

    /// Buka koneksi AppleSMC (injectable-able lewat openConnection buat tes).
    static func openConnection() -> io_connect_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            IOObjectRelease(service)
            return nil
        }
        IOObjectRelease(service) // conn menahan referensi sendiri
        return conn
    }

    static func sharedConnection() -> io_connect_t? {
        connLock.lock(); defer { connLock.unlock() }
        if let conn = cachedConn { return conn }
        let conn = openConnection()
        cachedConn = conn
        return conn
    }

    /// Reset koneksi (dipakai kalau call gagal — koneksi basi).
    static func resetConnection() {
        connLock.lock(); defer { connLock.unlock() }
        if let conn = cachedConn {
            IOServiceClose(conn)
        }
        cachedConn = nil
    }

    // MARK: - Protokol SMC

    /// Satu kunci SMC = 4 karakter.
    static func keyCode(_ key: String) -> UInt32? {
        let chars = key.utf8.map { $0 }
        guard chars.count == 4 else { return nil }
        return (UInt32(chars[0]) << 24) | (UInt32(chars[1]) << 16)
            | (UInt32(chars[2]) << 8) | UInt32(chars[3])
    }

    struct ReadResult {
        let bytes: [UInt8]
        let dataType: String
    }

    // Layout SMCKeyData_t (80 byte) yang dipakai AppleSMC lewat selector 2
    // (kSMCHandleYPCEvent). Perintah ada di field data8, BUKAN selector.
    private static let structSize = 80
    private static let offsetKey = 0
    private static let offsetDataSize = 28   // keyInfo.dataSize (UInt32)
    private static let offsetDataType = 32   // keyInfo.dataType (fourcc)
    private static let offsetResult = 40
    private static let offsetData8 = 42      // perintah
    private static let offsetBytes = 48      // SMCBytes_t[32]
    private static let selectorYPCEvent: UInt32 = 2
    private static let commandReadBytes: UInt8 = 5
    private static let commandGetKeyInfo: UInt8 = 9

    /// Satu panggilan IOConnectCallStructMethod; nil kalau IOKit gagal.
    private static func call(_ input: [UInt8], conn: io_connect_t) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: structSize)
        var outputCount = structSize
        let kr = input.withUnsafeMutableBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(
                    conn, selectorYPCEvent,
                    inPtr.baseAddress, structSize,
                    outPtr.baseAddress, &outputCount
                )
            }
        }
        guard kr == KERN_SUCCESS else {
            // Koneksi basi (mis. setelah sleep) — buka ulang di panggilan berikut.
            resetConnection()
            return nil
        }
        return output
    }

    private static func loadUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private static func storeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value) { bytes.replaceSubrange(offset..<offset + 4, with: $0) }
    }

    static func fourCC(_ value: UInt32) -> String {
        let chars = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        return String(decoding: chars, as: UTF8.self)
    }

    /// GET_KEY_INFO (ukuran + tipe) lalu READ_BYTES.
    static func readKey(_ key: String, conn: io_connect_t) -> ReadResult? {
        guard let code = keyCode(key) else { return nil }

        var request = [UInt8](repeating: 0, count: structSize)
        // Kunci disimpan sebagai UInt32 NATIVE (nilai fourcc), bukan byte big-endian.
        storeUInt32(code, into: &request, at: offsetKey)
        request[offsetData8] = commandGetKeyInfo
        guard let info = call(request, conn: conn), info[offsetResult] == 0 else { return nil }
        let dataSize = Int(loadUInt32(info, at: offsetDataSize))
        let dataType = loadUInt32(info, at: offsetDataType)
        guard (1...32).contains(dataSize) else { return nil }

        storeUInt32(UInt32(dataSize), into: &request, at: offsetDataSize)
        storeUInt32(dataType, into: &request, at: offsetDataType)
        request[offsetData8] = commandReadBytes
        guard let value = call(request, conn: conn), value[offsetResult] == 0 else { return nil }
        return ReadResult(
            bytes: Array(value[offsetBytes..<offsetBytes + dataSize]),
            dataType: fourCC(dataType)
        )
    }

    /// Decode sesuai tipe: 'sp78' (Intel) atau 'flt ' (Apple Silicon,
    /// Float32 little-endian). Tipe lain = bukan sensor suhu yang kita kenal.
    static func decode(_ result: ReadResult) -> Double? {
        switch result.dataType {
        case "sp78": return decodeSP78(result.bytes)
        case "flt ": return decodeFloat(result.bytes)
        default: return nil
        }
    }

    public static func decodeFloat(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: raw))
        return value.isFinite ? value : nil
    }

    /// Decode 'sp78': 1 byte signed integer + 1 byte pecahan (1/256).
    /// Pure — diuji unit test.
    public static func decodeSP78(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let whole = Int8(bitPattern: bytes[0])
        return Double(whole) + Double(bytes[1]) / 256.0
    }

    /// Rentang suhu CPU yang masuk akal — di luar ini = sensor bukan suhu
    /// atau bacaan sampah.
    static func plausible(_ celsius: Double) -> Bool {
        (20.0...115.0).contains(celsius)
    }

    /// Kandidat pembacaan mentah — injectable buat unit test.
    /// Default: baca semua cpuKeys lewat koneksi SMC bersama.
    public static var rawReader: (String) -> Double? = { key in
        guard let conn = sharedConnection() else { return nil }
        guard let result = readKey(key, conn: conn) else { return nil }
        return decode(result)
    }

    /// Suhu CPU dalam °C — sensor tertinggi yang terbaca, atau nil kalau
    /// mesin ini tidak membuka sensornya (tampilkan thermalState saja).
    public static func cpuCelsius() -> Double? {
        var best: Double?
        for key in cpuKeys {
            if let value = rawReader(key), plausible(value) {
                if value > (best ?? -999) { best = value }
            }
        }
        return best
    }

    /// Buat unit test — kembalikan state pembaca ke default.
    public static func resetForTesting() {
        rawReader = { key in
            guard let conn = sharedConnection() else { return nil }
            guard let result = readKey(key, conn: conn) else { return nil }
            return decode(result)
        }
        resetConnection()
    }
}
