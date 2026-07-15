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

    private var isDragging = false

    override func transformPresentedView(transform: CGAffineTransform) {
        super.transformPresentedView(transform: transform)
        let dragging = !transform.isIdentity
        if dragging != isDragging {
            isDragging = dragging
            // Tear down the tray sheet on the first drag movement, without animation:
            // a fast flick can commit the recorder's dismissal before an animated
            // teardown finishes — UIKit would then forward the dismissal to the
            // half-dismissed child and the recorder would be left stuck mid-transform.
            // Deferred one runloop tick: dismissing a child inside the pan's event
            // stack can cancel the very gesture driving the dismissal.
            if dragging {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.isDragging,
                          let child = self.presentedViewController.presentedViewController,
                          !child.isBeingDismissed
                    else { return }
                    self.presentedViewController.dismiss(animated: false)
                }
            }
            onDragChanged?(dragging)
        }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)
        onPresentationSettled?(completed)
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed {
            isDragging = false
        }
        onDismissalEnded?(completed)
    }
}

// MARK: - Header drag driver

/// Drives the recorder's interactive dismissal from a SwiftUI drag gesture on the
/// header. Transmission's own pan recognizer sits on the presented view's root, and
/// the persistent tray sheet's background-interaction passthrough only delivers
/// touches to recognizers *inside* the hosted content — the root-level pan never
/// sees them while the tray is up. This driver moves the whole screen 1:1 with the
/// finger (a real full-screen drag, not a rubber-band peek) and hands off to the
/// slide dismissal on release; the slide animator continues from the dragged position
/// so there is no jump.
final class WorkoutRecorderDragDriver {
    weak var controller: WorkoutRecorderPresentationController?

    /// Past this fraction of the screen height — or a fast enough downward flick —
    /// releasing commits the dismissal; otherwise the screen springs back up.
    private let dismissDistanceFraction: CGFloat = 0.25
    private let dismissVelocity: CGFloat = 800

    /// The built-in pan handles drags that reach it (e.g. no tray presented);
    /// don't double-drive the transform in that case.
    private var builtInPanIsActive: Bool {
        guard let pan = controller?.panGesture else { return false }
        return pan.state == .began || pan.state == .changed
    }

    func dragChanged(translation: CGSize) {
        guard let controller, !builtInPanIsActive,
              controller.presentedViewController.isBeingDismissed == false
        else { return }
        // 1:1 downward tracking. Upward drags don't move the screen (it's already
        // full-screen), so clamp to zero — matches a normal bottom sheet.
        let dy = max(0, translation.height)
        controller.transformPresentedView(
            transform: CGAffineTransform(translationX: 0, y: dy)
        )
    }

    func dragEnded(translation: CGSize, velocity: CGSize) {
        guard let controller, !builtInPanIsActive,
              controller.presentedViewController.isBeingDismissed == false
        else { return }
        let height = max(controller.presentedViewController.view.bounds.height, 1)
        let shouldDismiss = translation.height > height * dismissDistanceFraction
            || velocity.height > dismissVelocity
        if shouldDismiss {
            // Ensure no child sheet intercepts the dismissal (the tray is normally
            // already gone via the drag-start teardown, but a below-threshold drag
            // that then flicks past it can still have one attached).
            if let child = controller.presentedViewController.presentedViewController,
               !child.isBeingDismissed {
                controller.presentedViewController.dismiss(animated: false)
            }
            // Non-interactive animated dismiss: the slide animator animates the
            // presented view's transform from where the drag left it, so the screen
            // slides the rest of the way down without a jump.
            controller.presentedViewController.dismiss(animated: true)
        } else {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0
            ) {
                controller.transformPresentedView(transform: .identity)
                controller.presentedView?.layoutIfNeeded()
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
