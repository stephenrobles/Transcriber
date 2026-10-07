import SwiftUI

/// Progress while the speech engine works, with the text appearing as it is recognized.
struct TranscribingView: View {
    let job: TranscriptionJob
    let fileName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fileName)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(statusLine)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                }
                ProgressView(value: job.phase == .downloading ? job.downloadProgress : job.progress)
                    .progressViewStyle(.linear)
            }
            .padding(20)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(job.liveText)\(Text(job.volatileText.isEmpty ? "" : " " + job.volatileText).foregroundStyle(.secondary))")
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(24)
                }
                .onChange(of: job.words.count) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var statusLine: String {
        switch job.phase {
        case .downloading:
            return "\(job.status) \(Int(job.downloadProgress * 100))%"
        case .transcribing:
            let percent = Int(job.progress * 100)
            let elapsed = Date().timeIntervalSince(job.startedAt)
            if job.progress > 0.02, elapsed > 3 {
                let remaining = elapsed / job.progress - elapsed
                return "Transcribing… \(percent)% · about \(TimeFormat.clock(remaining)) left"
            }
            return "Transcribing… \(percent)%"
        default:
            return job.status
        }
    }
}
