//
//  IntegerField.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 16.01.23.
//

import Combine
import SwiftUI

struct IntegerField: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @Environment(\.setFieldFocusRelay) private var focusRelay
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    // MARK: - Parameters

    let placeholder: Int64
    /// Untracked, like the focus below: the row that draws this field observes the entry and hands
    /// it a fresh field whenever the value changes, so the field never has to watch it itself.
    @UntrackedBinding var value: Int64
    let maxDigits: Int?
    let index: Index
    @UntrackedBinding var focusedIntegerFieldIndex: Index?
    var unit: String? = "kg"
    var trend: SetValueComparison? = nil
    var trendText: String = ""
    var trendColor: Color = .accentColor
    var previousValueText: String? = nil
    var onTapPreviousValue: (() -> Void)? = nil

    // MARK: - State

    @State private var valueString: String = ""
    @FocusState private var isFocused: Bool
    /// Whether a real text field is in place — only while this field has the keyboard, or is about
    /// to get it. See `SetFieldTextInput`.
    @State private var isEditing = false

    // MARK: - Body

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                if canEdit && (isEditing || isVoiceOverEnabled) {
                    TextField(
                        String(placeholder),
                        text: $valueString,
                        prompt: Text(String(placeholder)).foregroundStyle(isFocused ? Color(UIColor.systemGray2) : Color.placeholder)
                    )
                    .focused($isFocused)
                    .onChange(of: valueString) { _, newString in
                        valueString = (newString == "0" || newString.isEmpty) ? "" : String(newString.prefix(4))
                        if let valueInt = Int64(valueString), valueInt != value {
                            value = valueInt
                        } else if valueString.isEmpty && value != 0 {
                            value = 0
                        }
                    }
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .keyboardType(.numberPad)
                    .onAppear { if isEditing { isFocused = true } }
                    .transition(.identity)
                } else if canEdit {
                    SetFieldRestingText(
                        text: valueString,
                        prompt: String(placeholder)
                    )
                } else {
                    Text(valueString)
                        .foregroundColor(isEmpty ? .placeholder : .primary)
                }
            }
            .font(.system(.title3, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .fixedSize()
            Text(unit?.uppercased() ?? "")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundColor(isFocused ? (isEmpty ? Color(UIColor.systemGray) : Color(UIColor.systemGray3)) : isEmpty ? .placeholder : .secondary)
        }
        .fixedSize()
        .onAppear {
            valueString = text(for: value)
            if focusRelay?.current == index { beginEditing() }
        }
        .onSetFieldFocusChange(focusRelay) { newValue in
            switch SetFieldFocusMove(to: newValue, for: index, isFocused: isFocused) {
            case .claim: beginEditing()
            case .release: isFocused = false
            case .none: break
            }
        }
        .onChange(of: isFocused) { _, newValue in
            if newValue {
                UISelectionFeedbackGenerator().selectionChanged()
                // Only update binding if we're gaining focus and not already set
                if focusedIntegerFieldIndex != index {
                    focusedIntegerFieldIndex = index
                }
            } else {
                // When losing focus, don't update the binding - another field is taking over.
                // Text again once the unfocus spring has settled — see `SetFieldRestingText.swapDelay`.
                DispatchQueue.main.asyncAfter(deadline: .now() + SetFieldRestingText.swapDelay) {
                    if !isFocused { isEditing = false }
                }
            }
        }
        .onChange(of: value) { _, newValue in
            if text(for: newValue) != valueString {
                valueString = text(for: newValue)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .secondaryTileStyle(backgroundColor: isFocused ? Color.white : Color.black.opacity(0.000001))
        .setValueIndicator(
            trend: trend,
            trendText: trendText,
            positiveColor: trendColor,
            previousValueText: previousValueText,
            showPreviousValue: isEmpty,
            onTapPreviousValue: onTapPreviousValue,
            isVisible: canEdit
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0), value: isFocused)
        .frame(minWidth: 100, alignment: .trailing)
        .onTapGesture {
            beginEditing()
        }
        .id(index)
        .keyboardScrollTarget(index)
    }

    /// The text for `value`. An editable field leaves zero empty, so its prompt shows — what the
    /// text field's own input filter does to a typed "0", done here because at rest there is no
    /// text field to do it.
    private func text(for value: Int64) -> String {
        canEdit && value == 0 ? "" : String(value)
    }

    /// Puts the real text field in place and gives it the keyboard — straight away when it is
    /// already there, else as soon as it appears.
    private func beginEditing() {
        guard canEdit else { return }
        if isEditing || isVoiceOverEnabled {
            isFocused = true
        } else {
            isEditing = true
        }
    }

    // MARK: - Computed Properties

    private var isEmpty: Bool {
        Int(valueString) == 0 || valueString.isEmpty
    }

    /// Identity of one input field: the set it belongs to, the entry within the set, and the
    /// field within the entry. The set is keyed by its stable entity UUID — NOT by its flat
    /// position in the workout, which shifts whenever sets are added, removed, or reordered.
    /// Position keys let two views that rendered at different times disagree about which set
    /// an index means, and the field whose (stale) index matched the tapped field's would
    /// steal the keyboard — typing landed in a different set than the one tapped.
    struct Index: Equatable, Hashable {
        let setID: UUID
        var secondary: Int = 0
        var tertiary: Int = 0
    }
}

// MARK: - Focus plumbing

/// A binding a view can hold without SwiftUI counting it among the view's inputs.
///
/// A `@Binding` re-renders the view holding it whenever the bound value changes — whether its body
/// reads the value or not. The set lists thread the keyboard's focus index, and every field its
/// value, through each card, set row and field, so with plain bindings one focus move re-rendered
/// every view on the way: a few hundred, the whole list, for a single tap of Next. Through this
/// wrapper the binding reads and writes exactly the same state, but a view only re-renders when it
/// is handed new arguments or something it actually observes changes. The fields learn about focus
/// moves from `SetFieldFocusRelay` instead.
@propertyWrapper
struct UntrackedBinding<Value> {
    // Closures, not the `Binding` itself: a stored `Binding` is a dynamic property SwiftUI would go
    // looking for, which is the whole thing this avoids.
    private let read: () -> Value
    private let write: (Value) -> Void

    init(_ binding: Binding<Value>) {
        read = { binding.wrappedValue }
        write = { binding.wrappedValue = $0 }
    }

    /// A value nothing can change — what a read-only field is given.
    static func constant(_ value: Value) -> UntrackedBinding<Value> {
        UntrackedBinding(.constant(value))
    }

    var wrappedValue: Value {
        get { read() }
        nonmutating set { write(newValue) }
    }

    /// Passed on as it is, so a view hands its own `$binding` to the next one down.
    var projectedValue: UntrackedBinding<Value> { self }
}

extension Binding {
    /// This binding for a view that must not re-render when its value changes. See `UntrackedBinding`.
    var untracked: UntrackedBinding<Value> { UntrackedBinding(self) }
}

/// Tells the set fields where the keyboard's focus has moved.
///
/// The focus index lives in the screen that owns the keyboard (the recorder, the workout and
/// template editors), and every field has to know when it becomes — or stops being — the focused
/// one. Reading it through a binding made every field, and every view the binding passed through,
/// re-render on each move (see `UntrackedBinding`). The relay hands the move to each field as an
/// event instead, so only the field losing the keyboard and the one gaining it ever change.
///
/// Installed with `relaysSetFieldFocus(_:through:)` where the focus state lives.
final class SetFieldFocusRelay {
    /// The focused field, as last announced — for fields that appear after the move.
    private(set) var current: IntegerField.Index?
    let changes = PassthroughSubject<IntegerField.Index?, Never>()

    func announce(_ index: IntegerField.Index?) {
        current = index
        changes.send(index)
    }

    /// For fields outside any screen that relays focus: nothing ever moves.
    fileprivate static let silent = SetFieldFocusRelay()
}

private struct SetFieldFocusRelayKey: EnvironmentKey {
    static let defaultValue: SetFieldFocusRelay? = nil
}

extension EnvironmentValues {
    var setFieldFocusRelay: SetFieldFocusRelay? {
        get { self[SetFieldFocusRelayKey.self] }
        set { self[SetFieldFocusRelayKey.self] = newValue }
    }
}

/// The one view that follows the focus state itself, and passes each move on to the fields.
private struct SetFieldFocusRelaying: ViewModifier {
    @Binding var focus: IntegerField.Index?
    let relay: SetFieldFocusRelay

    func body(content: Content) -> some View {
        content
            .environment(\.setFieldFocusRelay, relay)
            .onChange(of: focus, initial: true) { _, newValue in
                relay.announce(newValue)
            }
    }
}

extension View {
    /// Lets the set fields below follow `focus` without re-rendering anything on the way to them.
    /// Apply it where the focus state lives. See `SetFieldFocusRelay`.
    func relaysSetFieldFocus(
        _ focus: Binding<IntegerField.Index?>,
        through relay: SetFieldFocusRelay
    ) -> some View {
        modifier(SetFieldFocusRelaying(focus: focus, relay: relay))
    }

    /// Runs `action` whenever the keyboard moves between set fields (nil: no field has it) — the
    /// way for a view to react to focus without holding it. Silent outside a relaying screen.
    func onSetFieldFocusChange(
        _ relay: SetFieldFocusRelay?,
        perform action: @escaping (IntegerField.Index?) -> Void
    ) -> some View {
        onReceive((relay ?? .silent).changes, perform: action)
    }
}

/// What a set field does when the keyboard moves: claim it when it is the target, give it up when
/// the keyboard is put away. Moving *to another field* deliberately leaves this one alone — the new
/// field taking first responder is what ends this one's, which keeps UIKit's hand-over smooth (and
/// the keyboard up).
enum SetFieldFocusMove {
    case claim
    case release
    case none

    init(to newValue: IntegerField.Index?, for index: IntegerField.Index, isFocused: Bool) {
        if newValue == index {
            self = isFocused ? .none : .claim
        } else if newValue == nil, isFocused {
            self = .release
        } else {
            self = .none
        }
    }
}

/// A set field at rest: what its text field shows, drawn as plain text.
///
/// A set list holds a field for every value of every set — seventy-odd in a long workout — and each
/// one was a live `UITextField`. Every presentation over the recorder, tray detent change and
/// keyboard appearance made all of them restyle and re-measure themselves, which was a large share
/// of the stall under each of those. Only the field that has the keyboard needs to be one; the
/// rest look exactly the same as text, and swap the real field in the moment they are tapped or
/// moved to.
///
/// To accessibility (and the UI tests) it still presents as the text field it stands in for, with
/// the same value, and tapping it focuses the real one. VoiceOver users keep real fields throughout.
struct SetFieldRestingText: View {
    /// How long a field that lost the keyboard keeps its real text field before turning back into
    /// text: until its unfocus spring has settled. A text field rides that spring as one moving
    /// layer; text swapped in mid-spring would be redrawn on every frame of it.
    static let swapDelay: TimeInterval = 0.6

    let text: String
    let prompt: String

    var body: some View {
        Text(text.isEmpty ? prompt : text)
            .foregroundStyle(text.isEmpty ? Color.placeholder : Color.white)
            .accessibilityRepresentation {
                TextField(prompt, text: .constant(text))
            }
            // The swap with the real field is instant, never a cross-fade.
            .transition(.identity)
    }
}

// MARK: - Set Value Trend Indicator

/// How a set's value compares with the previous workout's: which way the number moved, and
/// whether that direction is the goal.
///
/// The two are separate on purpose. A sprinter who runs 12 s instead of 13 has a *smaller*
/// number and a *better* one; negating the number to make the arrow point up would put a rising
/// arrow next to a falling time. The arrow follows the number, the colour follows the goal.
struct SetValueComparison: Equatable {
    enum Direction { case up, down }
    let direction: Direction
    let isImprovement: Bool

    /// The number rose, and rising is the goal — every field except a `.faster` duration.
    static let improved = SetValueComparison(direction: .up, isImprovement: true)
    /// The number fell, and falling is not the goal.
    static let declined = SetValueComparison(direction: .down, isImprovement: false)
    /// The number fell, and falling *is* the goal: a quicker sprint.
    static let improvedDownward = SetValueComparison(direction: .down, isImprovement: true)
    /// The number rose on an exercise where less is better: a slower sprint.
    static let declinedUpward = SetValueComparison(direction: .up, isImprovement: false)
}

/// A small up/down arrow plus the absolute difference versus the previous workout's
/// value for a single set field. An improvement uses the exercise's muscle-group
/// color; anything else is muted gray. The arrow always points the way the number moved.
struct SetValueDeltaLabel: View {
    let comparison: SetValueComparison
    let text: String
    var positiveColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 1) {
            Image(
                systemName: comparison.direction == .up
                    ? "arrow.up"
                    : "arrow.down"
            )
            .font(.system(size: 7, weight: .bold))
            Text(text)
        }
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(comparison.isImprovement ? positiveColor : Color.secondary)
        .lineLimit(1)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// A clock symbol plus the previous workout's value for a single set field, shown in the
/// same spot as `SetValueDeltaLabel` while the field has no entry yet. Unit-less and all
/// gray, since the field right next to it already shows the unit. Tapping it opens the
/// previous attempts for the exercise.
struct PreviousSetValueLabel: View {
    let text: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onTap?()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "clock")
                    .font(.system(size: 7, weight: .bold))
                Text(text)
            }
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel(
            Text(NSLocalizedString("lastSetReferencePrefix", comment: "") + " " + text)
        )
    }
}

/// Whether the set fields draw their previous-workout indicators at all.
///
/// Off for now: a delta and a last-session value beside *every* field of *every* set read as
/// clutter rather than information, and the two labels sharing one slot — swapping as you type —
/// make the row hard to read. Everything behind them is deliberately left standing (the
/// reference set the cells resolve, the delta helpers, both labels below), so a later set-cell
/// design can bring the comparison back by flipping this one flag.
private let showsSetValueIndicators = false

extension View {
    /// Places one indicator immediately to the left of (and baseline-aligned with) the number
    /// it is attached to: the previous workout's value while the field is still empty, or
    /// the trend delta once a value is entered. Fades between states.
    ///
    /// Currently a no-op — see `showsSetValueIndicators`.
    ///
    /// The indicator participates in layout (it used to be an overlay overflowing into the
    /// field frame's empty leading space, which let a long previous value draw over the
    /// neighboring field's number — the reported overlap bug). Its slot is reserved whenever
    /// a reference exists, whichever of the two labels is showing, so the row's layout stays
    /// put while typing swaps the previous value for the trend delta.
    func setValueIndicator(
        trend: SetValueComparison?,
        trendText: String,
        positiveColor: Color,
        previousValueText: String?,
        showPreviousValue: Bool,
        onTapPreviousValue: (() -> Void)?,
        isVisible: Bool
    ) -> some View {
        let showTrend = showsSetValueIndicators && isVisible && trend != nil
        let showPrevious = showsSetValueIndicators && !showTrend && showPreviousValue
            && previousValueText != nil
        let reservesSlot = showsSetValueIndicators && isVisible
            && (trend != nil || previousValueText != nil)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            if reservesSlot {
                ZStack(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                    SetValueDeltaLabel(
                        comparison: trend ?? .improved,
                        text: trendText,
                        positiveColor: positiveColor
                    )
                    .opacity(showTrend ? 1 : 0)
                    PreviousSetValueLabel(text: previousValueText ?? "", onTap: onTapPreviousValue)
                        .opacity(showPrevious ? 1 : 0)
                        .allowsHitTesting(showPrevious)
                }
                .animation(.easeInOut(duration: 0.2), value: showTrend)
                .animation(.easeInOut(duration: 0.2), value: showPrevious)
            }
            self
        }
    }
}

struct IntegerField_Previews: PreviewProvider {
    static var previews: some View {
        IntegerField(
            placeholder: 0,
            value: .constant(12),
            maxDigits: 4,
            index: .init(setID: UUID()),
            focusedIntegerFieldIndex: .constant(nil)
        )
        .padding(CELL_PADDING)
        .secondaryTileStyle()
        .previewEnvironmentObjects()
    }
}
