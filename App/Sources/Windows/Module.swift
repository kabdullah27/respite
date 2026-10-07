import Foundation
import SwiftUI

/// Pengelompokan modul di sidebar — biar nggak jadi list datar.
enum ModuleSection: String, CaseIterable, Identifiable {
    case cleaning = "Pembersihan"
    case monitoring = "Pemantauan"
    case misc = "Lainnya"
    case support = "Dukungan"

    var id: String { rawValue }

    /// Nama section yang dilokalkan — rawValue cuma identity key.
    var title: String {
        NSLocalizedString(rawValue, comment: "Section sidebar")
    }
}

/// Modul v0.1 sesuai PRD §4 (P0). Icon mapping dari Design Spec §4.
enum Module: String, CaseIterable, Identifiable {
    case home
    case keyboardLock
    case powerLid
    case smartScan
    case appUninstaller
    case largeOldFiles
    case memoryMonitor
    case diagnostic
    case thermalDetector
    case devCacheCleanup
    case shredder
    case duplicateFinder
    case similarPhotos
    case batteryHealth
    case startupItems
    case browserCleaner
    case donation

    var id: String { rawValue }

    var section: ModuleSection {
        switch self {
        case .home:
            return .monitoring
        case .smartScan, .appUninstaller, .largeOldFiles, .devCacheCleanup, .shredder, .duplicateFinder, .similarPhotos, .browserCleaner:
            return .cleaning
        case .memoryMonitor, .diagnostic, .thermalDetector, .batteryHealth, .startupItems:
            return .monitoring
        case .keyboardLock, .powerLid:
            return .misc
        case .donation:
            return .support
        }
    }

    var title: String {
        switch self {
        case .home: return NSLocalizedString("Beranda", comment: "")
        case .keyboardLock: return NSLocalizedString("Kunci Keyboard", comment: "")
        case .powerLid: return NSLocalizedString("Nyala saat dibuka", comment: "")
        case .smartScan: return NSLocalizedString("Pindai Cerdas", comment: "")
        case .appUninstaller: return NSLocalizedString("Copot Aplikasi", comment: "")
        case .largeOldFiles: return NSLocalizedString("File Besar & Lama", comment: "")
        case .memoryMonitor: return NSLocalizedString("Pemantau Memori", comment: "")
        case .diagnostic: return NSLocalizedString("Diagnosis Performa", comment: "")
        case .thermalDetector: return NSLocalizedString("Deteksi Suhu", comment: "")
        case .devCacheCleanup: return NSLocalizedString("Sisa Pengembang", comment: "")
        case .shredder: return NSLocalizedString("Penghancur File", comment: "")
        case .duplicateFinder: return NSLocalizedString("Pencari Duplikat", comment: "")
        case .similarPhotos: return NSLocalizedString("Foto Mirip", comment: "")
        case .batteryHealth: return NSLocalizedString("Kesehatan Baterai", comment: "")
        case .startupItems: return NSLocalizedString("Aplikasi Saat Login", comment: "")
        case .browserCleaner: return NSLocalizedString("Pembersih Peramban", comment: "")
        case .donation: return NSLocalizedString("Dukung Respite", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .keyboardLock: return "keyboard"
        case .powerLid: return "laptopcomputer"
        case .smartScan: return "tray.full"
        case .appUninstaller: return "trash"
        case .largeOldFiles: return "doc.badge.gearshape"
        case .memoryMonitor: return "memorychip"
        case .diagnostic: return "waveform.path.ecg"
        case .thermalDetector: return "thermometer.medium"
        case .devCacheCleanup: return "hammer"
        case .shredder: return "trash.slash"
        case .duplicateFinder: return "square.on.square"
        case .similarPhotos: return "photo.on.rectangle"
        case .batteryHealth: return "battery.100"
        case .startupItems: return "person.crop.circle.badge.clock"
        case .browserCleaner: return "globe"
        case .donation: return "heart"
        }
    }

    var summary: String {
        switch self {
        case .home:
            return NSLocalizedString("Tinjauan kondisi Mac dan pintasan ke semua alat.", comment: "")
        case .keyboardLock:
            return NSLocalizedString("Tahan semua ketukan keyboard selama layar kunci aktif.", comment: "")
        case .powerLid:
            return NSLocalizedString("Atur apakah Mac menyala sendiri saat lid dibuka.", comment: "")
        case .smartScan:
            return NSLocalizedString("Pindai cache, log, dan Trash — hasilnya dikelompokkan dan dijelaskan kenapa aman dihapus.", comment: "")
        case .appUninstaller:
            return NSLocalizedString("Hapus aplikasi beserta sisa datanya di Application Support, Caches, Preferences, dan LaunchAgents.", comment: "")
        case .largeOldFiles:
            return NSLocalizedString("Temukan file besar atau lama yang jarang dipakai — urutkan sesuai ukuran, tanggal, atau tipe.", comment: "")
        case .memoryMonitor:
            return NSLocalizedString("Pusat pantauan RAM, CPU, swap, dan uptime — plus Maintenance Sweep dan daftar proses yang bisa dihentikan.", comment: "")
        case .diagnostic:
            return NSLocalizedString("Analisis baca-saja untuk mencari akar masalah Mac lambat sekarang — dirangkum singkat plus Health Score 0–100.", comment: "")
        case .thermalDetector:
            return NSLocalizedString("Cek apakah kelambanan berasal dari panas berlebih (throttling) — bukan dari file sampah.", comment: "")
        case .devCacheCleanup:
            return NSLocalizedString("Bersihkan cache developer: Xcode DerivedData, simulator, CocoaPods/SPM, Docker, Homebrew, node_modules, sampai Cargo.", comment: "")
        case .shredder:
            return NSLocalizedString("Hapus permanen untuk file yang benar-benar sensitif — lewat konfirmasi berlapis. Semua modul lain tetap bisa dibatalkan lewat Trash.", comment: "")
        case .duplicateFinder:
            return NSLocalizedString("Temukan file duplikat persis (byte identik) — foto maupun non-foto — dengan perbandingan tiga fase yang cepat. Salinan terlama disarankan disimpan.", comment: "")
        case .similarPhotos:
            return NSLocalizedString("Temukan foto yang mirip secara visual — hasil edit, resize, atau rekaman ulang — dengan sidik jari ringan tanpa model ML.", comment: "")
        case .batteryHealth:
            return NSLocalizedString("Cycle count dan kapasitas baterai langsung dari IOKit — sepenuhnya baca-saja, disembunyikan otomatis di Mac desktop.", comment: "")
        case .startupItems:
            return NSLocalizedString("Daftar LaunchAgent/LaunchDaemon dengan asal-usul aplikasi pemiliknya — bukan sekadar nama file.", comment: "")
        case .browserCleaner:
            return NSLocalizedString("Bersihkan cache browser (Chrome, Arc, Brave, Edge, Firefox, Safari) — dibuat ulang otomatis, tanpa mengeluarkan kamu dari akun.", comment: "")
        case .donation:
            return NSLocalizedString("Respite gratis penuh tanpa fitur terkunci. Donasi menjaga pengembangannya berlanjut.", comment: "")
        }
    }

    /// Warna kategori untuk icon tile (gaya PureMac): tiap alat punya identitas
    /// warna sendiri, dipakai di sidebar, grid Beranda, dan ikon judul.
    var tintColor: Color {
        switch self {
        case .home: return .respite
        case .keyboardLock: return .mint
        case .powerLid: return .indigo
        case .smartScan: return .respite
        case .appUninstaller: return .blue
        case .largeOldFiles: return .indigo
        case .memoryMonitor: return .blue
        case .diagnostic: return .purple
        case .thermalDetector: return .orange
        case .devCacheCleanup: return Color(red: 0.55, green: 0.40, blue: 0.20)
        case .shredder: return .red
        case .duplicateFinder: return .purple
        case .similarPhotos: return .pink
        case .batteryHealth: return .green
        case .startupItems: return .teal
        case .browserCleaner: return .blue
        case .donation: return .pink
        }
    }

    /// Deskripsi satu-kalimat untuk kartu alat di Beranda — lebih pendek dari summary.
    var shortDescription: String {
        switch self {
        case .home: return ""
        case .keyboardLock: return NSLocalizedString("Kunci keyboard saat membersihkan layar.", comment: "")
        case .powerLid: return NSLocalizedString("Atur Mac menyala sendiri saat lid dibuka.", comment: "")
        case .smartScan: return NSLocalizedString("Pindai cache, log, dan Trash sekaligus.", comment: "")
        case .appUninstaller: return NSLocalizedString("Hapus aplikasi beserta sisa datanya.", comment: "")
        case .largeOldFiles: return NSLocalizedString("Temukan file besar atau lama yang jarang dipakai.", comment: "")
        case .memoryMonitor: return NSLocalizedString("Pantau RAM, CPU, swap, dan proses berat.", comment: "")
        case .diagnostic: return NSLocalizedString("Cari akar masalah Mac lambat sekarang.", comment: "")
        case .thermalDetector: return NSLocalizedString("Cek apakah panas membuat Mac melambat.", comment: "")
        case .devCacheCleanup: return NSLocalizedString("Bersihkan cache Xcode, Homebrew, Docker, dll.", comment: "")
        case .shredder: return NSLocalizedString("Hapus permanen untuk file sensitif.", comment: "")
        case .duplicateFinder: return NSLocalizedString("Temukan file duplikat yang identik byte.", comment: "")
        case .similarPhotos: return NSLocalizedString("Temukan foto mirip dari hasil edit.", comment: "")
        case .batteryHealth: return NSLocalizedString("Cycle count dan kesehatan baterai.", comment: "")
        case .startupItems: return NSLocalizedString("Kelola aplikasi yang jalan saat login.", comment: "")
        case .browserCleaner: return NSLocalizedString("Bersihkan cache semua browser.", comment: "")
        case .donation: return NSLocalizedString("Dukung pengembangan Respite.", comment: "")
        }
    }

    /// Icon tile warna-tint ala PureMac — dipakai sidebar & kartu Beranda.
    @ViewBuilder
    var iconTile: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tintColor)
            .frame(width: 26, height: 26)
            .background(tintColor.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
