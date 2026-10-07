import AVKit
import SwiftUI

/// Video (when there is any) plus a transport bar: play/pause, scrubber, times, speed.
struct PlayerView: View {
    @Bindable var player: PlayerController
    @State private var scrubTime: TimeInterval?

    var body: some View {
        VStack(spacing: 0) {
            if player.hasVideo {
                VideoPlayer(player: player.player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .background(.black)
                Divider()
            }
            HStack(spacing: 12) {
                Button {
                    player.skip(by: -5)
                } label: {
                    Image(systemName: "gobackward.5")
                }
                .help("Back 5 seconds (⌥⌘←)")
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 22)
                }
                .help(player.isPlaying ? "Pause (⌥Space)" : "Play (⌥Space)")
                Button {
                    player.skip(by: 5)
                } label: {
                    Image(systemName: "goforward.5")
                }
                .help("Forward 5 seconds (⌥⌘→)")

                Text(TimeFormat.clock(scrubTime ?? player.currentTime, forceHours: player.duration >= 3600))
                    .monospacedDigit()
                    .frame(width: player.duration >= 3600 ? 64 : 44, alignment: .trailing)

                Slider(value: Binding(get: { scrubTime ?? player.currentTime },
                                      set: { scrubTime = $0 }),
                       in: 0...max(player.duration, 0.01)) { editing in
                    if !editing, let scrubTime {
                        player.seek(to: scrubTime)
                        self.scrubTime = nil
                    }
                }

                Text(TimeFormat.clock(player.duration, forceHours: player.duration >= 3600))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: player.duration >= 3600 ? 64 : 44, alignment: .leading)

                Menu {
                    ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                        Button {
                            player.rate = rate
                        } label: {
                            if player.rate == rate {
                                Label(rateTitle(rate), systemImage: "checkmark")
                            } else {
                                Text(rateTitle(rate))
                            }
                        }
                    }
                } label: {
                    Text(rateTitle(player.rate))
                        .monospacedDigit()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Playback speed")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func rateTitle(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }
}
