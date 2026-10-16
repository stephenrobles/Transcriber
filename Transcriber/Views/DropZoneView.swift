import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct DropZoneView: View {
    let isMissingMedia: Bool
    let onChoose: () -> Void
    #if os(iOS)
    @Binding var photoSelection: PhotosPickerItem?
    #endif

    @Bindable private var settings = AppSettings.shared

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
                Text(isMissingMedia ? "The media file for this project wasn't found" : headline)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(isMissingMedia
                     ? "Choose the original file and the transcript stays as it is."
                     : "MP4, MOV, M4A, MP3, WAV and more. Everything runs on this device; nothing is uploaded.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 12) {
                Button(isMissingMedia ? "Locate File…" : "Choose File…", action: onChoose)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                #if os(iOS)
                if !isMissingMedia {
                    PhotosPicker(selection: $photoSelection, matching: .videos) {
                        Text("Photos…")
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                }
                #endif
            }
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
            .help("The language of the speech in the files you choose")
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headline: String {
        #if os(macOS)
        "Drop a video or audio file to transcribe"
        #else
        "Choose a video or audio file to transcribe"
        #endif
    }
}
