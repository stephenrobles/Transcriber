import Combine
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let transcriberProject = UTType(exportedAs: "fm.beard.transcriber.project", conformingTo: .json)
}

/// A transcription project: a reference to the media file plus the transcript and its cues.
@Observable
final class TranscriptDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = ProjectFile

    nonisolated static var readableContentTypes: [UTType] { [.transcriberProject] }
    nonisolated static var writableContentTypes: [UTType] { [.transcriberProject] }

    var mediaURL: URL?
    var mediaFileName: String?
    var mediaDuration: TimeInterval = 0
    var transcript: Transcript?
    var cueSettings: CueSettings = .default
    /// True when the project was opened but its media file could not be found.
    var mediaMissing = false

    /// The run in progress (or the last one, until it is dismissed).
    var job: TranscriptionJob?

    init() {}

    init(mediaURL: URL) {
        self.mediaURL = mediaURL
        mediaFileName = mediaURL.lastPathComponent
    }

    nonisolated required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ProjectFile.self, from: data)
        mediaFileName = file.mediaFileName
        mediaDuration = file.mediaDuration
        transcript = file.transcript
        cueSettings = file.cueSettings

        var resolved: URL?
        if let bookmark = file.mediaBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                resolved = url
            }
        }
        if resolved == nil, let path = file.mediaPath, FileManager.default.fileExists(atPath: path) {
            resolved = URL(fileURLWithPath: path)
        }
        mediaURL = resolved
        mediaMissing = resolved == nil && (file.mediaBookmark != nil || file.mediaPath != nil)
    }

    func snapshot(contentType: UTType) throws -> ProjectFile {
        ProjectFile(mediaBookmark: try? mediaURL?.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                    mediaPath: mediaURL?.path,
                    mediaFileName: mediaFileName,
                    mediaDuration: mediaDuration,
                    transcript: transcript,
                    cueSettings: cueSettings)
    }

    nonisolated func fileWrapper(snapshot: ProjectFile, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }

    // MARK: - State

    var hasMedia: Bool { mediaURL != nil }
    var hasTranscript: Bool { transcript != nil }
    var cues: [Cue] { transcript?.cues ?? [] }
    var isTranscribing: Bool { job?.isRunning ?? false }

    /// A default file name for exports and the first save: the media name without its extension.
    var suggestedBaseName: String {
        if let mediaFileName { return (mediaFileName as NSString).deletingPathExtension }
        return "Transcript"
    }

    // MARK: - Media

    func attachMedia(_ url: URL, undoManager: UndoManager?) {
        let previous = mediaURL
        mediaURL = url
        mediaFileName = url.lastPathComponent
        mediaMissing = false
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.cancelTranscription()
            if let previous {
                doc.attachMedia(previous, undoManager: undoManager)
            } else {
                doc.detachMedia(undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Attach Media")
    }

    func detachMedia(undoManager: UndoManager?) {
        let previous = mediaURL
        cancelTranscription()
        mediaURL = nil
        mediaFileName = nil
        mediaMissing = false
        if let previous {
            undoManager?.registerUndo(withTarget: self) { doc in
                doc.attachMedia(previous, undoManager: undoManager)
            }
            undoManager?.setActionName("Attach Media")
        }
    }

    func relinkMedia(_ url: URL) {
        mediaURL = url
        mediaFileName = url.lastPathComponent
        mediaMissing = false
    }

    // MARK: - Transcription

    func startTranscription(locale: Locale, cueSettings: CueSettings, undoManager: UndoManager?) {
        guard let mediaURL, !isTranscribing else { return }
        let job = TranscriptionJob(locale: locale)
        self.job = job
        self.cueSettings = cueSettings
        job.start(url: mediaURL) { [weak self] words in
            guard let self else { return }
            let transcript = Transcript(words: words,
                                        cues: CueBuilder.cues(from: words, settings: cueSettings),
                                        localeIdentifier: locale.identifier,
                                        createdAt: Date())
            setTranscript(transcript, actionName: "Transcribe", undoManager: undoManager)
            self.job = nil
        }
    }

    func cancelTranscription() {
        job?.cancel()
        job = nil
    }

    func dismissJob() {
        job = nil
    }

    func setTranscript(_ new: Transcript?, actionName: String, undoManager: UndoManager?) {
        let old = transcript
        transcript = new
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.setTranscript(old, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    /// Regroups the original words into cues with new settings, discarding cue edits.
    func rebuildCues(settings: CueSettings, undoManager: UndoManager?) {
        guard let transcript else { return }
        cueSettings = settings
        var rebuilt = transcript
        rebuilt.cues = CueBuilder.cues(from: transcript.words, settings: settings)
        setTranscript(rebuilt, actionName: "Rebuild Cues", undoManager: undoManager)
    }

    // MARK: - Cue editing

    func setCues(_ new: [Cue], actionName: String, undoManager: UndoManager?) {
        guard var transcript else { return }
        let old = transcript.cues
        guard old != new else { return }
        transcript.cues = new
        self.transcript = transcript
        undoManager?.registerUndo(withTarget: self) { doc in
            doc.setCues(old, actionName: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    func updateText(of id: UUID, to text: String, undoManager: UndoManager?) {
        var cues = self.cues
        guard let index = cues.firstIndex(where: { $0.id == id }), cues[index].text != text else { return }
        cues[index].text = text
        setCues(cues, actionName: "Edit Cue", undoManager: undoManager)
    }

    func updateTiming(of id: UUID, start: TimeInterval?, end: TimeInterval?, undoManager: UndoManager?) {
        var cues = self.cues
        guard let index = cues.firstIndex(where: { $0.id == id }) else { return }
        if let start { cues[index].start = max(0, start) }
        if let end { cues[index].end = end }
        if cues[index].end <= cues[index].start { cues[index].end = cues[index].start + 0.5 }
        cues.sort { $0.start < $1.start }
        setCues(cues, actionName: "Retime Cue", undoManager: undoManager)
    }

    func mergeWithNext(_ id: UUID, undoManager: UndoManager?) {
        var cues = self.cues
        guard let index = cues.firstIndex(where: { $0.id == id }), index + 1 < cues.count else { return }
        let next = cues.remove(at: index + 1)
        cues[index].end = max(cues[index].end, next.end)
        cues[index].text = joinedText(cues[index].text, next.text)
        setCues(cues, actionName: "Merge Cues", undoManager: undoManager)
    }

    /// Splits a cue at a character offset. The split time comes from the original word timings when
    /// they still line up with the text, otherwise it is proportional to the character position.
    func split(_ id: UUID, at offset: Int, undoManager: UndoManager?) {
        var cues = self.cues
        guard let index = cues.firstIndex(where: { $0.id == id }) else { return }
        let cue = cues[index]
        let text = cue.text
        let clamped = max(0, min(offset, text.count))
        let splitIndex = text.index(text.startIndex, offsetBy: clamped)
        let head = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(text[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty, !tail.isEmpty else { return }

        let splitTime = splitTime(for: cue, headWordCount: head.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count,
                                  fraction: Double(head.count) / Double(max(text.count, 1)))
        cues[index] = Cue(id: cue.id, start: cue.start, end: splitTime, text: head)
        cues.insert(Cue(start: splitTime, end: cue.end, text: tail), at: index + 1)
        setCues(cues, actionName: "Split Cue", undoManager: undoManager)
    }

    func insertCue(after id: UUID?, undoManager: UndoManager?) -> UUID {
        var cues = self.cues
        let new: Cue
        if let id, let index = cues.firstIndex(where: { $0.id == id }) {
            let previous = cues[index]
            let nextStart = index + 1 < cues.count ? cues[index + 1].start : previous.end + 2
            new = Cue(start: previous.end, end: min(previous.end + 2, max(nextStart, previous.end + 0.5)), text: "")
            cues.insert(new, at: index + 1)
        } else {
            let start = cues.first.map { max(0, $0.start - 2) } ?? 0
            new = Cue(start: start, end: start + 2, text: "")
            cues.insert(new, at: 0)
        }
        setCues(cues, actionName: "Insert Cue", undoManager: undoManager)
        return new.id
    }

    func delete(_ ids: Set<UUID>, undoManager: UndoManager?) {
        guard !ids.isEmpty else { return }
        setCues(cues.filter { !ids.contains($0.id) }, actionName: ids.count == 1 ? "Delete Cue" : "Delete Cues", undoManager: undoManager)
    }

    private func joinedText(_ a: String, _ b: String) -> String {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }

    private func splitTime(for cue: Cue, headWordCount: Int, fraction: Double) -> TimeInterval {
        let proportional = cue.start + cue.duration * fraction
        guard let words = transcript?.words else { return proportional }
        let inRange = words.filter { $0.start >= cue.start - 0.05 && $0.end <= cue.end + 0.05 }
        let cueWordCount = cue.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // Only trust word timings when the cue still has as many words as the engine produced.
        guard inRange.count == cueWordCount, headWordCount < inRange.count, headWordCount > 0 else { return proportional }
        let boundary = (inRange[headWordCount - 1].end + inRange[headWordCount].start) / 2
        return min(max(boundary, cue.start + 0.1), cue.end - 0.1)
    }
}
