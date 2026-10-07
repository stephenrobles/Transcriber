import Foundation

/// Groups recognized words into subtitle cues and wraps cue text into lines.
nonisolated enum CueBuilder {
    static let minimumCueDuration: TimeInterval = 1.0

    static func cues(from words: [TranscriptWord], settings: CueSettings) -> [Cue] {
        var cues: [Cue] = []
        var current: [TranscriptWord] = []
        let lineLimit = max(settings.maxCharactersPerLine, 8)
        let maxLines = max(settings.maxLines, 1)

        func flush(_ group: [TranscriptWord]) {
            guard let first = group.first, let last = group.last else { return }
            let text = group.map(\.text).joined(separator: " ")
            cues.append(Cue(start: first.start, end: max(last.end, first.start + 0.3), text: text))
        }

        /// Whether `group` wraps into the allowed number of lines.
        func fits(_ group: [TranscriptWord]) -> Bool {
            var lines = 1
            var lineLength = 0
            for word in group {
                if lineLength == 0 {
                    lineLength = word.text.count
                } else if lineLength + 1 + word.text.count <= lineLimit {
                    lineLength += 1 + word.text.count
                } else {
                    lines += 1
                    lineLength = word.text.count
                }
            }
            return lines <= maxLines
        }

        /// When a cue has to end because it is full, prefer ending it at the last comma or full stop
        /// in its second half rather than mid-phrase; the words after that boundary start the next cue.
        func splitPoint(_ group: [TranscriptWord]) -> Int? {
            guard group.count >= 4 else { return nil }
            for i in stride(from: group.count - 1, through: 2, by: -1) where group.count - i <= group.count / 2 {
                let previous = group[i - 1].text
                if endsSentence(previous) || endsClause(previous) { return i }
            }
            return nil
        }

        func characterCount(_ group: [TranscriptWord]) -> Int {
            group.reduce(0) { $0 + $1.text.count } + max(group.count - 1, 0)
        }

        for word in words where !word.text.isEmpty {
            if let last = current.last, let first = current.first {
                let gap = word.start - last.end
                let length = characterCount(current)
                if gap >= settings.pauseBreak {
                    flush(current)
                    current = []
                } else if endsSentence(last.text), length >= min(20, lineLimit / 2) {
                    flush(current)
                    current = []
                } else if endsClause(last.text), length >= lineLimit * maxLines * 3 / 5 {
                    flush(current)
                    current = []
                } else if !fits(current + [word]) || word.end - first.start > settings.maxDuration {
                    if let point = splitPoint(current) {
                        flush(Array(current[..<point]))
                        current = Array(current[point...])
                    } else {
                        flush(current)
                        current = []
                    }
                }
            }
            current.append(word)
        }
        flush(current)
        return normalized(cues)
    }

    /// Gives short cues a readable minimum duration and keeps cues from overlapping.
    static func normalized(_ input: [Cue]) -> [Cue] {
        var cues = input.sorted { $0.start < $1.start }
        for i in cues.indices {
            if cues[i].end < cues[i].start + minimumCueDuration {
                cues[i].end = cues[i].start + minimumCueDuration
            }
            if i + 1 < cues.count {
                let limit = cues[i + 1].start - 0.001
                if cues[i].end > limit { cues[i].end = max(limit, cues[i].start + 0.2) }
            }
        }
        return cues
    }

    static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last(where: { !$0.isPunctuation || ".?!…".contains($0) }) else { return false }
        return ".?!…".contains(last)
    }

    static func endsClause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ",;:—–".contains(last)
    }

    /// Wraps cue text to at most `maxCharactersPerLine` per line, balancing two lines when the
    /// text needs more than one. Explicit newlines typed by the user are kept as-is.
    static func wrap(_ text: String, settings: CueSettings) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("\n") {
            return trimmed.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let limit = max(settings.maxCharactersPerLine, 8)
        if trimmed.count <= limit { return [trimmed] }

        let words = trimmed.split(separator: " ").map(String.init)
        if trimmed.count <= limit * 2 {
            // Best two-line split: both halves fit, lengths as even as possible.
            var best: (diff: Int, lines: [String])?
            for i in 1..<words.count {
                let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
                guard a.count <= limit, b.count <= limit else { continue }
                let diff = abs(a.count - b.count)
                if best == nil || diff < best!.diff { best = (diff, [a, b]) }
            }
            if let best { return best.lines }
        }
        // Greedy fallback for long cues.
        var lines: [String] = []
        var line = ""
        for word in words {
            if line.isEmpty { line = word }
            else if line.count + 1 + word.count <= limit { line += " " + word }
            else { lines.append(line); line = word }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
