import AVFoundation
import Combine
import Foundation
import Observation

/// Wraps an AVPlayer so the transcript can follow playback and cues can seek it.
@Observable
final class PlayerController {
    let player = AVPlayer()

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var hasVideo = false
    private(set) var isLoaded = false
    var rate: Float = 1 {
        didSet { if isPlaying { player.rate = rate } }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusCancellable: AnyCancellable?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .pause
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
    }

    func load(url: URL) async {
        unload()
        let asset = AVURLAsset(url: url)
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        hasVideo = !videoTracks.isEmpty
        duration = (try? await asset.load(.duration).seconds) ?? 0
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
        isLoaded = true
    }

    func unload() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.replaceCurrentItem(with: nil)
        isLoaded = false
        hasVideo = false
        currentTime = 0
        duration = 0
    }

    func togglePlayback() {
        guard isLoaded else { return }
        if isPlaying {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
            player.playImmediately(atRate: rate)
        }
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval, thenPlay: Bool = false) {
        guard isLoaded else { return }
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if thenPlay, !isPlaying { player.playImmediately(atRate: rate) }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }
}
