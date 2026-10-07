import Foundation

/// One recognized word (or token) with the time it was spoken. The raw engine output is kept
/// so cues can be rebuilt with different subtitle settings without transcribing again.
nonisolated struct TranscriptWord: Codable, Hashable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// A subtitle cue: a stretch of text shown from `start` to `end`.
nonisolated struct Cue: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    var duration: TimeInterval { end - start }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}

nonisolated struct Transcript: Codable, Hashable, Sendable {
    var words: [TranscriptWord]
    var cues: [Cue]
    var localeIdentifier: String
    var createdAt: Date

    /// Index of the cue being spoken at `time`, or the last cue that started before it.
    func cueIndex(at time: TimeInterval) -> Int? {
        guard !cues.isEmpty else { return nil }
        var low = 0, high = cues.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cues[mid].start <= time { low = mid } else { high = mid - 1 }
        }
        return cues[low].start <= time ? low : nil
    }
}

/// How words are grouped into cues and how cue text is wrapped on export.
nonisolated struct CueSettings: Codable, Hashable, Sendable {
    var maxCharactersPerLine: Int = 42
    var maxLines: Int = 2
    var maxDuration: TimeInterval = 6
    var pauseBreak: TimeInterval = 1.0

    static let `default` = CueSettings()

    var maxCharacters: Int { maxCharactersPerLine * maxLines }
}

/// The on-disk `.transcriber` document: JSON, so it stays readable and diffable.
nonisolated struct ProjectFile: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = ProjectFile.currentVersion
    var mediaBookmark: Data?
    var mediaPath: String?
    var mediaFileName: String?
    var mediaDuration: TimeInterval = 0
    var transcript: Transcript?
    var cueSettings: CueSettings = .default
}
