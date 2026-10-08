import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Everything the menus need from the front document window.
@MainActor
struct DocumentContext {
    let document: TranscriptDocument
    let state: EditorState
    let player: PlayerController
    let undoManager: UndoManager?
    let attachMedia: (URL) -> Void
}

struct DocumentContextKey: FocusedValueKey {
    typealias Value = DocumentContext
}

extension FocusedValues {
    var documentContext: DocumentContext? {
        get { self[DocumentContextKey.self] }
        set { self[DocumentContextKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let updater: AppUpdater
    @FocusedValue(\.documentContext) private var context
    @Environment(\.newDocument) private var newDocument

    private var settings: AppSettings { AppSettings.shared }
    private var hasTranscript: Bool { context?.document.hasTranscript ?? false }
    private var hasMedia: Bool { context?.document.hasMedia ?? false }
    private var canEdit: Bool { hasTranscript && !(context?.document.isTranscribing ?? false) }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }

        CommandGroup(after: .newItem) {
            Button("Open Media…") { openMedia() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .saveItem) {
            Menu("Export") {
                ForEach(ExportFormat.allCases) { format in
                    Button("\(format.title)…") { export(format) }
                        .keyboardShortcut(format == .srt ? KeyboardShortcut("e") : nil)
                }
            }
            .disabled(!hasTranscript)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find…") { context?.state.showFind() }
                .keyboardShortcut("f")
                .disabled(!hasTranscript)
            Button("Find and Replace…") { context?.state.showFind(focusReplace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!hasTranscript)
            Button("Find Next") { if let context { context.state.step(1, in: context.document.cues) } }
                .keyboardShortcut("g")
                .disabled(!hasTranscript)
            Button("Find Previous") { if let context { context.state.step(-1, in: context.document.cues) } }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!hasTranscript)
        }

        CommandMenu("Transcript") {
            Button("Transcribe Again…") { retranscribe() }
                .disabled(!hasMedia || (context?.document.isTranscribing ?? false))
            Button("Rebuild Cues from Settings…") { rebuildCues() }
                .disabled(!canEdit)
            Divider()
            Button("Split Cue at Cursor") { splitCue() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canEdit || context?.state.editingCueID == nil)
            Button("Merge with Next Cue") { mergeCue() }
                .keyboardShortcut("m", modifiers: [.command, .control])
                .disabled(!canEdit || (context?.state.selection.count ?? 0) != 1)
            Button("Insert Cue After") { insertCue() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!canEdit)
            Button("Delete Cue") { deleteCues() }
                .disabled(!canEdit || (context?.state.selection.isEmpty ?? true))
            Divider()
            Button("Jump to Current Cue") { jumpToCurrentCue() }
                .keyboardShortcut("j")
                .disabled(!canEdit)
        }

        CommandMenu("Playback") {
            Button(context?.player.isPlaying == true ? "Pause" : "Play") { context?.player.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [.option])
                .disabled(!(context?.player.isLoaded ?? false))
            Button("Skip Back 5 Seconds") { context?.player.skip(by: -5) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!(context?.player.isLoaded ?? false))
            Button("Skip Forward 5 Seconds") { context?.player.skip(by: 5) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!(context?.player.isLoaded ?? false))
            Divider()
            Picker("Speed", selection: Binding(get: { context?.player.rate ?? 1 }, set: { context?.player.rate = $0 })) {
                Text("0.75×").tag(Float(0.75))
                Text("1×").tag(Float(1))
                Text("1.25×").tag(Float(1.25))
                Text("1.5×").tag(Float(1.5))
                Text("2×").tag(Float(2))
            }
            .pickerStyle(.inline)
        }

        CommandGroup(after: .toolbar) {
            Picker("View", selection: Binding(get: { context?.state.tab ?? .cues }, set: { context?.state.tab = $0 })) {
                Text("Cues").tag(EditorState.Tab.cues).keyboardShortcut("1")
                Text("Text").tag(EditorState.Tab.text).keyboardShortcut("2")
            }
            .pickerStyle(.inline)
            .disabled(!hasTranscript)
            Toggle("Follow Playback", isOn: Binding(get: { settings.followPlayback }, set: { settings.followPlayback = $0 }))
            Divider()
        }
    }

    // MARK: - Actions

    private func openMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = PendingMedia.acceptedTypes
        panel.message = "Choose a video or audio file to transcribe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let context, !context.document.hasMedia {
            context.attachMedia(url)
        } else {
            newDocument { TranscriptDocument(mediaURL: url) }
        }
    }

    private func export(_ format: ExportFormat) {
        guard let context else { return }
        ExportPanel.run(document: context.document, format: format)
    }

    private func retranscribe() {
        guard let context else { return }
        if context.document.hasTranscript {
            let alert = NSAlert()
            alert.messageText = "Transcribe this file again?"
            alert.informativeText = "The current transcript and any edits will be replaced. You can undo this."
            alert.addButton(withTitle: "Transcribe Again")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        context.document.startTranscription(locale: settings.locale, cueSettings: settings.cueSettings, undoManager: context.undoManager)
    }

    private func rebuildCues() {
        guard let context else { return }
        let alert = NSAlert()
        alert.messageText = "Rebuild cues from the subtitle settings?"
        alert.informativeText = "Cues are regrouped from the original transcription using the limits in Settings. Text edits, splits and merges are discarded. You can undo this."
        alert.addButton(withTitle: "Rebuild")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        context.document.rebuildCues(settings: settings.cueSettings, undoManager: context.undoManager)
    }

    private func splitCue() {
        guard let context, let id = context.state.editingCueID, let offset = context.state.editingCursorOffset else { return }
        context.state.pendingSplit = (id, offset)
    }

    private func mergeCue() {
        guard let context, let id = context.state.selection.first else { return }
        context.document.mergeWithNext(id, undoManager: context.undoManager)
    }

    private func insertCue() {
        guard let context else { return }
        let anchor = context.state.selection.count == 1 ? context.state.selection.first : context.document.cues.last?.id
        let id = context.document.insertCue(after: anchor, undoManager: context.undoManager)
        context.state.selection = [id]
        context.state.editingCueID = id
        context.state.scroll(to: id)
    }

    private func deleteCues() {
        guard let context else { return }
        context.document.delete(context.state.selection, undoManager: context.undoManager)
        context.state.selection = []
    }

    private func jumpToCurrentCue() {
        guard let context, let transcript = context.document.transcript,
              let index = transcript.cueIndex(at: context.player.currentTime) else { return }
        let id = transcript.cues[index].id
        context.state.selection = [id]
        context.state.scroll(to: id)
    }
}

enum ExportPanel {
    @MainActor
    static func run(document: TranscriptDocument, format: ExportFormat) {
        let settings = AppSettings.shared
        if format.isGenerated, let problem = SoapNoteGenerator.availabilityProblem() {
            let alert = NSAlert()
            alert.messageText = "Can't write a SOAP note"
            alert.informativeText = problem
            alert.runModal()
            return
        }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.suggestedBaseName + format.fileSuffix + "." + format.fileExtension
        panel.directoryURL = document.mediaURL?.deletingLastPathComponent()
        panel.title = "Export \(format.title)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let title = document.suggestedBaseName
        let cues = document.cues
        let cueSettings = document.cueSettings
        let paragraphGap = settings.paragraphGap
        if format.isGenerated {
            let transcript = TranscriptExporter.plainText(cues, paragraphGap: paragraphGap)
            GenerationProgressSheet.run(title: "Writing SOAP note…") { status in
                try await SoapNoteGenerator.generate(transcript: transcript, title: title, status: status)
            } completion: { result in
                switch result {
                case .success(let note):
                    do { try note.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
                case .failure(let error):
                    if error is CancellationError { return }
                    let alert = NSAlert()
                    alert.messageText = "Couldn't write the SOAP note"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
            return
        }
        let text = TranscriptExporter.export(cues, as: format, title: title, cueSettings: cueSettings, paragraphGap: paragraphGap)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
