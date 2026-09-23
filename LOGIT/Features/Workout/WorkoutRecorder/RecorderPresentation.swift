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

/// True once the recorder's presentation transition has fully landed. The persistent
/// exercise tray sheet is gated on this: presenting it mid-slide would glitch the
/// transition, and it must be gone before the recorder is dismissed because UIKit
/// forwards `dismiss` on a view controller to its presented child — a lingering tray
/// would swallow the dismissal meant for the recorder.
///
/// Defaults to true so the screen still shows its tray when rendered outside the
/// Transmission presentation (previews, tests).
struct WorkoutRecorderIsSettledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

/// The recorder's drag driver; the default is inert (no controller attached), which is
/// what previews and tests rendering the screen outside the presentation get.
struct WorkoutRecorderDragDriverKey: EnvironmentKey {
    static let defaultValue = WorkoutRecorderDragDriver()
}

extension EnvironmentValues {
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

/// A full-screen slide presentation controller for the recorder: it slides up from the
/// bottom edge, and a drag pulls it back down.
///
/// The drag is purely visual until the finger lifts. While it is in flight the recorder
/// — and the exercise tray sheet with it — just follow the finger as a layer transform:
/// no dismissal is started, no SwiftUI state changes, nothing is torn down. That is what
/// makes it a real drag you can pull back up and let go of. Only a release far enough
/// down commits: the screen finishes sliding off, and only then is the tray removed and
/// the recorder dismissed underneath (UIKit forwards `dismiss` to a presented child, so
/// the tray has to go first — and tearing it down while the finger was still down is
/// what used to cancel the gesture and minimize the recorder on the spot).
final class WorkoutRecorderPresentationController: SlidePresentationController {
    var onPresentationSettled: ((Bool) -> Void)?
    var onDismissalEnded: ((Bool) -> Void)?
    /// Removes the exercise tray sheet (unanimated) ahead of a committed drag dismissal.
    var onTrayTeardownRequested: (() -> Void)?

    /// True from the drag's first movement until its release animation has finished.
    private(set) var isDragging = false

    /// Transmission's own pan gesture is disabled for the recorder: it does receive
    /// touches through the tray sheet's background-interaction passthrough, but its
    /// dismissal path breaks against a presented child (UIKit forwards `dismiss` to
    /// the tray), and it would start the dismissal mid-gesture. Drags come from
    /// `WorkoutRecorderDragDriver` instead. The framework re-enables the pan after
    /// transitions, so it is forced off at every hook.
    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        panGesture.isEnabled = false
    }

    override func attach(to transition: UIPercentDrivenInteractiveTransition) {
        super.attach(to: transition)
        panGesture.isEnabled = false
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        panGesture.isEnabled = false
        onPresentationSettled?(completed)
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        isDragging = false
        onDismissalEnded?(completed)
    }

    // MARK: Drag

    /// Whether a drag may pick the recorder up right now: fully presented, not on its
    /// way out, and not already settling from a previous drag.
    var canBeginDrag: Bool {
        !presentedViewController.isBeingPresented
            && !presentedViewController.isBeingDismissed
            && !isSettlingDrag
    }

    private var isSettlingDrag = false

    /// The tray sheet's container: it lives in its own presentation, so it has to be
    /// moved alongside the recorder to read as part of it.
    private var trayContainerView: UIView? {
        presentedViewController.presentedViewController?.presentationController?.containerView
    }

    private var dragHeight: CGFloat {
        max(containerView?.bounds.height ?? presentedViewController.view.bounds.height, 1)
    }

    /// Moves the recorder (and its tray) `offset` points down from its resting place.
    func dragChanged(offset: CGFloat) {
        guard let presentedView else { return }
        if !isDragging {
            guard canBeginDrag else { return }
            isDragging = true
            // Rounded like the screen while it's off its resting place, as the slide
            // transition does.
            CornerRadiusOptions.RoundedRectangle.screen(min: 0).apply(to: presentedView)
        }
        let transform = CGAffineTransform(translationX: 0, y: max(offset, 0))
        presentedView.transform = transform
        trayContainerView?.transform = transform
    }

    /// Settles a drag: slides the recorder off and dismisses it when `commit` is true,
    /// otherwise springs it back into place.
    func dragEnded(offset: CGFloat, velocity: CGFloat, commit: Bool) {
        guard isDragging, let presentedView else { return }
        isSettlingDrag = true
        let target: CGFloat = commit ? dragHeight : 0
        let remaining = abs(target - max(offset, 0))
        let springVelocity = remaining >= 1 ? max(-30, min(velocity / remaining, 30)) : 0
        let tray = trayContainerView
        UIView.animate(
            withDuration: commit ? 0.38 : 0.42,
            delay: 0,
            usingSpringWithDamping: commit ? 1 : 0.84,
            initialSpringVelocity: commit ? max(springVelocity, 0) : abs(springVelocity),
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            let transform = CGAffineTransform(translationX: 0, y: target)
            presentedView.transform = transform
            tray?.transform = transform
        } completion: { [weak self] _ in
            guard let self else { return }
            if commit {
                self.dismissAfterTrayTeardown()
            } else {
                CornerRadiusOptions.RoundedRectangle.identity.apply(to: presentedView)
                self.isDragging = false
                self.isSettlingDrag = false
            }
        }
    }

    /// The recorder is off screen now; take the tray down, wait for it to be gone, then
    /// dismiss the recorder itself. The slide-out has nothing left to animate — the
    /// dismissal animates the same transform the drag already reached.
    private func dismissAfterTrayTeardown(attempt: Int = 0) {
        let recorder = presentedViewController
        guard !recorder.isBeingDismissed else { return }
        if let child = recorder.presentedViewController {
            if attempt == 0 {
                onTrayTeardownRequested?()
            } else if attempt == 30, !child.isBeingDismissed {
                // SwiftUI never took it down (should not happen) — do it directly.
                recorder.dismiss(animated: false)
            } else if attempt == 120 {
                // Still covered: bring the recorder back rather than leave it presented
                // off screen, where it would block the app behind it.
                isSettlingDrag = false
                dragEnded(offset: dragHeight, velocity: 0, commit: false)
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.dismissAfterTrayTeardown(attempt: attempt + 1)
            }
            return
        }
        isSettlingDrag = false
        recorder.dismiss(animated: true)
    }
}

// MARK: - Drag driver

/// Connects the recorder's SwiftUI drag gestures (on the set list and the header) to
/// the presentation controller. Transmission's own pan recognizer sits on the presented
/// view's root, and the persistent tray sheet's background-interaction passthrough only
/// delivers touches to recognizers *inside* the hosted content — the root-level pan
/// never sees them while the tray is up, so the drag has to come from SwiftUI.
///
/// A drag always tracks the finger 1:1 and is decided on release, by distance: a release
/// past `commitFraction` of the screen minimizes the recorder, anything short of it — or a
/// release while moving back up — springs it back. Speed never helps a release commit; a
/// release still flicking fast even needs `flickCommitFraction`, so a quick swipe can't
/// minimize the workout.
final class WorkoutRecorderDragDriver {
    weak var controller: WorkoutRecorderPresentationController?

    /// How far down (as a share of the screen height) a release has to be to minimize.
    static let commitFraction: CGFloat = 1 / 3
    /// The same for a release that is still flicking down faster than `flickVelocity`.
    static let flickCommitFraction: CGFloat = 1 / 2
    static let flickVelocity: CGFloat = 1500

    private var isActive = false
    private var isPastCommit = false
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    /// Whether the recorder can be picked up by a drag right now.
    var canBeginDrag: Bool {
        controller?.canBeginDrag ?? false
    }

    /// `translation` is measured from where the drag picked the recorder up.
    func dragChanged(translation: CGFloat) {
        guard let controller else { return }
        if !isActive {
            guard controller.canBeginDrag else { return }
            isActive = true
            isPastCommit = false
            feedback.prepare()
        }
        controller.dragChanged(offset: translation)
        // A tick when the release would start to minimize, and again when it no longer would.
        let pastCommit = translation >= screenHeight(for: controller) * Self.commitFraction
        if pastCommit != isPastCommit {
            isPastCommit = pastCommit
            feedback.impactOccurred()
        }
    }

    func dragEnded(translation: CGFloat, velocity: CGFloat) {
        guard isActive, let controller else { return }
        isActive = false
        let fraction = velocity > Self.flickVelocity ? Self.flickCommitFraction : Self.commitFraction
        let commit = translation >= screenHeight(for: controller) * fraction && velocity > -200
        controller.dragEnded(offset: translation, velocity: velocity, commit: commit)
    }

    /// The gesture was cancelled (another gesture or the system took the touch): put the
    /// recorder back.
    func dragCancelled() {
        guard isActive, let controller else { return }
        isActive = false
        controller.dragEnded(offset: 0, velocity: 0, commit: false)
    }

    private func screenHeight(for controller: WorkoutRecorderPresentationController) -> CGFloat {
        max(controller.containerView?.bounds.height ?? controller.presentedViewController.view.bounds.height, 1)
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
    let onTrayTeardownRequested: () -> Void
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
        controller.onTrayTeardownRequested = onTrayTeardownRequested
        controller.onPresentationSettled = onPresentationSettled
        controller.onDismissalEnded = onDismissalEnded
        dragDriver.controller = controller
    }
}

extension PresentationLinkTransition {
    static func workoutRecorder(
        dragDriver: WorkoutRecorderDragDriver,
        onTrayTeardownRequested: @escaping () -> Void,
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
                onTrayTeardownRequested: onTrayTeardownRequested,
                onPresentationSettled: onPresentationSettled,
                onDismissalEnded: onDismissalEnded
            )
        )
    }
}
