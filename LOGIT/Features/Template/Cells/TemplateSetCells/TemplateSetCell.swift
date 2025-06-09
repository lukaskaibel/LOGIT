//
//  TemplateSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 23.05.22.
//

import SwiftUI

struct TemplateSetCell: View {
    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var templateSet: TemplateSet
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let indexInSetGroup = indexInSetGroup {
                HStack {
                    Text("\(NSLocalizedString("set", comment: "")) \(indexInSetGroup + 1)")
                    Spacer()
                    if let standardSet = templateSet as? TemplateStandardSet {
                        TemplateStandardSetCell(
                            standardSet: standardSet,
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                        )
                        .padding(
                            .top,
                            templateSetIsFirst(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                        .padding(
                            .bottom,
                            templateSetIsLast(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                    } else if let dropSet = templateSet as? TemplateDropSet {
                        TemplateDropSetCell(
                            dropSet: dropSet,
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                        )
                        .padding(
                            .top,
                            templateSetIsFirst(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                        .padding(
                            .bottom,
                            templateSetIsLast(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                    } else if let superSet = templateSet as? TemplateSuperSet {
                        TemplateSuperSetCell(
                            superSet: superSet,
                            focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                        )
                        .padding(
                            .top,
                            templateSetIsFirst(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                        .padding(
                            .bottom,
                            templateSetIsLast(templateSet: templateSet) ? 0 : CELL_SPACING / 2
                        )
                    }
                }
                if let dropSet = templateSet as? TemplateDropSet, canEdit {
                    Divider()
                        .padding(.top, 8)
                        .padding(.bottom, CELL_PADDING)
                    HStack {
                        Text(NSLocalizedString("dropCount", comment: ""))
                        Spacer()
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            dropSet.removeLastDrop()
                        } label: {
                            Image(systemName: "minus")
                                .fontWeight(.semibold)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                        }
                        .disabled((dropSet.repetitions?.count ?? 0) < 2)
                        Text(String(dropSet.repetitions?.count ?? 0))
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(.primary)
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            dropSet.addDrop()
                        } label: {
                            Image(systemName: "plus")
                                .fontWeight(.semibold)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                        }
                    }
                    .accentColor(dropSet.exercise?.muscleGroup?.color)
                }
            }
        }
        .padding(.leading, CELL_PADDING)
        .padding([.top, .trailing], 8)
        .padding(.bottom, templateSet as? TemplateDropSet != nil ? CELL_PADDING : 8)
    }

    // MARK: - Supporting Methods

    private var indexInSetGroup: Int? {
        templateSet.setGroup?.sets.firstIndex(of: templateSet)
    }

    private func templateSetIsFirst(templateSet: TemplateSet) -> Bool {
        guard let setGroup = templateSet.setGroup else { return false }
        return setGroup.sets.firstIndex(of: templateSet) == 0
    }

    private func templateSetIsLast(templateSet: TemplateSet) -> Bool {
        guard let setGroup = templateSet.setGroup else { return false }
        return setGroup.sets.firstIndex(of: templateSet) == setGroup.sets.count - 1
    }
}
