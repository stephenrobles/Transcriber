import Foundation

nonisolated enum TimeFormat {
    private static func parts(_ time: TimeInterval) -> (h: Int, m: Int, s: Int, ms: Int) {
        let total = max(0, time)
        let ms = Int((total * 1000).rounded())
        return (ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// `HH:MM:SS,mmm` as SubRip wants it.
    static func srt(_ time: TimeInterval) -> String {
        let p = parts(time)
        return String(format: "%02d:%02d:%02d,%03d", p.h, p.m, p.s, p.ms)
    }

    /// `HH:MM:SS.mmm` for WebVTT.
    static func vtt(_ time: TimeInterval) -> String {
        let p = parts(time)
        return String(format: "%02d:%02d:%02d.%03d", p.h, p.m, p.s, p.ms)
    }

    /// `M:SS` or `H:MM:SS` for transport controls and bracketed timestamps.
    static func clock(_ time: TimeInterval, forceHours: Bool = false) -> String {
        let total = Int(max(0, time).rounded(.down))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        if h > 0 || forceHours { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// `M:SS.t` with tenths, used on cue rows; hours appear only when needed.
    static func cue(_ time: TimeInterval, forceHours: Bool = false) -> String {
        let p = parts(time)
        let tenths = p.ms / 100
        if p.h > 0 || forceHours { return String(format: "%d:%02d:%02d.%d", p.h, p.m, p.s, tenths) }
        return String(format: "%d:%02d.%d", p.m, p.s, tenths)
    }

    /// `H:MM:SS.mmm` for editing fields.
    static func precise(_ time: TimeInterval) -> String {
        let p = parts(time)
        return String(format: "%d:%02d:%02d.%03d", p.h, p.m, p.s, p.ms)
    }

    /// Accepts `SS`, `M:SS`, `H:MM:SS`, each with an optional fraction (`.5`, `,250`).
    static func parse(_ string: String) -> TimeInterval? {
        let cleaned = string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let pieces = cleaned.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count <= 3 else { return nil }
        var total: TimeInterval = 0
        for (index, piece) in pieces.enumerated() {
            guard let value = Double(piece), value >= 0 else { return nil }
            let isLast = index == pieces.count - 1
            if !isLast, value != value.rounded() { return nil }
            total = total * 60 + value
        }
        return total
    }
}
