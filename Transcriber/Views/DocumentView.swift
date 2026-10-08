import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Root view of a document window. Shows the drop zone, the live transcription, or the editor.
struct DocumentView: View {
    let document: TranscriptDocument
    @State private var state = EditorState()
    @State private var player = PlayerController()
    @State private var viewID = UUID()
    @State private var dropTargeted = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.newDocument) private var newDocument

    private var settings: AppSettings { AppSettings.shared }
    private var pending: PendingMedia { PendingMedia.shared }

    var body: some View {
        content
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
            } isTargeted: { dropTargeted = $0 }
            .focusedSceneValue(\.documentContext, DocumentContext(document: document, state: state, player: player,
                                                                   undoManager: undoManager, attachMedia: attach))
            .task(id: document.mediaURL) {
                if let url = document.mediaURL {
                    await player.load(url: url)
                } else {
                    player.unload()
                }
            }
            .onAppear { adoptPendingMediaIfEmpty() }
            .onChange(of: pending.urls.count) { adoptPendingMediaIfEmpty() }
            .onChange(of: document.hasMedia, initial: true) { _, hasMedia in
                if hasMedia {
                    pending.emptyDocumentIDs.remove(viewID)
                } else {
                    pending.emptyDocumentIDs.insert(viewID)
                }
            }
            .onDisappear {
                pending.emptyDocumentIDs.remove(viewID)
                player.pause()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let job = document.job, job.isRunning {
            TranscribingView(job: job, fileName: document.mediaFileName ?? "") {
                document.cancelTranscription()
            }
        } else if document.hasTranscript {
            EditorView(document: document, state: state, player: player)
        } else if document.hasMedia {
            ReadyView(document: document, player: player) {
                startTranscription()
            }
        } else {
            DropZoneView(isMissingMedia: document.mediaMissing, onChoose: chooseMedia)
        }
    }

    // MARK: - Media intake

    private func handleDrop(_ urls: [URL]) -> Bool {
        let media = urls.filter { PendingMedia.isMedia($0) }
        let projects = urls.filter { PendingMedia.isProject($0) }
        for project in projects {
            NSDocumentController.shared.openDocument(withContentsOf: project, display: true) { _, _, _ in }
        }
        guard !media.isEmpty else { return !projects.isEmpty }
        var remaining = media[...]
        if !document.hasMedia || document.mediaMissing && !document.hasTranscript {
            attach(remaining.removeFirst())
        } else if document.mediaMissing {
            // A project whose media went missing: the dropped file stands in for it.
            document.relinkMedia(remaining.removeFirst())
        }
        for url in remaining {
            newDocument { TranscriptDocument(mediaURL: url) }
        }
        return true
    }

    private func adoptPendingMediaIfEmpty() {
        guard !document.hasMedia, let url = pending.take() else { return }
        attach(url)
    }

    private func attach(_ url: URL) {
        document.attachMedia(url, undoManager: undoManager)
        startTranscription()
    }

    private func startTranscription() {
        document.startTranscription(locale: settings.locale, cueSettings: settings.cueSettings, undoManager: undoManager)
    }

    private func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = PendingMedia.acceptedTypes
        panel.message = "Choose a video or audio file to transcribe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if document.mediaMissing, document.hasTranscript {
            document.relinkMedia(url)
        } else {
            attach(url)
        }
    }
}

/// Media is attached but there is no transcript: after a cancel, a failure, or a Transcribe Again.
struct ReadyView: View {
    let document: TranscriptDocument
    let player: PlayerController
    let onTranscribe: () -> Void

    @Bindable private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: player.hasVideo ? "film" : "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(document.mediaFileName ?? "")
                    .font(.title3.weight(.semibold))
                if player.duration > 0 {
                    Text(TimeFormat.clock(player.duration))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let job = document.job, case .failed(let message) = job.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button {
                onTranscribe()
            } label: {
                Label("Transcribe", systemImage: "text.bubble")
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            HStack(spacing: 6) {
                Text("Spoken language")
                    .foregroundStyle(.secondary)
                LanguagePicker(selection: $settings.localeIdentifier)
                    .labelsHidden()
                    .fixedSize()
            }
            .font(.callout)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
