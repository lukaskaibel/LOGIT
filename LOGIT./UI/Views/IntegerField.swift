//
//  CustomTextField.swift
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
        .onTapGesture {
            isFocused = true
        }
        .onAppear {
            valueString = String(value)
        }
        .onChange(of: focusedIntegerFieldIndex) { newValue in
            guard isFocused != (newValue == index) else { return }
            // Solution, because otherwise moving down wasnt working, since it would first focus on the new field, while the old one was still focused, which caused the focus to get lost.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            guard newValue == index else { return }
            isFocused = true
        }
        .onChange(of: isFocused) { newValue in
            if newValue {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            guard newValue != (focusedIntegerFieldIndex == index) else { return }
            focusedIntegerFieldIndex = index
        }
        .onChange(of: value) { newValue in
            if String(newValue) != valueString {
                valueString = String(newValue)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .secondaryTileStyle(backgroundColor: isFocused ? Color.white : Color.black.opacity(0.000001))
        .frame(minWidth: 100, alignment: .trailing)
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
