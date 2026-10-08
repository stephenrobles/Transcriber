import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(AppUpdater.self) private var updater
    @State private var supportedLocales: [Locale] = []
    @State private var installedIdentifiers: Set<String> = []

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section("Transcription") {
                Picker("Language", selection: $settings.localeIdentifier) {
                    if !supportedLocales.contains(where: { $0.identifier == settings.localeIdentifier }) {
                        Text(TranscriptionEngine.languageName(settings.locale)).tag(settings.localeIdentifier)
                    }
                    ForEach(supportedLocales, id: \.identifier) { locale in
                        Text(languageTitle(locale)).tag(locale.identifier)
                    }
                }
                Text("Speech is recognized on this Mac with Apple's on-device engine; nothing leaves your computer. A language's model downloads the first time you use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            WatchedFoldersSettings()

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
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            supportedLocales = supported.sorted { languageTitle($0) < languageTitle($1) }
            installedIdentifiers = Set(installed.map(\.identifier))
        }
    }

    private func languageTitle(_ locale: Locale) -> String {
        TranscriptionEngine.languageName(locale)
    }
}
