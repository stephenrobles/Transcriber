import SwiftUI

struct DropZoneView: View {
    let isMissingMedia: Bool
    let onChoose: () -> Void

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 148, height: 148)
                HStack(spacing: 9) {
                    Image(systemName: "waveform")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "text.alignleft")
                }
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 8) {
                Text(isMissingMedia ? "The media file for this project wasn't found" : "Drop a video or audio file to transcribe")
                    .font(.title2.weight(.semibold))
                Text(isMissingMedia
                     ? "Drop the original file here, or choose it, and the transcript stays as it is."
                     : "MP4, MOV, M4A, MP3, WAV and more. Everything runs on this Mac; nothing is uploaded.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Button(isMissingMedia ? "Locate File…" : "Choose File…", action: onChoose)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            Text("Transcribes in \(TranscriptionEngine.languageName(settings.locale)). Change the language in Settings.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
