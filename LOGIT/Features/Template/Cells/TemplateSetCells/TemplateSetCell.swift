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
    let onEditRestDuration: (() -> Void)?

    // MARK: - Body

    var body: some View {
        Group {
            if canEdit {
                content
                    .contextMenu {
                        contextMenuContent
                    }
            } else {
                content
            }
        }
        .padding(.leading, CELL_PADDING)
        .padding([.top, .trailing], 8)
        .padding(.bottom, templateSet as? TemplateDropSet != nil ? CELL_PADDING : 8)
    }

    // MARK: - Supporting Views

    private var content: some View {
        VStack(spacing: 0) {
            if let indexInSetGroup = indexInSetGroup {
                HStack {
                    Text("\(NSLocalizedString("set", comment: "")) \(indexInSetGroup + 1)")
                    Spacer()
                    setContent
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
                        .disabled(dropSet.entryValues.count < 2)
                        Text(String(dropSet.entryValues.count))
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
    }

    @ViewBuilder
    private var setContent: some View {
        if let indexInTemplate {
            VStack(spacing: 0) {
                ForEach(
                    Array(templateSet.entries.enumerated()), id: \.element.objectID
                ) { entryIndex, entry in
                    let entryExercise = templateSet.owningExercise(of: entry)
                    SetEntryFieldsRow(
                        entry: entry,
                        primaryIndex: indexInTemplate,
                        secondaryIndex: entryIndex,
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                    )
                    .accentColor(entryExercise?.muscleGroup?.color)
                }
            }
            .padding(.top, templateSetIsFirst(templateSet: templateSet) ? 0 : CELL_SPACING / 2)
            .padding(.bottom, templateSetIsLast(templateSet: templateSet) ? 0 : CELL_SPACING / 2)
        }
    }

    private var indexInTemplate: Int? {
        templateSet.setGroup?.workout?.sets.firstIndex(of: templateSet)
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Section {
            if let onEditRestDuration {
                Button {
                    onEditRestDuration()
                } label: {
                    Label(
                        NSLocalizedString(
                            templateSet.restDurationSeconds > 0 ? "editRest" : "addRest",
                            comment: ""
                        ),
                        systemImage: "clock"
                    )
                }
            }
        }

        // Per-set measurement override on top of the exercise/group default. Hidden for
        // super sets: their two exercises each bring their own measurement type.
        if !(templateSet is TemplateSuperSet) {
            Section {
                Menu {
                    ForEach(SetMeasurementType.allCases) { type in
                        Button {
                            templateSet.overrideMeasurementType(type)
                        } label: {
                            HStack {
                                Text(type.title)
                                if templateSet.measurementType == type {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    // Distance scale — an exercise-wide display choice (values stay meters),
                    // offered here too so a re-typed set can fix its unit in the same menu.
                    if templateSet.measurementType.usesDistance, let exercise = templateSet.exercise {
                        Section {
                            ForEach(SetMeasurementType.DistanceStyle.allCases, id: \.self) { style in
                                Button {
                                    exercise.distanceStyle = style
                                } label: {
                                    HStack {
                                        Text(distanceStyleTitle(for: style))
                                        if templateSet.measurementType.distanceStyle(for: exercise) == style {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(NSLocalizedString("distanceUnit", comment: ""))
                        }
                    }
                } label: {
                    Label(
                        NSLocalizedString("measurementType", comment: ""),
                        systemImage: "slider.horizontal.3"
                    )
                }
            }
        }

        Section {
            Button {
                withAnimation(.interactiveSpring()) {
                    database.addSet(before: templateSet)
                }
            } label: {
                Label(
                    NSLocalizedString("addSetBefore", comment: ""),
                    systemImage: "arrow.up.to.line.circle"
                )
            }

            Button {
                withAnimation(.interactiveSpring()) {
                    database.addSet(after: templateSet)
                }
            } label: {
                Label(
                    NSLocalizedString("addSetAfter", comment: ""),
                    systemImage: "arrow.down.to.line.circle"
                )
            }
        }

        Section {
            Button {
                withAnimation(.interactiveSpring()) {
                    database.duplicateSet(templateSet)
                }
            } label: {
                Label(NSLocalizedString("copySet", comment: ""), systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                withAnimation(.interactiveSpring()) {
                    database.delete(templateSet)
                }
            } label: {
                Label(NSLocalizedString("remove", comment: ""), systemImage: "xmark.circle")
            }
        }
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
