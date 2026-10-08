import SwiftUI

/// Player on top, then the cue list or the plain-text view, with a status bar underneath.
struct EditorView: View {
    let document: TranscriptDocument
    @Bindable var state: EditorState
    let player: PlayerController
    @Environment(\.undoManager) private var undoManager
    @State private var pendingLanguage: String?

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 0) {
            if document.hasMedia, player.isLoaded {
                PlayerView(player: player)
                Divider()
            } else if document.mediaMissing {
                MissingMediaBanner(document: document)
                Divider()
            }
            if state.findVisible {
                FindReplaceBar(document: document, state: state)
                Divider()
            }
            switch state.tab {
            case .cues:
                CueListView(document: document, state: state, player: player)
            case .text:
                FullTextView(document: document, state: state)
            }
            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                tabButton(.cues)
            }
            ToolbarItem(placement: .principal) {
                tabButton(.text)
            }
            ToolbarItemGroup {
                Button {
                    if state.findVisible { state.hideFind() } else { state.showFind() }
                } label: {
                    Label("Find & Replace", systemImage: "magnifyingglass")
                }
                .help("Find & Replace (⌘F)")
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button("\(format.title)…") { ExportPanel.run(document: document, format: format) }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export the transcript")
            }
        }
    }

    private func tabButton(_ tab: EditorState.Tab) -> some View {
        Toggle(isOn: Binding(get: { state.tab == tab }, set: { if $0 { state.tab = tab } })) {
            Text(tab.title)
                .frame(minWidth: 44)
        }
        .toggleStyle(.button)
        .help(tab == .cues ? "Timestamped cues (⌘1)" : "Plain text (⌘2)")
    }

    /// The transcript's language; picking another one transcribes the file again in it.
    private func languageMenu(current: String) -> some View {
        Menu {
            ForEach(LanguageCatalog.shared.supported, id: \.identifier) { locale in
                Button {
                    if locale.identifier != current { pendingLanguage = locale.identifier }
                } label: {
                    if locale.identifier == current {
                        Label(LanguageCatalog.name(locale), systemImage: "checkmark")
                    } else {
                        Text(LanguageCatalog.name(locale))
                    }
                }
            }
        } label: {
            Text(LanguageCatalog.name(Locale(identifier: current)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Spoken language. Choosing another transcribes the file again.")
        .onAppear { LanguageCatalog.shared.load() }
        .confirmationDialog("Transcribe again in \(LanguageCatalog.name(Locale(identifier: pendingLanguage ?? current)))?",
                            isPresented: Binding(get: { pendingLanguage != nil }, set: { if !$0 { pendingLanguage = nil } })) {
            Button("Transcribe Again") {
                if let identifier = pendingLanguage {
                    settings.localeIdentifier = identifier
                    document.startTranscription(locale: Locale(identifier: identifier), cueSettings: settings.cueSettings, undoManager: undoManager)
                }
                pendingLanguage = nil
            }
            Button("Cancel", role: .cancel) { pendingLanguage = nil }
        } message: {
            Text("The current transcript and any edits are replaced. You can undo this. The language also becomes the default for new files.")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            if let transcript = document.transcript {
                languageMenu(current: transcript.localeIdentifier)
                Text("\(transcript.cues.count) cues")
                Text("\(transcript.words.count) words")
            }
            if player.duration > 0 {
                Text(TimeFormat.clock(player.duration))
            }
            Spacer()
            if state.tab == .cues {
                Text("Click a cue's text to edit it. ⌘↩ splits at the cursor.")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct MissingMediaBanner: View {
    let document: TranscriptDocument

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("The media file \"\(document.mediaFileName ?? "")\" wasn't found, so playback is off. Editing and export still work.")
                .lineLimit(2)
            Spacer()
            Button("Locate…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = PendingMedia.acceptedTypes
                panel.message = "Find \(document.mediaFileName ?? "the media file")."
                if panel.runModal() == .OK, let url = panel.url { document.relinkMedia(url) }
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.08))
    }
}
