import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import PhotosUI
#endif

/// Root view of a document. Shows the drop zone, the live transcription, or the editor, and owns
/// the file dialogs and confirmations that the menus and toolbar trigger.
struct DocumentView: View {
    let document: TranscriptDocument
    @State private var state = EditorState()
    @State private var player = PlayerController()
    #if os(iOS)
    @State fileprivate var hinge = HingeMonitor()
    #endif
    @State private var viewID = UUID()
    @State private var dropTargeted = false
    @State private var showFileImporter = false
    @State private var importerRelinks = false
    @State private var confirmation: Confirmation?
    @State private var importError: String?
    #if os(iOS)
    @State private var photoSelection: PhotosPickerItem?
    @State private var exportRequest: ExportRequest?
    @State private var showSettings = false
    #endif
    @Environment(\.undoManager) private var undoManager
    #if os(macOS)
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openSettings) private var openSettings
    #endif

    private var settings: AppSettings { AppSettings.shared }

    private enum Confirmation: Identifiable {
        case retranscribe, rebuildCues
        var id: Self { self }
    }

    #if os(iOS)
    private struct ExportRequest: Identifiable {
        let format: ExportFormat
        let file: ExportedTextFile
        let name: String
        var id: String { format.rawValue }
    }
    #endif

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
            .focusedSceneValue(\.documentContext, DocumentContext(
                document: document, state: state, player: player, undoManager: undoManager,
                openMedia: { importerRelinks = false; showFileImporter = true },
                export: export,
                retranscribe: { if document.hasTranscript { confirmation = .retranscribe } else { startTranscription() } },
                rebuildCues: { confirmation = .rebuildCues }))
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: PendingMedia.acceptedTypes, allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                if importerRelinks || (document.mediaMissing && document.hasTranscript) {
                    document.relinkMedia(url, undoManager: undoManager)
                } else {
                    openInNewOrHere(url)
                }
            }
            .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                switch confirmation {
                case .retranscribe:
                    Button("Transcribe Again", role: .destructive) { startTranscription() }
                case .rebuildCues:
                    Button("Rebuild Cues", role: .destructive) { document.rebuildCues(settings: settings.cueSettings, undoManager: undoManager) }
                case nil:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmation == .rebuildCues
                     ? "Cues are regrouped from the original transcription using the limits in Settings. Text edits, splits and merges are discarded. You can undo this."
                     : "The current transcript and any edits will be replaced. You can undo this.")
            }
            .alert("Couldn't import the video", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .task(id: document.mediaURL) {
                if let url = document.mediaURL {
                    await player.load(url: url)
                    #if DEBUG
                    if let seek = ProcessInfo.processInfo.environment["TRANSCRIBER_SEEK"].flatMap(Double.init) { player.seek(to: seek) }
                    #endif
                } else {
                    player.unload()
                }
            }
            .onDisappear { player.pause() }
            .platformExtras(self)
            .observingHinge(self)
    }

    @ViewBuilder
    private var content: some View {
        if let job = document.job, job.isRunning {
            foldPane {
                TranscribingView(job: job, fileName: document.mediaFileName ?? "") {
                    document.cancelTranscription()
                }
            }
        } else if document.hasTranscript {
            #if os(macOS)
            EditorView(document: document, state: state, player: player, onExport: export,
                       onRelink: { importerRelinks = true; showFileImporter = true })
            #else
            EditorView(document: document, state: state, player: player, onExport: export,
                       onRelink: { importerRelinks = true; showFileImporter = true }, hinge: hinge)
            #endif
        } else if document.hasMedia {
            foldPane {
                ReadyView(document: document, player: player) {
                    startTranscription()
                }
            }
        } else {
            #if os(macOS)
            DropZoneView(isMissingMedia: document.mediaMissing, onChoose: { importerRelinks = document.mediaMissing; showFileImporter = true })
            #else
            foldPane {
                DropZoneView(isMissingMedia: document.mediaMissing, onChoose: { importerRelinks = document.mediaMissing; showFileImporter = true },
                             photoSelection: $photoSelection)
            }
            #endif
        }
    }

    /// On a bent foldable, keeps a full-screen view in the pane away from the hinge; elsewhere a no-op.
    @ViewBuilder
    private func foldPane<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        #if os(iOS)
        FoldPane(monitor: hinge, content: content)
        #else
        content()
        #endif
    }

    private var confirmationTitle: String {
        confirmation == .rebuildCues ? "Rebuild cues from the subtitle settings?" : "Transcribe this file again?"
    }

    // MARK: - Media intake

    private func handleDrop(_ urls: [URL]) -> Bool {
        let media = urls.filter { PendingMedia.isMedia($0) }
        #if os(macOS)
        let projects = urls.filter { PendingMedia.isProject($0) }
        for project in projects {
            NSDocumentController.shared.openDocument(withContentsOf: project, display: true) { _, _, _ in }
        }
        guard !media.isEmpty else { return !projects.isEmpty }
        #else
        guard !media.isEmpty else { return false }
        #endif
        var remaining = media[...]
        if !document.hasMedia || document.mediaMissing && !document.hasTranscript {
            attach(remaining.removeFirst())
        } else if document.mediaMissing {
            // A project whose media went missing: the dropped file stands in for it.
            document.relinkMedia(remaining.removeFirst(), undoManager: undoManager)
        }
        for url in remaining {
            openInNewOrHere(url)
        }
        return true
    }

    /// On the Mac a second file gets its own window; on iPhone and iPad it replaces this document's
    /// media and the transcript is redone (undoable).
    private func openInNewOrHere(_ url: URL) {
        #if os(macOS)
        if document.hasMedia {
            newDocument { TranscriptDocument(mediaURL: url) }
            return
        }
        #endif
        attach(url)
    }

    fileprivate func attach(_ url: URL) {
        document.attachMedia(url, undoManager: undoManager)
        startTranscription()
    }

    private func startTranscription() {
        document.startTranscription(locale: settings.locale, cueSettings: settings.cueSettings, undoManager: undoManager)
    }

    // MARK: - Export

    private func export(_ format: ExportFormat) {
        #if os(macOS)
        ExportPanel.run(document: document, format: format)
        #else
        let text = TranscriptExporter.export(document.cues, as: format, title: document.suggestedBaseName,
                                             cueSettings: document.cueSettings, paragraphGap: settings.paragraphGap)
        exportRequest = ExportRequest(format: format, file: ExportedTextFile(text: text),
                                      name: document.suggestedBaseName + "." + format.fileExtension)
        #endif
    }

    // MARK: - Platform extras

    #if os(macOS)
    fileprivate func macExtras<Content: View>(_ view: Content) -> some View {
        view
            .onAppear {
                adoptPendingMediaIfEmpty()
                #if DEBUG
                if CommandLine.arguments.contains("-OpenSettings") { openSettings() }
                #endif
            }
            .onChange(of: PendingMedia.shared.urls.count) { adoptPendingMediaIfEmpty() }
            .onChange(of: document.hasMedia, initial: true) { _, hasMedia in
                if hasMedia {
                    PendingMedia.shared.emptyDocumentIDs.remove(viewID)
                } else {
                    PendingMedia.shared.emptyDocumentIDs.insert(viewID)
                }
            }
            .onDisappear { PendingMedia.shared.emptyDocumentIDs.remove(viewID) }
    }

    private func adoptPendingMediaIfEmpty() {
        guard !document.hasMedia, let url = PendingMedia.shared.take() else { return }
        attach(url)
    }
    #else
    fileprivate func iOSExtras<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                Task {
                    do {
                        if let movie = try await item.loadTransferable(type: ImportedMovie.self) {
                            attach(movie.url)
                        } else {
                            importError = "That item isn't a video Transcriber can read."
                        }
                    } catch {
                        importError = error.localizedDescription
                    }
                    photoSelection = nil
                }
            }
            .fileExporter(isPresented: Binding(get: { exportRequest != nil }, set: { if !$0 { exportRequest = nil } }),
                          document: exportRequest?.file,
                          contentType: UTType(filenameExtension: exportRequest?.format.fileExtension ?? "txt") ?? .plainText,
                          defaultFilename: exportRequest?.name) { _ in
                exportRequest = nil
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
    }
    #endif
}

private extension View {
    @ViewBuilder
    func observingHinge(_ document: DocumentView) -> some View {
        #if os(iOS)
        self.background(HingeObserver(monitor: document.hinge))
        #else
        self
        #endif
    }

    func platformExtras(_ document: DocumentView) -> some View {
        #if os(macOS)
        document.macExtras(self)
        #else
        document.iOSExtras(self)
        #endif
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
                    .multilineTextAlignment(.center)
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
                #if os(macOS)
                Text("Spoken language")
                    .foregroundStyle(.secondary)
                LanguagePicker(selection: $settings.localeIdentifier)
                    .labelsHidden()
                    .fixedSize()
                #else
                LanguagePicker(selection: $settings.localeIdentifier, label: "Spoken language")
                #endif
            }
            .font(.callout)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
