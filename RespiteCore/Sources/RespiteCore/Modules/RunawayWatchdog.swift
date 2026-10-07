import Foundation

/// Satu sampel beban CPU sebuah grup proses pada satu tick.
public struct WatchdogSample: Sendable, Equatable {
    public let date: Date
    public let name: String
    public let fraction: Double

    public init(date: Date, name: String, fraction: Double) {
        self.date = date
        self.name = name
        self.fraction = fraction
    }
}

/// Verdict proses liar (TRD §4.11): CPU tinggi TERUS-MENERUS, bukan spike.
public struct RunawayVerdict: Sendable, Equatable, Identifiable {
    public let name: String
    public let sustainedMinutes: Double
    public let averageFraction: Double

    public var id: String { name }
}

public enum RunawayWatchdog {
    /// Pure — diuji unit test. Aturan: dalam window N menit terakhir,
    /// grup proses dengan rata-rata beban ≥ threshold DAN muncul di
    /// ≥ minCoverage porsi tick dianggap "liar" (sustain, bukan spike sesaat).
    public static func evaluate(
        history: [WatchdogSample],
        now: Date,
        windowMinutes: Double = 10,
        threshold: Double = 0.5,
        minCoverage: Double = 0.8,
        minTicks: Int = 5
    ) -> [RunawayVerdict] {
        let cutoff = now.addingTimeInterval(-windowMinutes * 60)
        let recent = history.filter { $0.date >= cutoff }
        let tickStamps = Set(recent.map { $0.date.timeIntervalSince1970 })
        guard tickStamps.count >= minTicks else { return [] }

        let tickCount = Double(tickStamps.count)
        // Klaim "sustain N menit" harus dibuktikan rentang data nyata:
        // span ≥ 60% window — data 1 menit tidak boleh diklaim 10 menit.
        let minSpan = windowMinutes * 60 * 0.6
        let byName = Dictionary(grouping: recent, by: \.name)

        return byName.compactMap { name, samples in
            let average = samples.map(\.fraction).reduce(0, +) / Double(samples.count)
            let coverage = Double(samples.count) / tickCount
            let span = (samples.map(\.date).max()!.timeIntervalSince(samples.map(\.date).min()!))
            guard average >= threshold, coverage >= minCoverage, span >= minSpan else { return nil }
            return RunawayVerdict(
                name: name,
                sustainedMinutes: span / 60,
                averageFraction: average
            )
        }
        .sorted { $0.averageFraction > $1.averageFraction }
    }
}
