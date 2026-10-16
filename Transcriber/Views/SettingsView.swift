import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    /// Tall enough to show a tab without scrolling on a big display, never taller than the screen;
    /// the form scrolls inside it on small ones.
    private var windowHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return min(620, screen - 110)
    }

    @State private var selectedTab = SettingsView.initialTab

    /// Debug builds honor TRANSCRIBER_SETTINGS_TAB=Subtitles (or General, Watched Folders) for screenshots.
    private static var initialTab: String {
        #if DEBUG
        if let tab = ProcessInfo.processInfo.environment["TRANSCRIBER_SETTINGS_TAB"] { return tab }
        #endif
        return "General"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: "General") {
                Form {
                    Section("Transcription") {
                        LanguagePicker(selection: $settings.localeIdentifier)
                        Text("Speech is recognized on this Mac with Apple's on-device engine; nothing leaves your computer. A language's model downloads the first time you use it. The language can also be changed in the window before each transcription. Languages marked “dictation model” use Apple's earlier on-device dictation engine, which covers more languages at lower accuracy.")
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
                }
                .formStyle(.grouped)
            }
            Tab("Subtitles", systemImage: "captions.bubble", value: "Subtitles") {
                Form {
                    Section("Video Preview") {
                        Toggle("Show captions over the video while it plays", isOn: $settings.previewCaptions)
                        Picker("Style", selection: $settings.captionStyle) {
                            ForEach(CaptionPreviewStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!settings.previewCaptions)
                        CaptionStyleSample(style: settings.captionStyle)
                            .opacity(settings.previewCaptions ? 1 : 0.4)
                        Text(settings.captionStyle.summary + " Captions in the preview use the same line limits as SRT export; they are not burned into the video.")
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
                }
                .formStyle(.grouped)
            }
            Tab("Watched Folders", systemImage: "folder.badge.gearshape", value: "Watched Folders") {
                Form {
            WatchedFoldersSettings()
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 540, height: windowHeight)
    }

}
#endif

#if os(iOS)
/// Settings as a sheet on iPhone and iPad.
struct SettingsSheet: View {
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Transcription") {
                    LanguagePicker(selection: $settings.localeIdentifier)
                    Text("Speech is recognized on this device with Apple's on-device engine; nothing leaves it. A language's model downloads the first time you use it. Languages marked “dictation model” use Apple's earlier dictation engine, which covers more languages at lower accuracy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Video Preview") {
                    Toggle("Show captions over the video", isOn: $settings.previewCaptions)
                    Picker("Style", selection: $settings.captionStyle) {
                        ForEach(CaptionPreviewStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.previewCaptions)
                    CaptionStyleSample(style: settings.captionStyle)
                        .opacity(settings.previewCaptions ? 1 : 0.4)
                        .listRowInsets(EdgeInsets())
                    Text(settings.captionStyle.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Subtitle Cues") {
                    Stepper("Characters per line: \(settings.maxCharactersPerLine)", value: $settings.maxCharactersPerLine, in: 20...80)
                    Stepper("Lines per cue: \(settings.maxLines)", value: $settings.maxLines, in: 1...3)
                    VStack(alignment: .leading) {
                        Text("Longest cue: \(String(format: "%.1f s", settings.maxCueDuration))")
                        Slider(value: $settings.maxCueDuration, in: 2...10, step: 0.5)
                    }
                    VStack(alignment: .leading) {
                        Text("Break on pauses over \(String(format: "%.1f s", settings.pauseBreak))")
                        Slider(value: $settings.pauseBreak, in: 0.3...3, step: 0.1)
                    }
                    Text("These limits shape cues when a file is transcribed and when you rebuild cues. YouTube reads two lines of up to 42 characters comfortably.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Text Export") {
                    VStack(alignment: .leading) {
                        Text("New paragraph after a pause of \(String(format: "%.2f s", settings.paragraphGap))")
                        Slider(value: $settings.paragraphGap, in: 0.5...5, step: 0.25)
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
