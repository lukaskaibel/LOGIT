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
        .setValueIndicatorOverlay(
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

    struct Index: Equatable, Hashable {
        let primary: Int
        var secondary: Int = 0
        var tertiary: Int = 0

        static func == (lhs: Index, rhs: Index) -> Bool {
            lhs.primary == rhs.primary && lhs.secondary == rhs.secondary
                && lhs.tertiary == rhs.tertiary
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(primary)
            hasher.combine(secondary)
            hasher.combine(tertiary)
        }
    }
}

// MARK: - Set Value Trend Indicator

enum SetValueComparison: Equatable {
    case improved
    case declined
}

/// A small up/down triangle plus the absolute difference versus the previous workout's
/// value for a single set field. Positive (improved) uses the exercise's muscle-group
/// color; negative (declined) is muted gray.
struct SetValueDeltaLabel: View {
    let comparison: SetValueComparison
    let text: String
    var positiveColor: Color = .accentColor

    var body: some View {
        HStack(spacing: 1) {
            Image(
                systemName: comparison == .improved
                    ? "chevron.up"
                    : "chevron.down"
            )
            .font(.system(size: 7, weight: .bold))
            Text(text)
        }
        .font(.system(.caption2, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(comparison == .improved ? positiveColor : Color.secondary)
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
    /// Places one indicator immediately to the left of (and bottom-aligned with) the number
    /// it is attached to: the previous workout's value while the field is still empty, or
    /// the trend delta once a value is entered. Anchoring to the host's leading edge keeps
    /// the gap to the number constant regardless of the value's width; the label overflows
    /// into the empty leading space without affecting layout. Fades between states.
    func setValueIndicatorOverlay(
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
        // Aligned to the number's text baseline, sitting a few points to its left. The host
        // is the styled field tile, whose 8pt horizontal padding is offset in the leading
        // guide so the gap to the number stays constant regardless of the value's width.
        return overlay(alignment: Alignment(horizontal: .leading, vertical: .lastTextBaseline)) {
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
            .alignmentGuide(.leading) { $0.width - 2 }
            .animation(.easeInOut(duration: 0.2), value: showTrend)
            .animation(.easeInOut(duration: 0.2), value: showPrevious)
        }
    }
}

struct IntegerField_Previews: PreviewProvider {
    static var previews: some View {
        IntegerField(
            placeholder: 0,
            value: .constant(12),
            maxDigits: 4,
            index: .init(primary: 0),
            focusedIntegerFieldIndex: .constant(.init(primary: 0))
        )
        .padding(CELL_PADDING)
        .secondaryTileStyle()
        .previewEnvironmentObjects()
    }
}
