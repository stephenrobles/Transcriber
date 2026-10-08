import AppKit
import SwiftUI

/// The Settings sections for watched folders: the folder list, what gets written, login item, activity.
struct WatchedFoldersSettings: View {
    @Bindable private var settings = AppSettings.shared
    private var watcher: FolderWatcher { FolderWatcher.shared }
    @State private var loginEnabled = false
    @State private var loginError: String?

    var body: some View {
        Section("Watched Folders") {
            if watcher.folders.isEmpty {
                Text("Add a folder and every video or audio file that lands in it is transcribed automatically, with the outputs saved next to it.")
                    .foregroundStyle(.secondary)
            }
            ForEach(watcher.folders) { folder in
                HStack(spacing: 10) {
                    Toggle("Watch \(folder.displayName)", isOn: Binding(get: { folder.isEnabled }, set: { watcher.setEnabled(folder.id, $0) }))
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.displayName)
                        Text(folder.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !folder.exists {
                        Label("Folder not found", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Button {
                        watcher.remove(folder.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop watching this folder")
                }
            }
            HStack {
                Button("Add Folder…") { addFolder() }
                Spacer()
                if watcher.isProcessing {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Files already in a folder are left alone; only new arrivals are transcribed, once they have finished copying. Transcriber has to be running, so turn on Open at Login to make it automatic.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Watched Folder Output") {
            ForEach(ExportFormat.allCases) { format in
                Toggle(format.title, isOn: Binding(
                    get: { settings.watchFormats.contains(format.rawValue) },
                    set: { on in
                        if on { settings.watchFormats.insert(format.rawValue) } else { settings.watchFormats.remove(format.rawValue) }
                    }))
            }
            Toggle("Also save a .transcriber project", isOn: $settings.watchSavesProject)
            if settings.watchFormats.isEmpty, !settings.watchSavesProject {
                Text("Nothing is selected, so watched files will be transcribed and then discarded.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Open Transcriber at login", isOn: Binding(get: { loginEnabled }, set: { setLogin($0) }))
                .onAppear { loginEnabled = LoginItem.isEnabled }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Opens quietly in the background at login, without a window, so watched folders are handled while you work.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !watcher.activity.isEmpty {
            Section("Recent Activity") {
                ForEach(watcher.activity.prefix(8)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        statusIcon(entry.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.fileName).lineLimit(1).truncationMode(.middle)
                            Text(detail(entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if let url = entry.resultURL {
                            Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ status: WatchActivity.Status) -> some View {
        Group {
            switch status {
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .frame(width: 16)
    }

    private func detail(_ entry: WatchActivity) -> String {
        let when = entry.date.formatted(.relative(presentation: .named))
        switch entry.status {
        case .running: return "Transcribing from \(entry.folderName)…"
        case .done: return "From \(entry.folderName), \(when)"
        case .failed(let message): return message
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose folders to watch. New video and audio files in them are transcribed automatically."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { watcher.add(url) }
        Notifier.requestAuthorization()
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginEnabled = LoginItem.isEnabled
    }
}
