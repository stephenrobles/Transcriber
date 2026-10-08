import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct TranscriberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updater = AppUpdater()

    init() {
        // A new window with the drop zone is the whole point; skip the Open panel macOS would show at launch.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: { TranscriptDocument() }) { configuration in
            DocumentView(document: configuration.document)
                .environment(updater)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 740)
        .commands {
            AppCommands(updater: updater)
        }

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}

/// Receives media files opened from the Finder, the Dock icon, or `open -a Transcriber file.mp4`.
/// Project files go through the document system as usual.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = LoginItem.launchEventIsLoginItem
        Notifier.install()
        FolderWatcher.shared.configure(accepts: WatchProcessor.accepts, process: WatchProcessor.transcribe)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if LoginItem.launchEventIsLoginItem { launchedAtLogin = true }
        if launchedAtLogin {
            // Started by the system at login to watch folders: stay out of the way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                for document in NSDocumentController.shared.documents where !document.isDocumentEdited && document.fileURL == nil {
                    document.close()
                }
            }
        }
    }

    /// At a login-item launch there is nobody at the keyboard; don't open an empty window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if LoginItem.launchEventIsLoginItem { launchedAtLogin = true }
        return !launchedAtLogin
    }

    /// Keep running without windows while folders are being watched.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !FolderWatcher.shared.isWatching
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        var usedExistingEmptyDocument = false
        for url in urls {
            if PendingMedia.isProject(url) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else if PendingMedia.isMedia(url) {
                PendingMedia.shared.enqueue([url])
                if !usedExistingEmptyDocument, !PendingMedia.shared.emptyDocumentIDs.isEmpty {
                    usedExistingEmptyDocument = true
                } else {
                    NSDocumentController.shared.newDocument(nil)
                }
            }
        }
    }
}
