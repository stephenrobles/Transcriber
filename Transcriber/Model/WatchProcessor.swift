import AVFoundation
import Foundation

/// What Transcriber does with a file that lands in a watched folder: transcribe it and write the
/// outputs chosen in Settings next to it. Returns the first file written, for the notification.
@MainActor
enum WatchProcessor {
    static func accepts(_ url: URL) -> Bool {
        PendingMedia.isMedia(url)
    }

    static func transcribe(_ url: URL) async throws -> URL? {
        let settings = AppSettings.shared
        let locale = settings.locale
        let cueSettings = settings.cueSettings
        var words: [TranscriptWord] = []
        for try await event in TranscriptionEngine.transcribe(url: url, locale: locale) {
            if case .words(let new) = event { words.append(contentsOf: new) }
        }
        let cues = CueBuilder.cues(from: words, settings: cueSettings)
        let base = url.deletingPathExtension()
        let title = base.lastPathComponent
        var first: URL?

        for format in ExportFormat.allCases where settings.watchFormats.contains(format.rawValue) {
            let text = TranscriptExporter.export(cues, as: format, title: title, cueSettings: cueSettings, paragraphGap: settings.paragraphGap)
            let target = uniqueURL(base: base, ext: format.fileExtension)
            try text.write(to: target, atomically: true, encoding: .utf8)
            first = first ?? target
        }

        if settings.watchSavesProject {
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            let file = ProjectFile(mediaBookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                                   mediaPath: url.path,
                                   mediaFileName: url.lastPathComponent,
                                   mediaDuration: duration,
                                   transcript: Transcript(words: words, cues: cues, localeIdentifier: locale.identifier, createdAt: Date()),
                                   cueSettings: cueSettings)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let target = uniqueURL(base: base, ext: "transcriber")
            try encoder.encode(file).write(to: target, options: .atomic)
            first = first ?? target
        }
        return first
    }

    /// `Talk.srt`, or `Talk 2.srt` if that already exists: nothing the user made gets overwritten.
    private static func uniqueURL(base: URL, ext: String) -> URL {
        var candidate = base.appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent) \(n)")
                .appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
