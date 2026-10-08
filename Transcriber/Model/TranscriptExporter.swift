import Foundation

nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case srt, vtt, text, timestampedText, markdown, soap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .srt: "SRT Subtitles"
        case .vtt: "WebVTT Subtitles"
        case .text: "Plain Text"
        case .timestampedText: "Text with Timestamps"
        case .markdown: "Markdown"
        case .soap: "SOAP Note (Markdown)"
        }
    }

    /// Added to the media's name so the note doesn't collide with the Markdown transcript.
    var fileSuffix: String {
        self == .soap ? " SOAP" : ""
    }

    /// Written by Apple's on-device model rather than converted from the cues.
    var isGenerated: Bool {
        self == .soap
    }

    var fileExtension: String {
        switch self {
        case .srt: "srt"
        case .vtt: "vtt"
        case .text, .timestampedText: "txt"
        case .markdown, .soap: "md"
        }
    }
}

nonisolated enum TranscriptExporter {
    static func export(_ cues: [Cue], as format: ExportFormat, title: String, cueSettings: CueSettings, paragraphGap: TimeInterval) -> String {
        switch format {
        case .srt: srt(cues, settings: cueSettings)
        case .vtt: vtt(cues, settings: cueSettings)
        case .text: plainText(cues, paragraphGap: paragraphGap)
        case .timestampedText: timestampedText(cues, paragraphGap: paragraphGap)
        case .markdown: markdown(cues, title: title, paragraphGap: paragraphGap)
        case .soap: plainText(cues, paragraphGap: paragraphGap) // the generator's input; see SoapNoteGenerator
        }
    }

    static func srt(_ cues: [Cue], settings: CueSettings) -> String {
        var out = ""
        for (index, cue) in CueBuilder.normalized(cues).enumerated() where !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "\(index + 1)\n"
            out += "\(TimeFormat.srt(cue.start)) --> \(TimeFormat.srt(cue.end))\n"
            out += CueBuilder.wrap(cue.text, settings: settings).joined(separator: "\n")
            out += "\n\n"
        }
        return out
    }

    static func vtt(_ cues: [Cue], settings: CueSettings) -> String {
        var out = "WEBVTT\n\n"
        for (index, cue) in CueBuilder.normalized(cues).enumerated() where !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "\(index + 1)\n"
            out += "\(TimeFormat.vtt(cue.start)) --> \(TimeFormat.vtt(cue.end))\n"
            out += CueBuilder.wrap(cue.text, settings: settings).joined(separator: "\n")
            out += "\n\n"
        }
        return out
    }

    static func plainText(_ cues: [Cue], paragraphGap: TimeInterval) -> String {
        paragraphs(from: cues, gap: paragraphGap).map(\.text).joined(separator: "\n\n") + "\n"
    }

    static func timestampedText(_ cues: [Cue], paragraphGap: TimeInterval) -> String {
        let paragraphs = paragraphs(from: cues, gap: paragraphGap)
        let hours = (paragraphs.last?.start ?? 0) >= 3600
        return paragraphs.map { "[\(TimeFormat.clock($0.start, forceHours: hours))] \($0.text)" }.joined(separator: "\n\n") + "\n"
    }

    /// A heading with the media name, then one paragraph per pause with its timestamp in bold.
    static func markdown(_ cues: [Cue], title: String, paragraphGap: TimeInterval) -> String {
        let paragraphs = paragraphs(from: cues, gap: paragraphGap)
        let hours = (paragraphs.last?.start ?? 0) >= 3600
        var out = ""
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heading.isEmpty { out += "# \(heading)\n\n" }
        out += paragraphs.map { "**\(TimeFormat.clock($0.start, forceHours: hours))** \(escapeMarkdown($0.text))" }.joined(separator: "\n\n")
        return out + "\n"
    }

    /// Keeps spoken text from being read as Markdown syntax (a sentence starting with "#" or "*", for example).
    private static func escapeMarkdown(_ text: String) -> String {
        var result = text
        for character in ["*", "_", "#", "`", "[", "]", "<", ">"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result
    }

    struct Paragraph: Sendable {
        var start: TimeInterval
        var text: String
    }

    /// Joins cues into paragraphs: a new one starts after a pause at the end of a sentence,
    /// after a long pause anywhere, or when a paragraph has grown long and a sentence just ended.
    static func paragraphs(from cues: [Cue], gap: TimeInterval) -> [Paragraph] {
        var result: [Paragraph] = []
        var current: Paragraph?
        var previous: Cue?
        for cue in cues {
            let text = cue.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if var paragraph = current, let prev = previous {
                let pause = cue.start - prev.end
                let sentenceEnded = CueBuilder.endsSentence(prev.text)
                let split = (pause >= gap && sentenceEnded) || pause >= gap * 2.5 || (paragraph.text.count > 700 && sentenceEnded)
                if split {
                    result.append(paragraph)
                    current = Paragraph(start: cue.start, text: text)
                } else {
                    paragraph.text += " " + text
                    current = paragraph
                }
            } else {
                current = Paragraph(start: cue.start, text: text)
            }
            previous = cue
        }
        if let current { result.append(current) }
        return result
    }
}
