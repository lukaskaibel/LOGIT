//
//  OnDeleteModifier.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.07.23.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Swipe-to-delete for a row that isn't in a `List`, drawn the way a list's swipe action is: the
/// row slides left over a red Delete capsule, a tap on the capsule deletes, and a swipe carried on
/// past the middle of the row deletes on release.
///
/// It used to borrow the real thing — the row rendered twice, once invisibly to measure it and once
/// inside a one-row `List` that contributed nothing but the swipe action. That made every set row
/// in the recorder a UIKit collection view of its own and doubled every field in it: thirty sets
/// were sixty set rows, a few hundred fields and thirty collection views, all re-laid out on every
/// change, which is a large part of what made the recorder stutter. Now the row is drawn once and
/// a horizontal pan is all the swipe adds.
struct OnDeleteModifier: ViewModifier {
    let action: () -> Void

    /// How far the row is pushed left. Zero at rest, `openOffset` with the capsule showing.
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @State private var rowWidth: CGFloat = 0
    /// Past the full-swipe line, where letting go deletes — the haptic marks the crossing.
    @State private var isPastFullSwipe = false
    /// Identifies this row to the others, so opening one closes whichever was open before.
    @State private var rowID = UUID()

    private static let buttonWidth: CGFloat = 86
    private static let buttonInset: CGFloat = 8
    /// The row's position with the Delete capsule fully showing.
    private static var openOffset: CGFloat { -(buttonWidth + 2 * buttonInset) }

    /// Letting go beyond this deletes: past the middle of the row, and always well past the open
    /// position so that opening it never deletes by accident.
    private var fullSwipeOffset: CGFloat {
        min(-rowWidth * 0.55, Self.openOffset * 1.6)
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            // While open, a tap on the row only closes it, the way a list row's does — it must
            // not land on a field and bring the keyboard up under a half-hidden row.
            .overlay {
                if isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { close() }
                }
            }
            .background(alignment: .trailing) {
                deleteButton
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .gesture(
                HorizontalSwipeRecognizer(
                    allowsRightward: isOpen || offset < 0,
                    onChanged: dragChanged,
                    onEnded: dragEnded
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .swipeToDeleteRowOpened)) { notification in
                guard isOpen, notification.object as? UUID != rowID else { return }
                close()
            }
    }

    /// Grows out of the row's trailing edge as the row slides, the way a list's action does, and
    /// stretches on past its own width when the swipe keeps going.
    private var deleteButton: some View {
        let width = max(0, -offset - 2 * Self.buttonInset)
        return Button {
            delete()
        } label: {
            Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                .font(.body)
                .foregroundStyle(.white)
                .labelStyle(.titleAndIcon)
                .fixedSize()
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(Color.red, in: Capsule())
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .padding(.trailing, Self.buttonInset)
        .opacity(width > 1 ? 1 : 0)
        .accessibilityIdentifier("swipeToDeleteButton")
        .accessibilityHidden(!isOpen)
    }

    // MARK: - Gesture

    private func dragChanged(_ translation: CGFloat) {
        let start = isOpen ? Self.openOffset : 0
        var proposed = start + translation
        // Rightward past rest only gives a little, like a list row does.
        if proposed > 0 { proposed = proposed / 6 }
        offset = max(proposed, -rowWidth)
        let isPast = offset < fullSwipeOffset
        if isPast != isPastFullSwipe {
            isPastFullSwipe = isPast
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func dragEnded(_ translation: CGFloat, velocity: CGFloat) {
        if offset < fullSwipeOffset {
            delete()
        } else if velocity < -500 || (offset < Self.openOffset / 2 && velocity < 300) {
            open()
        } else {
            close()
        }
        isPastFullSwipe = false
    }

    private func open() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            offset = Self.openOffset
            isOpen = true
        }
        NotificationCenter.default.post(name: .swipeToDeleteRowOpened, object: rowID)
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            offset = 0
            isOpen = false
        }
    }

    /// The row leaves to the left before it goes, so it reads as swiped away rather than vanishing
    /// in place.
    private func delete() {
        withAnimation(.easeOut(duration: 0.18)) {
            offset = -max(rowWidth, -Self.openOffset)
        }
        isOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            action()
        }
    }
}

extension Notification.Name {
    /// A swipe-to-delete row opened; the object is its id. Any other open row closes.
    fileprivate static let swipeToDeleteRowOpened = Notification.Name("swipeToDeleteRowOpened")
}

/// A pan that only ever starts sideways — leftward, or rightward too while the row is open — so a
/// vertical drag stays the scroll view's, and taps, long presses and context menus are untouched.
private struct HorizontalSwipeRecognizer: UIGestureRecognizerRepresentable {
    var allowsRightward: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> SwipeOnlyPanRecognizer {
        let recognizer = SwipeOnlyPanRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: SwipeOnlyPanRecognizer, context: Context) {
        context.coordinator.allowsRightward = allowsRightward
    }

    func handleUIGestureRecognizerAction(_ recognizer: SwipeOnlyPanRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    /// A pan that gives up on a finger that rests. A plain pan stays undecided for as long as a
    /// finger is down without moving, and the row's context menu waits for it to decide — so a
    /// long press on a set never opened its menu. Swipes start moving at once; a finger still in
    /// place after a moment is a press, and this steps aside for it.
    final class SwipeOnlyPanRecognizer: UIPanGestureRecognizer {
        private var restingTimer: Timer?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            restingTimer?.invalidate()
            restingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                guard let self, self.state == .possible else { return }
                self.state = .failed
            }
        }

        override func reset() {
            super.reset()
            restingTimer?.invalidate()
            restingTimer = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var allowsRightward = false

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
            return velocity.x < 0 || allowsRightward
        }
    }
}

extension View {
    func onDeleteView(disabled: Bool = false, perform action: @escaping () -> Void) -> some View {
        Group {
            if disabled {
                self
            } else {
                self.modifier(OnDeleteModifier(action: action))
            }
        }
    }
}
