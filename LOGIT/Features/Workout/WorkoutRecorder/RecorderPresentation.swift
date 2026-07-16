//
//  RecorderPresentation.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 15.07.26.
//

import SwiftUI
import Transmission
import UIKit

// MARK: - Environment

/// True while the user is dragging the presented recorder down (the transform phase of
/// the interactive slide dismissal, before it commits or snaps back).
struct WorkoutRecorderIsDraggingKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// True once the recorder's presentation transition has fully landed. The persistent
/// exercise tray sheet is gated on this: presenting it mid-morph would glitch the
/// transition, and it must be torn down while dragging because UIKit forwards `dismiss`
/// on a view controller to its presented child — a lingering tray would swallow the
/// interactive dismissal meant for the recorder.
///
/// Defaults to true so the screen still shows its tray when rendered outside the
/// Transmission presentation (previews, tests).
struct WorkoutRecorderIsSettledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

/// The header's drag driver; the default is inert (no controller attached), which is
/// what previews and tests rendering the screen outside the presentation get.
struct WorkoutRecorderDragDriverKey: EnvironmentKey {
    static let defaultValue = WorkoutRecorderDragDriver()
}

extension EnvironmentValues {
    var workoutRecorderIsDragging: Bool {
        get { self[WorkoutRecorderIsDraggingKey.self] }
        set { self[WorkoutRecorderIsDraggingKey.self] = newValue }
    }

    var workoutRecorderIsSettled: Bool {
        get { self[WorkoutRecorderIsSettledKey.self] }
        set { self[WorkoutRecorderIsSettledKey.self] = newValue }
    }

    var workoutRecorderDragDriver: WorkoutRecorderDragDriver {
        get { self[WorkoutRecorderDragDriverKey.self] }
        set { self[WorkoutRecorderDragDriverKey.self] = newValue }
    }
}

// MARK: - Presentation controller

/// A full-screen slide presentation controller that reports its interactive phases back
/// into SwiftUI so the recorder can hide its floating buttons, resign the keyboard and
/// tear down the exercise tray sheet exactly like the old hand-rolled draggable cover did.
/// The recorder slides up from the bottom edge and is dragged straight back down to
/// dismiss (no morph, no fade) — the behaviour the plain full-screen cover had, now
/// driven by UIKit so the drag is interactive and coordinates with the scroll view.
final class WorkoutRecorderPresentationController: SlidePresentationController {
    var onDragChanged: ((Bool) -> Void)?
    var onPresentationSettled: ((Bool) -> Void)?
    var onDismissalEnded: ((Bool) -> Void)?

    /// True while the SwiftUI drag driver owns a percent-driven dismissal session.
    private(set) var isExternalDragActive = false

    private var isPanDragging = false

    /// Reporting interactive intent while the external session calls `dismiss` makes
    /// `attach(to:)` keep the transition's `wantsInteractiveStart` on, so UIKit pauses
    /// the dismissal for scrubbing instead of playing it straight through.
    override var wantsInteractiveTransition: Bool {
        isExternalDragActive || super.wantsInteractiveTransition
    }

    /// Transmission's own pan gesture is disabled for the recorder: it does receive
    /// touches through the tray sheet's background-interaction passthrough, but its
    /// dismissal path breaks against a presented child (UIKit forwards `dismiss` to
    /// the tray). All drags are driven by `WorkoutRecorderDragDriver` instead, which
    /// handles the tray teardown before dismissing. The framework re-enables the pan
    /// after transitions, so it is forced off at every hook.
    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        panGesture.isEnabled = false
    }

    override func attach(to transition: UIPercentDrivenInteractiveTransition) {
        super.attach(to: transition)
        panGesture.isEnabled = false
    }

    // Kept for the paths where Transmission's own pan gesture does receive the touches
    // and transform-follows: mirror the drag phase into SwiftUI like the external
    // session does.
    override func transformPresentedView(transform: CGAffineTransform) {
        super.transformPresentedView(transform: transform)
        let dragging = !transform.isIdentity
        if dragging != isPanDragging {
            isPanDragging = dragging
            onDragChanged?(dragging)
        }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        panGesture.isEnabled = false
        onPresentationSettled?(completed)
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        isExternalDragActive = false
        isPanDragging = false
        onDismissalEnded?(completed)
    }

    // MARK: External drag session (driven by WorkoutRecorderDragDriver)

    /// Starts (once possible) and scrubs the percent-driven dismissal. Until the tray
    /// sheet is gone the session can't begin — UIKit forwards `dismiss` on a view
    /// controller to its presented child — so the first tick(s) request the teardown
    /// and wait; the driver keeps calling this on every gesture change.
    func driveExternalDismissal(progress: CGFloat) {
        if !isExternalDragActive {
            guard !presentedViewController.isBeingDismissed else { return }
            if let child = presentedViewController.presentedViewController {
                if !child.isBeingDismissed {
                    // Mirror the drag into SwiftUI first (drops the tray's presented
                    // binding), then remove the sheet without animation one runloop
                    // tick later — dismissing a child inside the gesture's event
                    // delivery can cancel the very touch driving the drag.
                    onDragChanged?(true)
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              let child = self.presentedViewController.presentedViewController,
                              !child.isBeingDismissed
                        else { return }
                        self.presentedViewController.dismiss(animated: false)
                    }
                }
                return
            }
            onDragChanged?(true)
            isExternalDragActive = true
            presentedViewController.dismiss(animated: true)
            guard transition != nil else {
                // The dismissal didn't start interactively — let it play out.
                isExternalDragActive = false
                return
            }
        }
        guard let transition else { return }
        transition.pause()
        transition.update(max(0, min(progress, 1)))
    }

    /// Ends the session with Transmission's own pan-gesture semantics: finish past the
    /// distance threshold or on a fast downward flick, otherwise cancel so the screen
    /// springs back up and stays presented.
    func endExternalDismissal(progress: CGFloat, velocity: CGFloat) {
        guard isExternalDragActive else { return }
        guard let transition else {
            isExternalDragActive = false
            return
        }
        let progress = max(0, min(progress, 1))
        // 1/3 of the screen, like the original draggable cover; fast flicks always
        // commit, upward release velocity always snaps back.
        let shouldFinish = (progress >= 1 / 3 && velocity >= 0) || velocity >= 800
        var completionSpeed = shouldFinish ? 1 - progress : progress
        if velocity >= 4000 {
            completionSpeed = 1
        }
        transition.completionSpeed = max(0.1, completionSpeed)
        let height = max(presentedViewController.view.bounds.height, 1)
        let remaining = (shouldFinish ? (1 - progress) : progress) * height
        let dy = remaining >= 1 ? max(-30, min(velocity / remaining, 30)) : 0
        transition.timingCurve = UISpringTimingParameters(
            dampingRatio: shouldFinish ? 1 : 0.84,
            initialVelocity: CGVector(dx: 0, dy: dy)
        )
        if shouldFinish {
            transition.finish()
        } else {
            transition.cancel()
        }
        self.transition = nil
        // dismissalTransitionDidEnd resets the session flag and reports the outcome
        // (completed == false re-presents the tray).
    }

    /// Fallback for a flick so fast the gesture ended before the interactive session
    /// could start (the tray teardown takes a runloop tick): dismiss non-interactively
    /// once the torn-down tray has fully unwound.
    func requestImmediateDismissal() {
        let recorder = presentedViewController
        guard !recorder.isBeingDismissed else { return }
        if recorder.presentedViewController != nil {
            DispatchQueue.main.async {
                guard !recorder.isBeingDismissed, recorder.presentedViewController == nil else { return }
                recorder.dismiss(animated: true)
            }
        } else {
            recorder.dismiss(animated: true)
        }
    }
}

// MARK: - Header drag driver

/// Drives the recorder's interactive dismissal from a SwiftUI drag gesture on the
/// header or set list. Transmission's own pan recognizer sits on the presented view's
/// root, and the persistent tray sheet's background-interaction passthrough only
/// delivers touches to recognizers *inside* the hosted content — the root-level pan
/// never sees them while the tray is up. This driver reproduces what that pan does:
/// it starts the dismissal as a percent-driven interactive transition and scrubs it
/// with the finger, so the screen tracks 1:1, can be dragged back up, and on release
/// either finishes or springs back — exactly like a sheet.
final class WorkoutRecorderDragDriver {
    weak var controller: WorkoutRecorderPresentationController?

    /// Fallback thresholds for a flick that ends before the interactive session could
    /// start (mirrors the session's own finish rule in `endExternalDismissal`).
    private let dismissDistanceFraction: CGFloat = 1 / 3
    private let dismissVelocity: CGFloat = 800

    /// Translation at the moment the interactive session actually starts (the tray
    /// teardown takes a runloop tick) — scrubbing measures from there, so the screen
    /// picks up at the finger without a jump.
    private var sessionBaseline: CGFloat?
    private var isSessionActive = false

    func dragChanged(translation: CGSize) {
        guard let controller else { return }
        guard isSessionActive || translation.height > 0 else { return }
        isSessionActive = true

        if controller.isExternalDragActive {
            let height = max(controller.presentedViewController.view.bounds.height, 1)
            let progress = (translation.height - (sessionBaseline ?? 0)) / height
            controller.driveExternalDismissal(progress: progress)
        } else {
            // Not started yet: keep asking; the controller begins the session once the
            // tray is torn down. Record where the finger was when it finally starts.
            controller.driveExternalDismissal(progress: 0)
            if controller.isExternalDragActive {
                sessionBaseline = translation.height
            }
        }
    }

    func dragEnded(translation: CGSize, velocity: CGSize) {
        defer {
            isSessionActive = false
            sessionBaseline = nil
        }
        guard let controller, isSessionActive else { return }

        let height = max(controller.presentedViewController.view.bounds.height, 1)
        if controller.isExternalDragActive {
            let progress = (translation.height - (sessionBaseline ?? 0)) / height
            controller.endExternalDismissal(progress: progress, velocity: velocity.height)
        } else if !controller.presentedViewController.isBeingDismissed {
            // The gesture ended before the session could start (tray teardown still in
            // flight). Fast flicks past the threshold still dismiss; anything else
            // restores the tray.
            let shouldDismiss = translation.height > height * dismissDistanceFraction
                || velocity.height > dismissVelocity
            if shouldDismiss {
                controller.requestImmediateDismissal()
            } else {
                controller.onDragChanged?(false)
            }
        }
    }
}

// MARK: - Transition

/// The recorder's presentation: a full-screen cover that slides up from the bottom
/// edge and is dragged straight back down to dismiss — no morph, no fade. Delegates
/// all animation work to Transmission's slide transition and only swaps in the
/// phase-reporting presentation controller above.
struct WorkoutRecorderTransition: PresentationLinkTransitionRepresentable {
    let options: SlidePresentationLinkTransition.Options
    let dragDriver: WorkoutRecorderDragDriver
    let onDragChanged: (Bool) -> Void
    let onPresentationSettled: (Bool) -> Void
    let onDismissalEnded: (Bool) -> Void

    private var base: SlidePresentationLinkTransition {
        SlidePresentationLinkTransition(options: options)
    }

    func makeUIPresentationController(
        presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController,
        context: Context
    ) -> WorkoutRecorderPresentationController {
        let controller = WorkoutRecorderPresentationController(
            edge: options.edge,
            prefersScaleEffect: options.prefersScaleEffect,
            preferredFromCornerRadius: options.preferredFromCornerRadius,
            preferredToCornerRadius: options.preferredToCornerRadius,
            presentedViewController: presented,
            presenting: presenting
        )
        assignCallbacks(to: controller)
        return controller
    }

    func updateUIPresentationController(
        presentationController: WorkoutRecorderPresentationController,
        context: Context
    ) {
        base.updateUIPresentationController(
            presentationController: presentationController,
            context: context
        )
        assignCallbacks(to: presentationController)
    }

    func updateHostingController<Content: View>(
        presenting: PresentationHostingController<Content>,
        context: Context
    ) {
        base.updateHostingController(presenting: presenting, context: context)
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        presentationController: UIPresentationController,
        context: Context
    ) -> SlidePresentationControllerTransition? {
        base.animationController(
            forPresented: presented,
            presenting: presenting,
            presentationController: presentationController,
            context: context
        )
    }

    func animationController(
        forDismissed dismissed: UIViewController,
        presentationController: UIPresentationController,
        context: Context
    ) -> SlidePresentationControllerTransition? {
        base.animationController(
            forDismissed: dismissed,
            presentationController: presentationController,
            context: context
        )
    }

    private func assignCallbacks(to controller: WorkoutRecorderPresentationController) {
        controller.onDragChanged = onDragChanged
        controller.onPresentationSettled = onPresentationSettled
        controller.onDismissalEnded = onDismissalEnded
        dragDriver.controller = controller
    }
}

extension PresentationLinkTransition {
    static func workoutRecorder(
        dragDriver: WorkoutRecorderDragDriver,
        onDragChanged: @escaping (Bool) -> Void,
        onPresentationSettled: @escaping (Bool) -> Void,
        onDismissalEnded: @escaping (Bool) -> Void
    ) -> PresentationLinkTransition {
        .custom(
            options: .init(
                isInteractive: true,
                modalPresentationCapturesStatusBarAppearance: true,
                // Pure black, not `.background`: the recorder is presented modally, so
                // `systemBackground` resolves to its elevated grey (28,28,30) here.
                preferredPresentationBackgroundColor: .black
            ),
            WorkoutRecorderTransition(
                options: .init(
                    // Slide up from / drag down to the bottom edge.
                    edge: .bottom,
                    // No card-scaling of the app behind — a plain full-screen cover,
                    // like the recorder always had; dragging down reveals the tab
                    // screen behind it, static.
                    prefersScaleEffect: false,
                    // Corner radii default to the screen's radius while sliding /
                    // dragging and settle to square when fully presented — matching
                    // the old cover, which only rounded its corners mid-drag.
                    preferredFromCornerRadius: nil,
                    preferredToCornerRadius: nil,
                    hapticsStyle: .light
                ),
                dragDriver: dragDriver,
                onDragChanged: onDragChanged,
                onPresentationSettled: onPresentationSettled,
                onDismissalEnded: onDismissalEnded
            )
        )
    }
}
