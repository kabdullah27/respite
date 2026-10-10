import Foundation
import SwiftUI

/// Pengelompokan modul di sidebar — per TUJUAN user, bukan per teknologi.
enum ModuleSection: String, CaseIterable, Identifiable {
    case cleaning = "Kosongkan Ruang"
    case monitoring = "Cek Kondisi Mac"
    case misc = "Alat Lain"
    case support = "Pengaturan & Dukungan"

    var id: String { rawValue }

    /// Nama section yang dilokalkan — rawValue cuma identity key.
    var title: String {
        NSLocalizedString(rawValue, comment: "Section sidebar")
    }

    /// Alat lanjutan dilipat default — pemula nggak perlu melihatnya.
    var isExpandedByDefault: Bool { self != .misc }
}

/// Urutan case = urutan di sidebar & Beranda.
enum Module: String, CaseIterable, Identifiable {
    case home
    // Kosongkan Ruang
    case smartScan
    case largeOldFiles
    case duplicateFinder
    case similarPhotos
    case appUninstaller
    case browserCleaner
    // Cek Kondisi Mac
    case diagnostic
    case memoryMonitor
    case thermalDetector
    case batteryHealth
    // Alat Lain (lanjutan)
    case devCacheCleanup
    case startupItems
    case shredder
    case keyboardLock
    case powerLid
    case settings
    case donation

    var id: String { rawValue }

    var section: ModuleSection {
        switch self {
        case .home, .diagnostic, .memoryMonitor, .thermalDetector, .batteryHealth:
            return .monitoring
        case .smartScan, .largeOldFiles, .duplicateFinder, .similarPhotos, .appUninstaller, .browserCleaner:
            return .cleaning
        case .devCacheCleanup, .startupItems, .shredder, .keyboardLock, .powerLid:
            return .misc
        case .settings, .donation:
            return .support
        }
    }

    /// Nama alat — kata sehari-hari, tanpa istilah teknis.
    var title: String {
        switch self {
        case .home: return NSLocalizedString("Beranda", comment: "")
        case .smartScan: return NSLocalizedString("Bersihkan Cepat", comment: "")
        case .largeOldFiles: return NSLocalizedString("File Besar", comment: "")
        case .duplicateFinder: return NSLocalizedString("File Ganda", comment: "")
        case .similarPhotos: return NSLocalizedString("Foto Mirip", comment: "")
        case .appUninstaller: return NSLocalizedString("Hapus Aplikasi", comment: "")
        case .browserCleaner: return NSLocalizedString("Data Browser", comment: "")
        case .diagnostic: return NSLocalizedString("Kenapa Mac Lambat?", comment: "")
        case .memoryMonitor: return NSLocalizedString("Aplikasi Berat", comment: "")
        case .thermalDetector: return NSLocalizedString("Suhu Mac", comment: "")
        case .batteryHealth: return NSLocalizedString("Baterai", comment: "")
        case .devCacheCleanup: return NSLocalizedString("Cache Developer", comment: "")
        case .startupItems: return NSLocalizedString("Aplikasi Saat Login", comment: "")
        case .shredder: return NSLocalizedString("Hapus Permanen", comment: "")
        case .keyboardLock: return NSLocalizedString("Kunci Keyboard", comment: "")
        case .powerLid: return NSLocalizedString("Nyala Saat Dibuka", comment: "")
        case .settings: return NSLocalizedString("Pengaturan", comment: "")
        case .donation: return NSLocalizedString("Dukung Respite", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .keyboardLock: return "keyboard"
        case .powerLid: return "laptopcomputer"
        case .smartScan: return "sparkles"
        case .appUninstaller: return "trash"
        case .largeOldFiles: return "doc.zipper"
        case .memoryMonitor: return "speedometer"
        case .diagnostic: return "questionmark.circle"
        case .thermalDetector: return "thermometer.medium"
        case .devCacheCleanup: return "hammer"
        case .shredder: return "flame"
        case .duplicateFinder: return "square.on.square"
        case .similarPhotos: return "photo.on.rectangle"
        case .batteryHealth: return "battery.100"
        case .startupItems: return "person.crop.circle.badge.clock"
        case .browserCleaner: return "globe"
        case .settings: return "gearshape"
        case .donation: return "heart"
        }
    }

    /// Satu kalimat di bawah judul halaman: alat ini buat apa.
    var summary: String {
        switch self {
        case .home:
            return NSLocalizedString("Kondisi Mac kamu dan cara cepat membersihkannya.", comment: "")
        case .smartScan:
            return NSLocalizedString("Hapus file sementara (cache dan log) yang aman dibuang. Aplikasi akan membuatnya lagi saat perlu.", comment: "")
        case .largeOldFiles:
            return NSLocalizedString("Cari file besar yang sudah lama tidak kamu buka.", comment: "")
        case .duplicateFinder:
            return NSLocalizedString("Cari file yang sama persis tapi tersimpan lebih dari sekali.", comment: "")
        case .similarPhotos:
            return NSLocalizedString("Cari foto yang hampir sama, misalnya hasil jepret beruntun atau hasil edit.", comment: "")
        case .appUninstaller:
            return NSLocalizedString("Hapus aplikasi sampai bersih, termasuk file sisa yang biasanya tertinggal.", comment: "")
        case .browserCleaner:
            return NSLocalizedString("Hapus cache, riwayat, atau cookie browser kamu.", comment: "")
        case .diagnostic:
            return NSLocalizedString("Lihat apa yang membuat Mac lambat sekarang, dijelaskan dengan bahasa sederhana.", comment: "")
        case .memoryMonitor:
            return NSLocalizedString("Lihat aplikasi yang paling banyak memakai memori dan tenaga prosesor, lalu tutup bila perlu.", comment: "")
        case .thermalDetector:
            return NSLocalizedString("Cek apakah Mac terlalu panas sehingga sengaja diperlambat.", comment: "")
        case .batteryHealth:
            return NSLocalizedString("Cek kondisi baterai: sisa kapasitas dan berapa kali sudah diisi ulang.", comment: "")
        case .devCacheCleanup:
            return NSLocalizedString("Untuk programmer: hapus file build dan unduhan dari Xcode, Homebrew, node_modules, dan sejenisnya.", comment: "")
        case .startupItems:
            return NSLocalizedString("Atur aplikasi yang otomatis berjalan saat kamu masuk ke Mac.", comment: "")
        case .shredder:
            return NSLocalizedString("Hapus file rahasia tanpa lewat Trash. Hati-hati: tidak bisa dibatalkan.", comment: "")
        case .keyboardLock:
            return NSLocalizedString("Matikan keyboard sebentar supaya aman saat dilap atau dibersihkan.", comment: "")
        case .powerLid:
            return NSLocalizedString("Atur apakah Mac langsung menyala saat layarnya dibuka.", comment: "")
        case .settings:
            return NSLocalizedString("Atur bahasa, pengecualian, riwayat, dan pembaruan Respite.", comment: "")
        case .donation:
            return NSLocalizedString("Respite gratis tanpa fitur terkunci. Donasi membantu pengembangannya.", comment: "")
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
        case .settings: return .gray
        case .donation: return .pink
        }
    }

    /// Versi pendek untuk daftar di Beranda.
    var shortDescription: String {
        switch self {
        case .home: return ""
        case .smartScan: return NSLocalizedString("Buang file sementara yang aman dihapus.", comment: "")
        case .largeOldFiles: return NSLocalizedString("Temukan file besar yang jarang dibuka.", comment: "")
        case .duplicateFinder: return NSLocalizedString("Temukan file yang tersimpan dua kali.", comment: "")
        case .similarPhotos: return NSLocalizedString("Temukan foto yang hampir sama.", comment: "")
        case .appUninstaller: return NSLocalizedString("Hapus aplikasi sampai ke sisa-sisanya.", comment: "")
        case .browserCleaner: return NSLocalizedString("Bersihkan cache dan riwayat browser.", comment: "")
        case .diagnostic: return NSLocalizedString("Cari tahu penyebab Mac lambat.", comment: "")
        case .memoryMonitor: return NSLocalizedString("Lihat dan tutup aplikasi yang berat.", comment: "")
        case .thermalDetector: return NSLocalizedString("Cek apakah Mac kepanasan.", comment: "")
        case .batteryHealth: return NSLocalizedString("Cek kesehatan baterai.", comment: "")
        case .devCacheCleanup: return NSLocalizedString("Bersihkan file build untuk programmer.", comment: "")
        case .startupItems: return NSLocalizedString("Atur aplikasi yang jalan saat login.", comment: "")
        case .shredder: return NSLocalizedString("Hapus file rahasia selamanya.", comment: "")
        case .keyboardLock: return NSLocalizedString("Kunci keyboard saat dibersihkan.", comment: "")
        case .powerLid: return NSLocalizedString("Atur Mac menyala saat dibuka.", comment: "")
        case .settings: return NSLocalizedString("Atur Respite sesuai keinginanmu.", comment: "")
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
