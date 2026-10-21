#if os(iOS)
import SwiftUI
import UIKit

/// The hinge of a foldable iPhone, observed through UIKit's hinge interaction. On devices without a
/// hinge the status stays `.unknown` and nothing changes in the layout.
@Observable @MainActor
final class HingeMonitor {
    enum Status { case unknown, closed, partiallyOpen, fullyOpen }

    var status: Status = .unknown
    /// Radians, as reported by the system; informational only.
    var angle: Double = 0
    /// The screen the window is on, in points for the current orientation.
    var screenSize: CGSize = .zero

    /// Debug builds honor TRANSCRIBER_HINGE=closed|book|open to force a posture for screenshots
    /// (`book-h` / `book-v` also force the hinge axis).
    static let debugOverride: (status: Status, axis: FoldSplit.Axis?)? = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["TRANSCRIBER_HINGE"] {
        case "closed": return (.closed, nil)
        case "open": return (.fullyOpen, nil)
        case "book": return (.partiallyOpen, nil)
        case "book-h": return (.partiallyOpen, .horizontal)
        case "book-v": return (.partiallyOpen, .vertical)
        default: return nil
        }
        #else
        return nil
        #endif
    }()

    var effectiveStatus: Status { Self.debugOverride?.status ?? status }
    var isBent: Bool { effectiveStatus == .partiallyOpen }

    /// True when the window is on the large inner display (both dimensions well beyond a phone's width).
    var isOnInnerDisplay: Bool {
        min(screenSize.width, screenSize.height) >= 600 && max(screenSize.width, screenSize.height) >= 880
    }

    /// Where the hinge crosses a view, or nil when the device is flat, closed, or has no hinge. The fold
    /// bisects the inner display's longer side: a horizontal hinge in portrait, a vertical one in landscape.
    func split(for frame: CGRect) -> FoldSplit? {
        // A forced debug posture skips the inner-display check so the layouts can be seen on any screen.
        guard isBent, isOnInnerDisplay || Self.debugOverride != nil, frame.width > 0, frame.height > 0 else { return nil }
        let portrait = screenSize.height > screenSize.width
        var axis: FoldSplit.Axis = portrait ? .horizontal : .vertical
        if let forced = Self.debugOverride?.axis { axis = forced }
        // Each pane needs room to be useful; a forced debug axis accepts less so it can be seen on any screen.
        let minimumPane: CGFloat = Self.debugOverride?.axis != nil ? 60 : 120
        switch axis {
        case .horizontal:
            let center = screenSize.height / 2 - frame.minY
            guard center > minimumPane, center < frame.height - minimumPane else { return nil }
            return FoldSplit(axis: .horizontal, hingeCenter: center)
        case .vertical:
            let center = screenSize.width / 2 - frame.minX
            guard center > minimumPane + 40, center < frame.width - minimumPane - 40 else { return nil }
            return FoldSplit(axis: .vertical, hingeCenter: center)
        }
    }
}

/// A hinge crossing a view: which way it runs and where, in that view's coordinates.
struct FoldSplit: Equatable {
    enum Axis { case horizontal, vertical }
    var axis: Axis
    var hingeCenter: CGFloat
    /// The strip either side of the fold that content keeps out of.
    var band: CGFloat = 36

    var firstPaneLength: CGFloat { hingeCenter - band / 2 }
}

/// Invisible view that feeds the monitor from UIKit's hinge interaction and the window's screen.
struct HingeObserver: UIViewRepresentable {
    let monitor: HingeMonitor

    func makeUIView(context: Context) -> HingeView {
        let view = HingeView()
        view.monitor = monitor
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: HingeView, context: Context) {}

    final class HingeView: UIView {
        var monitor: HingeMonitor?
        private var installed = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishScreen()
            guard !installed, window != nil else { return }
            installed = true
            if #available(iOS 27.1, *) {
                let interaction = UIHingeInteraction { [weak self] _, update in
                    guard let monitor = self?.monitor else { return }
                    guard let hinge = update.hinge else {
                        monitor.status = .unknown
                        return
                    }
                    monitor.angle = hinge.angle
                    switch hinge.status {
                    case .closed: monitor.status = .closed
                    case .partiallyOpen: monitor.status = .partiallyOpen
                    case .fullyOpen: monitor.status = .fullyOpen
                    default: monitor.status = .unknown
                    }
                }
                addInteraction(interaction)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            publishScreen()
        }

        private func publishScreen() {
            guard let screen = window?.windowScene?.screen else { return }
            let size = screen.bounds.size
            if monitor?.screenSize != size { monitor?.screenSize = size }
        }
    }
}

/// Keeps a single piece of content in the pane above or left of the hinge while the device is bent,
/// so nothing sits on the fold. Used for the drop zone, the ready screen and the live transcription.
struct FoldPane<Content: View>: View {
    let monitor: HingeMonitor
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let split = monitor.split(for: proxy.frame(in: .global))
            switch split?.axis {
            case .horizontal?:
                VStack(spacing: 0) {
                    content().frame(height: split!.firstPaneLength)
                    Spacer(minLength: 0)
                }
            case .vertical?:
                HStack(spacing: 0) {
                    content().frame(width: split!.firstPaneLength)
                    Spacer(minLength: 0)
                }
            case nil:
                content()
            }
        }
    }
}
#endif
