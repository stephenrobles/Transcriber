import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(AppUpdater.self) private var updater

    /// Tall enough to show a tab without scrolling on a big display, never taller than the screen;
    /// the form scrolls inside it on small ones.
    private var windowHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return min(620, screen - 110)
    }

    var body: some View {
        @Bindable var updater = updater
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Section("Transcription") {
                        LanguagePicker(selection: $settings.localeIdentifier)
                        Text("Speech is recognized on this Mac with Apple's on-device engine; nothing leaves your computer. A language's model downloads the first time you use it. The language can also be changed in the window before each transcription.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Text Export") {
                        LabeledContent("New paragraph after a pause of") {
                            HStack {
                                Slider(value: $settings.paragraphGap, in: 0.5...5, step: 0.25)
                                Text(String(format: "%.2f s", settings.paragraphGap))
                                    .monospacedDigit()
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                        Text("Applies to the Text view and to .txt exports.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section("Updates") {
                        Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                        HStack {
                            Button("Check Now…") { updater.checkForUpdates() }
                                .disabled(!updater.canCheckForUpdates)
                            Spacer()
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Tab("Subtitles", systemImage: "captions.bubble") {
                Form {
                    Section("Subtitle Cues") {
                        Stepper("Characters per line: \(settings.maxCharactersPerLine)", value: $settings.maxCharactersPerLine, in: 20...80)
                        Stepper("Lines per cue: \(settings.maxLines)", value: $settings.maxLines, in: 1...3)
                        LabeledContent("Longest cue") {
                            HStack {
                                Slider(value: $settings.maxCueDuration, in: 2...10, step: 0.5)
                                Text(String(format: "%.1f s", settings.maxCueDuration))
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        LabeledContent("Break on pauses over") {
                            HStack {
                                Slider(value: $settings.pauseBreak, in: 0.3...3, step: 0.1)
                                Text(String(format: "%.1f s", settings.pauseBreak))
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                        Text("These limits shape cues when a file is transcribed and when you choose Transcript › Rebuild Cues. YouTube reads two lines of up to 42 characters comfortably.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
            Tab("Watched Folders", systemImage: "folder.badge.gearshape") {
                Form {
            WatchedFoldersSettings()
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 540, height: windowHeight)
    }

}
