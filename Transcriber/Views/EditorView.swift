import SwiftUI

/// Player on top, then the cue list or the plain-text view, with a status bar underneath.
struct EditorView: View {
    let document: TranscriptDocument
    @Bindable var state: EditorState
    let player: PlayerController
    let onExport: (ExportFormat) -> Void
    let onRelink: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var pendingLanguage: String?

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 0) {
            if document.hasMedia, player.isLoaded {
                PlayerView(player: player, caption: currentCaption)
                Divider()
            } else if document.mediaMissing {
                MissingMediaBanner(document: document, onLocate: onRelink)
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
        .platformToolbarStyle()
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .principal) {
                tabButton(.cues)
            }
            ToolbarItem(placement: .principal) {
                tabButton(.text)
            }
            #endif
            ToolbarItemGroup {
                Button {
                    if state.findVisible { state.hideFind() } else { state.showFind() }
                } label: {
                    Label("Find & Replace", systemImage: "magnifyingglass")
                }
                .help("Find & Replace (⌘F)")
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button("\(format.title)…") { onExport(format) }
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

    /// The cue under the playhead, wrapped the way it would be in an SRT file.
    private var currentCaption: String? {
        guard player.hasVideo, let transcript = document.transcript,
              let index = transcript.cueIndex(at: player.currentTime) else { return nil }
        let cue = transcript.cues[index]
        guard cue.contains(player.currentTime) else { return nil }
        return CueBuilder.wrap(cue.text, settings: document.cueSettings).joined(separator: "\n")
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
        .borderlessMenu()
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
            #if os(iOS)
            // The document title's menu covers the toolbar's principal slot on iPhone, so the view switch lives here.
            Picker("View", selection: $state.tab) {
                ForEach(EditorState.Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .controlSize(.small)
            if let transcript = document.transcript {
                Spacer(minLength: 8)
                languageMenu(current: transcript.localeIdentifier)
                    .lineLimit(1)
                Text("\(transcript.cues.count) cues")
                    .lineLimit(1)
                    .fixedSize()
            }
            #else
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
            #endif
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct MissingMediaBanner: View {
    let document: TranscriptDocument
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("The media file \"\(document.mediaFileName ?? "")\" wasn't found, so playback is off. Editing and export still work.")
                .lineLimit(2)
            Spacer()
            Button("Locate…", action: onLocate)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.08))
    }
}

extension View {
    /// A menu that looks like plain text with a chevron on the Mac; the default elsewhere.
    @ViewBuilder
    func borderlessMenu() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton)
        #else
        self
        #endif
    }
}

private extension View {
    /// On iPhone and iPad the bar gets a solid background so the video starts below it.
    @ViewBuilder
    func platformToolbarStyle() -> some View {
        #if os(iOS)
        self.toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }
}
