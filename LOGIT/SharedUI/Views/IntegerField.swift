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
    @EnvironmentObject var database: Database
    @Environment(\.isIntegerFieldFocusSuppressed) private var isFocusSuppressed: Bool

    // MARK: - Parameters

    let placeholder: Int64
    @Binding var value: Int64
    let maxDigits: Int?
    let index: Index
    @Binding var focusedIntegerFieldIndex: Index?
    var unit: String? = "kg"
    var trend: SetValueComparison? = nil
    var trendText: String = ""
    var trendColor: Color = .accentColor
    var previousValueText: String? = nil
    var onTapPreviousValue: (() -> Void)? = nil

    // MARK: - State

    @State private var valueString: String = ""
    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                if canEdit {
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
            valueString = String(value)
        }
        .onChange(of: focusedIntegerFieldIndex) { _, newValue in
            guard !isFocusSuppressed else { return }
            let shouldBeFocused = newValue == index
            guard isFocused != shouldBeFocused else { return }
            if shouldBeFocused {
                // Set focus directly - don't resign first responder first
                // This allows UIKit to handle the responder chain transfer smoothly
                isFocused = true
            } else if newValue == nil && isFocused {
                // Explicitly dismiss keyboard when focusedIntegerFieldIndex is set to nil
                isFocused = false
            }
            // When transferring to another field (newValue != nil && newValue != index),
            // don't explicitly set isFocused = false; the new field's focus will take over
        }
        .onChange(of: isFocused) { _, newValue in
            guard !isFocusSuppressed else { return }
            if newValue {
                UISelectionFeedbackGenerator().selectionChanged()
                // Only update binding if we're gaining focus and not already set
                if focusedIntegerFieldIndex != index {
                    focusedIntegerFieldIndex = index
                }
            }
            // When losing focus, don't update the binding - another field is taking over
        }
        .onChange(of: value) { _, newValue in
            if String(newValue) != valueString {
                valueString = String(newValue)
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
            guard !isFocusSuppressed else { return }
            isFocused = true
        }
        .id(index)
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

extension View {
    /// Places one indicator immediately to the left of (and baseline-aligned with) the number
    /// it is attached to: the previous workout's value while the field is still empty, or
    /// the trend delta once a value is entered. Fades between states.
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
        let showTrend = isVisible && trend != nil
        let showPrevious = !showTrend && showPreviousValue && previousValueText != nil
        let reservesSlot = isVisible && (trend != nil || previousValueText != nil)
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
