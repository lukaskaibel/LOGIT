//
//  ChartTapSelection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.09.26.
//

import Charts
import SwiftUI
import UIKit

extension View {
    /// Lets a plain tap select a value on a chart that already reads a selection through
    /// `chartXSelection(value:)`, and lets a tap anywhere outside the chart put it away again.
    ///
    /// Swift Charts' own selection gesture is a press-and-hold scrub: on a scrollable chart a quick
    /// tap does nothing at all, because the short drag belongs to the scroll view, and the framework
    /// only starts scrubbing once the finger has stayed put long enough to prove it isn't scrolling.
    /// Every inspectable chart in the app therefore needed a hold, which is not how a bar chart reads
    /// to anyone who just wants to know what a bar says.
    ///
    /// The tap has to be added **without touching the framework's gesture**, and the two obvious
    /// routes both break it:
    /// - `chartGesture` + `proxy.selectXValue(at:)` *replaces* the built-in gesture: the scrub is
    ///   gone, and rebuilding it with a `LongPressGesture` stops the chart scrolling altogether,
    ///   because a long press claims the touch the instant a finger lands.
    /// - A tappable `chartOverlay` sits above the chart's scroll view, so a swipe never reaches it —
    ///   the chart stops scrolling and iOS's swipe-back takes the pan instead.
    ///
    /// So the overlay here is inert, and only lends its `ChartProxy` to turn a position into a value.
    /// The tap itself is *observed* from the window (see `ChartTapObserver`), never claimed: the
    /// framework keeps its scrub and its scroll exactly as they were. The value goes into the **same**
    /// binding the scrub writes, so each chart's existing snapping (nearest bar, nearest point)
    /// applies to taps unchanged.
    ///
    /// A scrub puts its selection away when the finger lifts; a tap has no such moment, and Charts
    /// offers no way to put it away. So while `selection` holds a value, the next tap that lands
    /// outside the chart — on the page around it, a button, anywhere — clears it. That tap still does
    /// whatever it was going to do.
    func chartTapSelection<Value: Plottable>(_ selection: Binding<Value?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                ChartTapObserver(
                    onTapInside: { location in
                        // Resolved at tap time, not captured at layout: on a scrollable chart the plot
                        // frame is the whole scrollable plot, and its origin moves as the chart scrolls
                        // — measuring from where it is *now* lands the tap on the value under the finger.
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        guard let value: Value = proxy.value(atX: x) else { return }
                        selection.wrappedValue = value
                    },
                    onTapOutside: {
                        guard selection.wrappedValue != nil else { return }
                        selection.wrappedValue = nil
                    }
                )
                .allowsHitTesting(false)
            }
        }
    }
}

/// Reports taps that land inside or outside the view's frame, without ever taking part in touch
/// handling.
///
/// SwiftUI has no "tap outside" hook, and anything that *receives* touches over a chart steals them
/// from the chart. So this installs a plain `UITapGestureRecognizer` on the window itself that
/// recognises alongside everything else and never cancels or delays a touch: buttons, scroll views
/// and the chart's own gestures see every tap exactly as they would without it. The view itself is
/// inert (no hit testing); it exists to report its own frame, which follows the chart as the page
/// scrolls. The recognizer leaves the window with the view — a pushed-away screen or an unselected
/// tab is taken out of the window, so only charts actually on screen listen.
private struct ChartTapObserver: UIViewRepresentable {
    var onTapInside: (CGPoint) -> Void
    var onTapOutside: () -> Void

    func makeUIView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onTapInside = onTapInside
        view.onTapOutside = onTapOutside
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.uninstall()
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var onTapInside: (CGPoint) -> Void = { _ in }
        var onTapOutside: () -> Void = {}

        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        private weak var installedWindow: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window !== installedWindow else { return }
            uninstall()
            window?.addGestureRecognizer(recognizer)
            installedWindow = window
        }

        func uninstall() {
            installedWindow?.removeGestureRecognizer(recognizer)
            installedWindow = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let window else { return }
            let location = recognizer.location(in: self)
            if bounds.contains(location), landsOnThisScreen(recognizer.location(in: window), in: window) {
                onTapInside(location)
            } else {
                onTapOutside()
            }
        }

        /// Whether the tap actually reached the screen this chart is on, rather than something
        /// covering it — a sheet over the chart puts its own content where the chart's frame still is.
        private func landsOnThisScreen(_ point: CGPoint, in window: UIWindow) -> Bool {
            guard let hit = window.hitTest(point, with: nil) else { return false }
            return hit.owningViewController === owningViewController
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    /// The nearest view controller up the responder chain.
    var owningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
