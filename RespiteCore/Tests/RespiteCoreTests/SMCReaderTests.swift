import XCTest
@testable import RespiteCore

/// SMCReader — decode & logika murni; koneksi beneran tidak disentuh tes.
final class SMCReaderTests: XCTestCase {
    override func tearDown() {
        SMCReader.resetForTesting()
        super.tearDown()
    }

    /// sp78: byte signed + byte pecahan 1/256.
    func testDecodeSP78() {
        XCTAssertEqual(SMCReader.decodeSP78([62, 128]) ?? 0, 62.5, accuracy: 0.01)
        XCTAssertEqual(SMCReader.decodeSP78([45, 0]) ?? 0, 45.0, accuracy: 0.01)
        XCTAssertEqual(SMCReader.decodeSP78([100, 255]) ?? 0, 100.996, accuracy: 0.01)
        XCTAssertNil(SMCReader.decodeSP78([62]), "kurang dari 2 byte = tidak valid")
    }

    /// 'flt ' Apple Silicon: Float32 little-endian (sampel nyata M-series).
    func testDecodeFloat() {
        XCTAssertEqual(SMCReader.decodeFloat([210, 240, 126, 66]) ?? 0, 63.735, accuracy: 0.01)
        XCTAssertEqual(SMCReader.fourCC(SMCReader.keyCode("flt ")!), "flt ")
        XCTAssertNil(SMCReader.decodeFloat([1, 2]))
    }

    /// Kunci jadi 4-char code big-endian.
    func testKeyCode() {
        XCTAssertEqual(SMCReader.keyCode("TC0P"), 0x54433050)
        XCTAssertNil(SMCReader.keyCode("terlalu panjang"), "kunci harus 4 karakter")
    }

    /// Bacaan di luar rentang wajar dibuang (bukan sensor suhu / sampah).
    func testNilaiTakWajarDibuang() {
        SMCReader.rawReader = { key in
            key == "TC0P" ? 180.0 : (key == "TC0D" ? 61.0 : nil)
        }
        XCTAssertEqual(SMCReader.cpuCelsius() ?? 0, 61.0, accuracy: 0.01)
    }

    /// Sensor tertinggi yang dipakai, bukan rata-rata.
    func testSensorTertinggiYangDipakai() {
        SMCReader.rawReader = { key in
            switch key {
            case "TC0P": return 55.0
            case "TC0D": return 72.5
            case "TC0E": return 68.0
            default: return nil
            }
        }
        XCTAssertEqual(SMCReader.cpuCelsius() ?? 0, 72.5, accuracy: 0.01)
    }

    /// Semua sensor tidak terbaca → nil (UI fallback ke thermalState).
    func testTidakAdaSensor() {
        SMCReader.rawReader = { _ in nil }
        XCTAssertNil(SMCReader.cpuCelsius())
    }
}
