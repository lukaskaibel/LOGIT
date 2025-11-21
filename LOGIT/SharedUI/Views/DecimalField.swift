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
    @EnvironmentObject var database: Database
    @Environment(\.isIntegerFieldFocusSuppressed) private var isFocusSuppressed: Bool

    // MARK: - Parameters

    let placeholder: Double
    @Binding var value: Double
    let maxDigits: Int?
    let decimalPlaces: Int
    let index: IntegerField.Index
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    var unit: String? = "kg"

    // MARK: - State

    @State private var valueString: String = ""
    @FocusState private var isFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Group {
                if canEdit {
                    TextField(
                        formatNumber(placeholder),
                        text: $valueString,
                        prompt: Text(formatNumber(placeholder)).foregroundStyle(isFocused ? Color(UIColor.systemGray2) : Color.placeholder)
                    )
                    .focused($isFocused)
                    .onChange(of: valueString) {
                        let filtered = filterInput($0)
                        valueString = (filtered == "0" || filtered.isEmpty) ? "" : filtered
                        if let valueDouble = Double(filtered), valueDouble != value {
                            value = valueDouble
                        } else if filtered.isEmpty && value != 0 {
                            value = 0
                        }
                    }
                    .foregroundStyle(isFocused ? Color.black : Color.white)
                    .keyboardType(.decimalPad)
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
            valueString = formatNumber(value)
        }
        .onChange(of: focusedIntegerFieldIndex) { newValue in
            guard !isFocusSuppressed else { return }
            guard isFocused != (newValue == index) else { return }
            // Solution, because otherwise moving down wasnt working, since it would first focus on the new field, while the old one was still focused, which caused the focus to get lost.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            guard newValue == index else { return }
            isFocused = true
        }
        .onChange(of: isFocused) { newValue in
            guard !isFocusSuppressed else { return }
            if newValue {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            guard newValue != (focusedIntegerFieldIndex == index) else { return }
            focusedIntegerFieldIndex = index
        }
        .onChange(of: value) { newValue in
            let formatted = formatNumber(newValue)
            if formatted != valueString {
                valueString = formatted
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .secondaryTileStyle(backgroundColor: isFocused ? Color.white : Color.black.opacity(0.000001))
        .frame(minWidth: 100, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
        .onTapGesture {
            guard !isFocusSuppressed else { return }
            isFocused = true
        }
        .id(index)
    }

    // MARK: - Computed Properties

    private var isEmpty: Bool {
        Double(valueString) == 0 || valueString.isEmpty
    }

    // MARK: - Helper Methods

    private func filterInput(_ input: String) -> String {
        var filtered = input
        
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
        
        // Limit integer part to 4 digits (before decimal point) - do this BEFORE checking value
        if let dotIndex = filtered.firstIndex(of: ".") {
            let integerPart = filtered[..<dotIndex]
            if integerPart.count > 4 {
                let decimalPart = filtered[dotIndex...]
                filtered = String(integerPart.prefix(4)) + decimalPart
            }
        } else {
            // No decimal point, limit to 4 digits
            if filtered.count > 4 {
                filtered = String(filtered.prefix(4))
            }
        }
        
        // Limit decimal places to 3
        if let dotIndex = filtered.firstIndex(of: ".") {
            let afterDot = filtered.index(after: dotIndex)
            let decimalPart = filtered[afterDot...]
            if decimalPart.count > decimalPlaces {
                filtered = String(filtered.prefix(through: filtered.index(dotIndex, offsetBy: decimalPlaces)))
            }
        }
        
        // Check if value exceeds maximum (9999.999) after all formatting
        if let value = Double(filtered), value > 9999.999 {
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
        
        return filtered
    }

    private func formatNumber(_ number: Double) -> String {
        // Format the number to remove unnecessary trailing zeros
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimalPlaces
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ""
        
        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }
}

struct DecimalField_Previews: PreviewProvider {
    static var previews: some View {
        DecimalField(
            placeholder: 0,
            value: .constant(12.5),
            maxDigits: 4,
            decimalPlaces: 3,
            index: .init(primary: 0),
            focusedIntegerFieldIndex: .constant(.init(primary: 0))
        )
        .padding(CELL_PADDING)
        .secondaryTileStyle()
        .previewEnvironmentObjects()
    }
}
