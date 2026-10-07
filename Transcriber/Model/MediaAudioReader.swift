import AVFoundation
import Speech

nonisolated enum TranscriptionError: LocalizedError {
    case noAudioTrack
    case unsupportedLanguage(String)
    case noAudioFormat
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: "This file has no audio track to transcribe."
        case .unsupportedLanguage(let name): "On-device transcription isn't available for \(name) on this Mac."
        case .noAudioFormat: "The speech engine didn't offer an audio format it can analyze."
        case .readerFailed(let reason): "The audio couldn't be read: \(reason)"
        }
    }
}

/// Decodes every audio track of a movie or audio file (mixed to mono) and hands out PCM buffers
/// in the format the speech analyzer asked for. Reads are pulled one buffer at a time, so the
/// analyzer sets the pace and a long file never has to sit in memory.
nonisolated final class MediaAudioReader: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let readerFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let lock = NSLock()

    init(asset: AVAsset, targetFormat: AVAudioFormat) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw TranscriptionError.noAudioTrack }
        reader = try AVAssetReader(asset: asset)
        let sampleRate = targetFormat.sampleRate
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw TranscriptionError.readerFailed("unsupported audio") }
        reader.add(output)
        guard let readerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1,
                                               interleaved: targetFormat.channelCount == 1 ? targetFormat.isInterleaved : true) else {
            throw TranscriptionError.noAudioFormat
        }
        self.readerFormat = readerFormat
        self.targetFormat = targetFormat
        if readerFormat == targetFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: readerFormat, to: targetFormat) else { throw TranscriptionError.noAudioFormat }
            self.converter = converter
        }
        guard reader.startReading() else {
            throw TranscriptionError.readerFailed(reader.error?.localizedDescription ?? "unknown error")
        }
    }

    /// The next buffer in the analyzer's format, or nil at the end of the file.
    func next() throws -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        while true {
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw TranscriptionError.readerFailed(reader.error?.localizedDescription ?? "unknown error") }
                return nil
            }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0 else { continue }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: readerFormat, frameCapacity: AVAudioFrameCount(frames)) else {
                throw TranscriptionError.noAudioFormat
            }
            pcm.frameLength = AVAudioFrameCount(frames)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
            guard status == noErr else { throw TranscriptionError.readerFailed("PCM copy failed (\(status))") }
            guard let converter else { return pcm }

            let ratio = targetFormat.sampleRate / readerFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
                throw TranscriptionError.noAudioFormat
            }
            var handedOut = false
            var conversionError: NSError?
            let result = converter.convert(to: converted, error: &conversionError) { _, outStatus in
                if handedOut {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                handedOut = true
                outStatus.pointee = .haveData
                return pcm
            }
            if let conversionError { throw conversionError }
            if result == .error { throw TranscriptionError.readerFailed("audio conversion failed") }
            if converted.frameLength == 0 { continue }
            return converted
        }
    }
}

/// Adapts the reader to the async sequence the speech analyzer consumes.
nonisolated struct AnalyzerInputSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput

    let reader: MediaAudioReader
    let onBufferRead: (@Sendable (TimeInterval) -> Void)?

    func makeAsyncIterator() -> Iterator {
        Iterator(reader: reader, onBufferRead: onBufferRead)
    }

    struct Iterator: AsyncIteratorProtocol {
        let reader: MediaAudioReader
        let onBufferRead: (@Sendable (TimeInterval) -> Void)?
        var secondsRead: TimeInterval = 0

        mutating func next() async throws -> AnalyzerInput? {
            try Task.checkCancellation()
            guard let buffer = try reader.next() else { return nil }
            secondsRead += Double(buffer.frameLength) / buffer.format.sampleRate
            onBufferRead?(secondsRead)
            return AnalyzerInput(buffer: buffer)
        }
    }
}
