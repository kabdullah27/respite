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

    /// SMC_READ_KEY (selector 5): baca nilai + tipe data sebuah kunci.
    static func readKey(_ key: String, conn: io_connect_t) -> ReadResult? {
        guard let code = keyCode(key) else { return nil }

        // Layout input/output SMC yang dipakai osx-cpu-temp/Stats dst.
        var input = [UInt8](repeating: 0, count: 32)
        let be = code.bigEndian
        withUnsafeBytes(of: be) { input.replaceSubrange(0..<4, with: $0) }
        var output = [UInt8](repeating: 0, count: 32)
        var outputCount = 32

        let kr = input.withUnsafeMutableBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(
                    conn,
                    5, // kSMCReadKey
                    inPtr.baseAddress, 32,
                    outPtr.baseAddress, &outputCount
                )
            }
        }
        guard kr == KERN_SUCCESS, outputCount >= 6 else { return nil }

        // Output SMC: bytes 5..8 = data, 30 = status; tipe dari GET_KEY_INFO
        // tidak kita panggil — kunci suhu praktis selalu sp78, dan kita
        // validasi lewat rentang nilainya.
        let data = Array(output[5..<min(9, outputCount)])
        return ReadResult(bytes: data, dataType: "sp78")
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
        return decodeSP78(result.bytes)
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
            return decodeSP78(result.bytes)
        }
        resetConnection()
    }
}
