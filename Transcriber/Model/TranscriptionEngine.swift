import AVFoundation
import CoreMedia
import Foundation
import Speech

nonisolated enum TranscriptionEvent: Sendable {
    /// A short status line ("Downloading the English speech model…").
    case status(String)
    /// Speech model download progress, 0…1.
    case downloading(Double)
    /// Transcription progress through the file, 0…1.
    case progress(Double)
    /// The engine's current guess for the stretch it is still working on.
    case volatile(String)
    /// Finalized words, in order; append to what came before.
    case words([TranscriptWord])
}

/// Runs Apple's on-device SpeechAnalyzer over a media file and streams the results.
nonisolated enum TranscriptionEngine {
    static func transcribe(url: URL, locale: Locale) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await run(url: url, locale: locale) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func languageName(_ locale: Locale) -> String {
        LanguageCatalog.name(locale)
    }

    /// The locale the engine will actually use for `locale`, if it supports it at all.
    static func supportedLocale(for locale: Locale) async -> Locale? {
        if let speech = await SpeechTranscriber.supportedLocale(equivalentTo: locale) { return speech }
        return await DictationTranscriber.supportedLocale(equivalentTo: locale)
    }

    private static func run(url: URL, locale: Locale, emit: @escaping @Sendable (TranscriptionEvent) -> Void) async throws {
        emit(.status("Reading media…"))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard let (transcriber, resolvedLocale) = await makeTranscriber(for: locale, maskProfanity: false) else {
            throw TranscriptionError.unsupportedLanguage(languageName(locale))
        }

        try await ensureAssets(for: transcriber.module, locale: resolvedLocale, emit: emit)
        try Task.checkCancellation()

        emit(.status("Preparing…"))
        let analyzer = SpeechAnalyzer(modules: [transcriber.module])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber.module]) else {
            throw TranscriptionError.noAudioFormat
        }
        let reader = try await MediaAudioReader(asset: asset, targetFormat: format)
        let input = AnalyzerInputSequence(reader: reader, onBufferRead: nil)

        emit(.status("Transcribing…"))
        let handle: @Sendable (AttributedString, Bool, CMTimeRange) -> Void = { text, isFinal, range in
            if isFinal {
                emit(.words(words(from: text)))
                emit(.volatile(""))
                if duration > 0 {
                    emit(.progress(min(1, max(0, range.end.seconds / duration))))
                }
            } else {
                emit(.volatile(String(text.characters)))
            }
        }
        let results = Task.detached(priority: .userInitiated) {
            switch transcriber {
            case .speech(let module):
                for try await result in module.results { handle(result.text, result.isFinal, result.range) }
            case .dictation(let module):
                for try await result in module.results { handle(result.text, result.isFinal, result.range) }
            }
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(input) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            results.cancel()
            throw error
        }
        try await results.value
        emit(.progress(1))
    }

    /// Apple's new engine when it knows the language; otherwise the earlier on-device dictation
    /// model, which covers more languages (Swedish, Dutch, Norwegian, …) at lower accuracy.
    enum Transcriber {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .speech(let module): module
            case .dictation(let module): module
            }
        }
    }

    static func makeTranscriber(for locale: Locale, maskProfanity: Bool) async -> (Transcriber, Locale)? {
        if let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let module = SpeechTranscriber(locale: resolved,
                                           transcriptionOptions: maskProfanity ? [.etiquetteReplacements] : [],
                                           reportingOptions: [.volatileResults],
                                           attributeOptions: [.audioTimeRange])
            return (.speech(module), resolved)
        }
        if let resolved = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            var options: Set<DictationTranscriber.TranscriptionOption> = [.punctuation]
            if maskProfanity { options.insert(.etiquetteReplacements) }
            let module = DictationTranscriber(locale: resolved,
                                              contentHints: [],
                                              transcriptionOptions: options,
                                              reportingOptions: [.volatileResults],
                                              attributeOptions: [.audioTimeRange])
            return (.dictation(module), resolved)
        }
        return nil
    }

    private static func ensureAssets(for transcriber: any SpeechModule, locale: Locale, emit: @escaping @Sendable (TranscriptionEvent) -> Void) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionError.unsupportedLanguage(languageName(locale))
        case .supported, .downloading:
            break
        @unknown default:
            break
        }
        emit(.status("Downloading the \(languageName(locale)) speech model…"))
        emit(.downloading(0))
        // Reservation keeps the model installed; if the reservation list is full the download still works.
        _ = try? await AssetInventory.reserve(locale: locale)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        let progress = request.progress
        let poll = Task.detached {
            while !Task.isCancelled {
                emit(.downloading(progress.fractionCompleted))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poll.cancel() }
        try await request.downloadAndInstall()
        emit(.downloading(1))
    }

    /// Turns a finalized attributed result into words with times. Runs carry per-token time ranges;
    /// punctuation and spacing runs have none and are folded into the neighbouring word.
    static func words(from text: AttributedString) -> [TranscriptWord] {
        var characters: [(Character, CMTimeRange?)] = []
        for run in text.runs {
            let range = run.audioTimeRange
            for character in text[run.range].characters {
                characters.append((character, range))
            }
        }

        var words: [TranscriptWord] = []
        var pendingPrefix = ""
        var token = ""
        var tokenStart: TimeInterval?
        var tokenEnd: TimeInterval?

        func flushToken() {
            guard !token.isEmpty else { return }
            if let start = tokenStart, let end = tokenEnd {
                words.append(TranscriptWord(text: pendingPrefix + token, start: start, end: max(end, start)))
                pendingPrefix = ""
            } else if !words.isEmpty {
                words[words.count - 1].text += token
            } else {
                pendingPrefix += token
            }
            token = ""
            tokenStart = nil
            tokenEnd = nil
        }

        for (character, range) in characters {
            if character.isWhitespace || character.isNewline {
                flushToken()
                continue
            }
            token.append(character)
            if let range, range.start.isNumeric, range.duration.isNumeric {
                let start = range.start.seconds
                let end = range.end.seconds
                tokenStart = min(tokenStart ?? start, start)
                tokenEnd = max(tokenEnd ?? end, end)
            }
        }
        flushToken()
        if !pendingPrefix.isEmpty, !words.isEmpty {
            words[words.count - 1].text += pendingPrefix
        }
        return words
    }
}
