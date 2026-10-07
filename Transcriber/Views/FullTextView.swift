import SwiftUI

/// The transcript as readable paragraphs, for reading and copying.
struct FullTextView: View {
    let document: TranscriptDocument
    @Bindable var state: EditorState

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        let paragraphs = TranscriptExporter.paragraphs(from: document.cues, gap: settings.paragraphGap)
        let hours = (paragraphs.last?.start ?? 0) >= 3600
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if state.showTimestampsInText {
                            Text(TimeFormat.clock(paragraph.start, forceHours: hours))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: hours ? 64 : 44, alignment: .trailing)
                        }
                        Text(paragraph.text)
                            .font(.system(size: 15))
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $state.showTimestampsInText) {
                    Label("Timestamps", systemImage: "clock")
                }
                .help("Show a timestamp at the start of each paragraph")
                Button {
                    let text = state.showTimestampsInText
                        ? TranscriptExporter.timestampedText(document.cues, paragraphGap: settings.paragraphGap)
                        : TranscriptExporter.plainText(document.cues, paragraphGap: settings.paragraphGap)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .help("Copy the whole transcript")
            }
        }
    }
}
