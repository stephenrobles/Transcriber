import Foundation
import Observation

/// Drives one transcription run for a document and exposes its progress to the UI.
@Observable
final class TranscriptionJob {
    enum Phase: Equatable {
        case preparing
        case downloading
        case transcribing
        case finished
        case failed(String)
        case cancelled
    }

    private(set) var phase: Phase = .preparing
    private(set) var status = "Starting…"
    private(set) var progress: Double = 0
    private(set) var downloadProgress: Double = 0
    private(set) var words: [TranscriptWord] = []
    private(set) var volatileText = ""
    private(set) var startedAt = Date()
    let locale: Locale

    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .preparing, .downloading, .transcribing: true
        default: false
        }
    }

    /// Finalized text so far, for the live view.
    var liveText: String {
        words.map(\.text).joined(separator: " ")
    }

    init(locale: Locale) {
        self.locale = locale
    }

    func start(url: URL, completion: @escaping @MainActor ([TranscriptWord]) -> Void) {
        startedAt = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in TranscriptionEngine.transcribe(url: url, locale: locale) {
                    switch event {
                    case .status(let text):
                        status = text
                        if phase == .downloading { phase = .preparing }
                    case .downloading(let fraction):
                        phase = .downloading
                        downloadProgress = fraction
                    case .progress(let fraction):
                        phase = .transcribing
                        progress = max(progress, fraction)
                    case .volatile(let text):
                        phase = .transcribing
                        volatileText = text
                    case .words(let new):
                        phase = .transcribing
                        words.append(contentsOf: new)
                    }
                }
                guard !Task.isCancelled else {
                    phase = .cancelled
                    return
                }
                phase = .finished
                progress = 1
                completion(words)
            } catch is CancellationError {
                phase = .cancelled
            } catch {
                if Task.isCancelled {
                    phase = .cancelled
                } else {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        phase = .cancelled
    }
}
