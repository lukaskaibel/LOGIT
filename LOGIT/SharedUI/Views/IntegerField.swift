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
                    .onChange(of: valueString) {
                        valueString = ($0 == "0" || $0.isEmpty) ? "" : String($0.prefix(4))
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
        .onChange(of: focusedIntegerFieldIndex) { newValue in
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
        .onChange(of: isFocused) { newValue in
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
        .onChange(of: value) { newValue in
            if String(newValue) != valueString {
                valueString = String(newValue)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .secondaryTileStyle(backgroundColor: isFocused ? Color.white : Color.black.opacity(0.000001))
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
