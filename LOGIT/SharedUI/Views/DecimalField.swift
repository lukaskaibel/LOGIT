//
//  DecimalField.swift
//  LOGIT.
//
//  Created for decimal weight input support
//

import Combine
import SwiftUI

struct DecimalField: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @Environment(\.setFieldFocusRelay) private var focusRelay
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled

    // MARK: - Parameters

    let placeholder: Double
    /// Untracked — see `IntegerField.value`.
    @UntrackedBinding var value: Double
    let maxDigits: Int?
    let decimalPlaces: Int
    /// Whether a leading "-" survives `filterInput`. Only a weight can be negative — assistance is
    /// stored as a negative load — so only weight fields opt in. Everywhere else a minus is
    /// dropped: the number pad has no minus key, but a paste or a hardware keyboard can still
    /// type one, and a negative duration used to land as a permanent "fastest" record at 0:00.
    var allowsNegative: Bool = false
    let index: IntegerField.Index
    @UntrackedBinding var focusedIntegerFieldIndex: IntegerField.Index?
    var unit: String? = "kg"
    var trend: SetValueComparison? = nil
    var trendText: String = ""
    var trendColor: Color = .accentColor
    var previousValueText: String? = nil
    var onTapPreviousValue: (() -> Void)? = nil

    // MARK: - State

    @State private var valueString: String = ""
    @FocusState private var isFocused: Bool
    /// Whether a real text field is in place — see `SetFieldRestingText`.
    @State private var isEditing = false

    // MARK: - Body

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                if canEdit && (isEditing || isVoiceOverEnabled) {
                    TextField(
                        formatNumber(placeholder),
                        text: $valueString,
                        prompt: Text(formatNumber(placeholder)).foregroundStyle(isFocused ? Color(UIColor.systemGray2) : Color.placeholder)
                    )
                    .focused($isFocused)
                    .onChange(of: valueString) { _, newString in
                        let filtered = filterInput(newString)
                        valueString = (filtered == "0" || filtered.isEmpty) ? "" : filtered
                        if let valueDouble = Double(filtered), valueDouble != value {
                            value = valueDouble
                        } else if filtered.isEmpty && value != 0 {
                            value = 0
                        }
                    }
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .keyboardType(.decimalPad)
                    .onAppear { if isEditing { isFocused = true } }
                    .transition(.identity)
                } else if canEdit {
                    SetFieldRestingText(text: valueString, prompt: formatNumber(placeholder))
                } else {
                    Text(valueString)
                        .foregroundColor(isEmpty ? .placeholder : .primary)
                }
            }
            .font(.system(.title3, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            Text(unit?.uppercased() ?? "")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundColor(isFocused ? (isEmpty ? Color(UIColor.systemGray) : Color(UIColor.systemGray3)) : isEmpty ? .placeholder : .secondary)
                .fixedSize()
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
                // Losing focus – sync valueString with the canonical stored value
                // so the display shows the clean round-tripped number.
                let formatted = text(for: value)
                if formatted != valueString {
                    valueString = formatted
                }
                // Text again once the unfocus spring has settled — see `SetFieldRestingText.swapDelay`.
                DispatchQueue.main.asyncAfter(deadline: .now() + SetFieldRestingText.swapDelay) {
                    if !isFocused { isEditing = false }
                }
            }
        }
        .onChange(of: value) { _, newValue in
            // Only sync from the model when the field is NOT focused.
            // While the user is typing, valueString is the source of truth;
            // overwriting it causes rounding artefacts from the
            // display → grams → display round-trip (especially for lbs).
            //
            // The sign is the exception. Assistance is a negative weight, and the ± in the
            // keyboard row flips the stored value *under a focused field* — so that one
            // character is carried across on its own, leaving the digits being typed alone.
            guard !isFocused else {
                syncSignWhileTyping(of: newValue)
                return
            }
            let formatted = text(for: newValue)
            if formatted != valueString {
                valueString = formatted
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
        .fixedSize(horizontal: true, vertical: false)
        .onTapGesture {
            beginEditing()
        }
        .id(index)
        .keyboardScrollTarget(index)
    }

    /// The text for `value`. An editable field leaves zero empty, so its prompt shows — what the
    /// text field's own input filter does to a "0", done here because at rest there is no text
    /// field to do it.
    private func text(for value: Double) -> String {
        canEdit && value == 0 ? "" : formatNumber(value)
    }

    /// Puts the real text field in place and gives it the keyboard — see `IntegerField.beginEditing`.
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
        Double(valueString) == 0 || valueString.isEmpty
    }

    // MARK: - Helper Methods

    /// Puts the model's sign on the string being typed, without reformatting the digits. A field
    /// that doesn't allow negatives has no sign to carry.
    private func syncSignWhileTyping(of newValue: Double) {
        guard allowsNegative else { return }
        let isNegative = newValue < 0
        guard !valueString.isEmpty, isNegative != valueString.hasPrefix("-") else { return }
        valueString = isNegative ? "-" + valueString : String(valueString.dropFirst())
    }

    private func filterInput(_ input: String) -> String {
        // On a weight field (`allowsNegative`) a sign comes from the ± in the keyboard row, which
        // flips the stored weight. Set it aside, filter the magnitude exactly as before, and put it
        // back — a field showing assistance has to read as the negative number it stores. On any
        // other field the sign is simply dropped with the rest of the non-digits below, so a
        // pasted "-30" enters as 30.
        let isNegative = allowsNegative && input.hasPrefix("-")
        var filtered = isNegative ? String(input.dropFirst()) : input
        
        // Only allow digits and one decimal separator
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.,")
        filtered = String(filtered.unicodeScalars.filter { allowedCharacters.contains($0) })
        
        // Replace comma with period for decimal separator
        filtered = filtered.replacingOccurrences(of: ",", with: ".")
        
        // Only allow one decimal separator
        if filtered.filter({ $0 == "." }).count > 1 {
            if let firstDotIndex = filtered.firstIndex(of: ".") {
                let afterFirst = filtered.index(after: firstDotIndex)
                let beforeDot = filtered[...firstDotIndex]
                let afterDot = filtered[afterFirst...].replacingOccurrences(of: ".", with: "")
                filtered = String(beforeDot) + afterDot
            }
        }
        
        // Limit the integer part (before the decimal point) - do this BEFORE checking value.
        // `maxDigits` counts those integer digits: four for a weight, five for a distance in
        // meters, where a 10 km run is a five-digit entry.
        let integerDigitLimit = maxDigits ?? 4
        if let dotIndex = filtered.firstIndex(of: ".") {
            let integerPart = filtered[..<dotIndex]
            if integerPart.count > integerDigitLimit {
                let decimalPart = filtered[dotIndex...]
                filtered = String(integerPart.prefix(integerDigitLimit)) + decimalPart
            }
        } else {
            if filtered.count > integerDigitLimit {
                filtered = String(filtered.prefix(integerDigitLimit))
            }
        }
        
        // Limit decimal places to `decimalPlaces`
        if let dotIndex = filtered.firstIndex(of: ".") {
            let afterDot = filtered.index(after: dotIndex)
            let decimalPart = filtered[afterDot...]
            if decimalPart.count > decimalPlaces {
                filtered = String(filtered.prefix(through: filtered.index(dotIndex, offsetBy: decimalPlaces)))
            }
        }
        
        // Check if the value exceeds what those digits can spell (9999.999, 99999.99, …) after
        // all formatting
        let ceiling = pow(10.0, Double(integerDigitLimit)) - pow(10.0, -Double(decimalPlaces))
        if let value = Double(filtered), value > ceiling {
            // Keep the previous valid value
            return valueString
        }
        
        // Remove leading zeros before number (but keep "0" and "0.")
        if filtered.hasPrefix("0") && filtered.count > 1 && !filtered.hasPrefix("0.") {
            filtered = String(filtered.drop(while: { $0 == "0" }))
            if filtered.isEmpty || filtered.hasPrefix(".") {
                filtered = "0" + filtered
            }
        }
        
        // Nothing to be negative about: an empty field and a zero are unsigned.
        guard isNegative, !filtered.isEmpty, Double(filtered) != 0 else { return filtered }
        return "-" + filtered
    }

    /// Formatters are expensive to create and this runs twice per body evaluation (placeholder
    /// and prompt) across every weight field on screen, so they are cached per decimal-place
    /// count instead of rebuilt per call.
    private static var formatters: [Int: NumberFormatter] = [:]

    private func formatNumber(_ number: Double) -> String {
        // Format the number to remove unnecessary trailing zeros
        let formatter: NumberFormatter
        if let cached = Self.formatters[decimalPlaces] {
            formatter = cached
        } else {
            let created = NumberFormatter()
            created.numberStyle = .decimal
            created.minimumFractionDigits = 0
            created.maximumFractionDigits = decimalPlaces
            created.decimalSeparator = "."
            created.groupingSeparator = ""
            Self.formatters[decimalPlaces] = created
            formatter = created
        }

        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }
}

struct DecimalField_Previews: PreviewProvider {
    static var previews: some View {
        DecimalField(
            placeholder: 0,
            value: .constant(12.5),
            maxDigits: 4,
            decimalPlaces: 2,
            index: .init(setID: UUID()),
            focusedIntegerFieldIndex: .constant(nil)
        )
        .padding(CELL_PADDING)
        .secondaryTileStyle()
        .previewEnvironmentObjects()
    }
}
