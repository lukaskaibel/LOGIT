//
//  KeyboardToolbar.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 09.09.26.
//

import SwiftUI

/// The app's keyboard accessory: a row of glass capsules floating clear of the keys.
///
/// iOS draws its own glass slab behind a `.keyboard` toolbar item. That slab always sits flush
/// with the top row of keys and always takes the exact size of whatever we put inside it — so
/// padding grows the slab instead of lifting it, and content that stretches (an `HStack` with a
/// `Spacer`) dresses a single "hide the keyboard" button as a bar spanning the screen.
/// `sharedBackgroundVisibility(.hidden)` takes that slab away, which is what lets this row draw
/// its own capsules: each one hugs its buttons, so one action reads as one button, and the bottom
/// padding is real empty space, the way the bars in Notes and Reminders stand off the keyboard.
///
/// Callers compose the row themselves out of `KeyboardToolbarGroup` capsules and `Spacer()`s.
/// The house arrangement: whatever belongs to the *set* (a running rest timer, the rest editor)
/// on the leading edge, the keyboard's own controls on the trailing edge under the thumb.
///
/// Use it through `KeyboardToolbarItem` below, never by placing it in a `ToolbarItem` by hand —
/// that wrapper is what hides the system slab.
struct KeyboardToolbar<Content: View>: View {
    /// Space between the row and the top of the keyboard. Matches the standoff Notes and
    /// Reminders keep.
    private static var keyboardSpacing: CGFloat { 10 }

    /// How wide the row says it would like to be — more than any keyboard is wide.
    ///
    /// iOS 26 offered a keyboard item the whole bar, which `maxWidth: .infinity` filled. iOS 27
    /// only asks for the item's ideal width, hands back exactly that and centres it, so a row that
    /// merely *could* stretch shrank to its capsules and sat in the middle of the keys. Asking for
    /// more than there is makes the bar clamp the row to its own width instead, which puts the
    /// trailing capsules back under the thumb. It has to be finite: an infinite ideal width lays
    /// the row out at x = NaN and the app crashes.
    private static var idealWidth: CGFloat { 10000 }

    /// Reports where the capsules' bottom edge is, so a caller with a control of its own to place
    /// beside them can line it up. Measured rather than derived: the keyboard's reported frame
    /// starts a capsule's height above this row, and that gap is the system's to change.
    var onRowBottom: ((CGFloat) -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .frame(idealWidth: Self.idealWidth, maxWidth: .infinity, alignment: .trailing)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { onRowBottom?($0) }
        .padding(.bottom, Self.keyboardSpacing)
    }
}

/// One capsule of related actions inside the row. Separate jobs get separate capsules — hiding the
/// keyboard and moving to the next field are two different things and shouldn't share a slab.
struct KeyboardToolbarGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(.horizontal, 5)
        .frame(height: KEYBOARD_TOOLBAR_HEIGHT)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Height of every capsule in the row — and the size a caller's own self-styled control (the
/// recorder's live timer button) has to match to sit level with them.
let KEYBOARD_TOOLBAR_HEIGHT: CGFloat = 46

// MARK: - Scrolling a field clear of the row

/// The id of a set field's keyboard scroll target — see `keyboardScrollTarget(_:)`.
struct KeyboardScrollTarget: Hashable {
    let index: IntegerField.Index
}

/// How far below a field its scroll target reaches: the row of capsules and the gap it keeps
/// from the keys, plus a little air so the field doesn't sit flush on the capsules.
let KEYBOARD_ROW_SCROLL_CLEARANCE: CGFloat = KEYBOARD_TOOLBAR_HEIGHT + 18

extension View {
    /// Tags this field with a scroll target that runs `KEYBOARD_ROW_SCROLL_CLEARANCE` below it, so
    /// scrolling to the target's bottom leaves the field above the accessory row, not under it.
    ///
    /// The field's own frame isn't enough to scroll to. Scrolling it to the bottom of the visible
    /// area puts it on the keyboard's top edge, and the row floats above that edge — on iOS 27 the
    /// keyboard's reported frame no longer includes the row at all, so the last set's fields ended
    /// up entirely under Next and hide. A separate id keeps the field's own `.id(index)` identity
    /// untouched.
    func keyboardScrollTarget(_ index: IntegerField.Index) -> some View {
        background {
            Color.clear
                .id(KeyboardScrollTarget(index: index))
                .padding(.bottom, -KEYBOARD_ROW_SCROLL_CLEARANCE)
        }
    }
}

// MARK: - Buttons

/// One icon action in the keyboard capsule — hide the keyboard, edit the set's rest, flip a
/// weight's sign. Pass `isOn` for the ones that latch, so the row can say so in colour as well as
/// in the glyph.
struct KeyboardToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isOn: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isOn ? Color.accentColor : Color.label)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The capsule's primary action — "Next", the number pad's missing return key.
struct KeyboardToolbarTextButton: View {
    let title: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.label : Color.placeholder)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Toolbar content

/// Puts the capsule in the keyboard accessory. Goes inside a screen's own `.toolbar { … }` block
/// rather than adding a second one — a screen that hangs its keyboard item off a `toolbar`
/// modifier of its own gets no accessory at all in the editors' presentation stacks.
struct KeyboardToolbarItem<Content: View>: ToolbarContent {
    /// See `KeyboardToolbar.onRowBottom`.
    var onRowBottom: ((CGFloat) -> Void)?
    @ViewBuilder var content: Content

    var body: some ToolbarContent {
        ToolbarItem(placement: .keyboard) {
            KeyboardToolbar(onRowBottom: onRowBottom) { content }
        }
        // Without this the system draws its own slab behind the item, flush with the keys and
        // as wide as the item — the very thing the capsule replaces.
        .sharedBackgroundVisibility(.hidden)
    }
}

// MARK: - Travelling with the keyboard

extension Animation {
    /// The curve and duration UIKit is about to use for the keyboard that posted `notification`.
    ///
    /// A view that moves when the keyboard appears has to move *with* it, not merely at the same
    /// time: matching UIKit's own timing is the difference between one motion and two things
    /// happening at once. `keyboardWillShow`/`keyboardWillHide` carry both values, so run the state
    /// change inside `withAnimation(.keyboard(from:))` and the view travels on the keyboard's clock.
    ///
    /// UIKit animates the keyboard on a curve with no public case (raw value 7). Its Bézier control
    /// points are the ones below — the standard approximation, and the only part of this that isn't
    /// read straight from the notification.
    static func keyboard(from notification: Notification) -> Animation {
        let info = notification.userInfo
        let duration = info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        switch info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int {
        case UIView.AnimationCurve.easeInOut.rawValue: return .easeInOut(duration: duration)
        case UIView.AnimationCurve.easeIn.rawValue: return .easeIn(duration: duration)
        case UIView.AnimationCurve.easeOut.rawValue: return .easeOut(duration: duration)
        case UIView.AnimationCurve.linear.rawValue: return .linear(duration: duration)
        default: return .timingCurve(0.38, 0.7, 0.125, 1, duration: duration)
        }
    }
}

// MARK: - Hide the keyboard

/// The one way the app puts the keyboard away — a number pad has no return key, so every keyboard
/// accessory ends with this.
func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}
