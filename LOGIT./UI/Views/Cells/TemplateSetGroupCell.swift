//
//  TemplateSetGroupCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct TemplateSetGroupCell: View {

    // MARK: - Environment

    @Environment(\.canEdit) var canEdit: Bool
    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var setGroup: TemplateSetGroup

    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    @Binding var sheetType: TemplateEditorScreen.SheetType?
    @Binding var isReordering: Bool

    let supplementaryText: String?

    // MARK: - State

    @State var isReorderingSets = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            header
            if !isReordering {
                VStack(spacing: CELL_PADDING) {
                    VStack(spacing: CELL_SPACING) {
                        ReorderableForEach(
                            $setGroup.sets,
                            canReorder: canEdit,
                            isReordering: $isReorderingSets,
                            onOrderChanged: { database.refreshObjects() }
                        ) { templateSet in
                            TemplateSetCell(
                                templateSet: templateSet,
                                focusedIntegerFieldIndex: $focusedIntegerFieldIndex
                            )
                            .padding(CELL_PADDING)
                            .contentShape(Rectangle())
                            .onDelete(disabled: !canEdit) {
                                withAnimation(.interactiveSpring()) {
                                    database.delete(templateSet)
                                    database.refreshObjects()
                                }
                            }
                            .secondaryTileStyle()
                        }
                    }
                    .animation(.interactiveSpring())
                    if canEdit && !isReordering {
                        Button {
                            withAnimation(.interactiveSpring()) {
                                database.addSet(to: setGroup)
                            }
                        } label: {
                            Label(
                                NSLocalizedString("addSet", comment: ""),
                                systemImage: "plus.circle.fill"
                            )
                        }
                        .buttonStyle(SecondaryBigButtonStyle())
                    }
                }
            }
        }
        .accentColor(setGroup.exercise?.muscleGroup?.color ?? .accentColor)
    }

    // MARK: - Supporting Views

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if let supplementaryText = supplementaryText {
                    Text(supplementaryText)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondaryLabel)
                }
                ExerciseHeader(
                    exercise: setGroup.exercise,
                    secondaryExercise: setGroup.secondaryExercise,
                    noExerciseAction: {
                        sheetType = .exerciseSelection(
                            exercise: setGroup.exercise,
                            setExercise: {
                                setGroup.exercise = $0
                                database.refreshObjects()
                            },
                            forSecondary: false
                        )
                    },
                    noSecondaryExerciseAction: {
                        sheetType = .exerciseSelection(
                            exercise: setGroup.secondaryExercise,
                            setExercise: {
                                setGroup.secondaryExercise = $0
                                database.refreshObjects()
                            },
                            forSecondary: true
                        )
                    },
                    isSuperSet: setGroup.setType == .superSet,
                    navigationToDetailEnabled: true
                )
            }
            Spacer()
            if canEdit {
                menu
            }
        }
        .font(.title3.weight(.bold))
        .foregroundColor(.label)
    }

    // MARK: - Supporting Views

    private var menu: some View {
        Menu {
            Section {
                Button(
                    role: .destructive,
                    action: {
                        withAnimation {
                            database.delete(setGroup)
                        }
                    }
                ) {
                    Label(NSLocalizedString("remove", comment: ""), systemImage: "xmark.circle")
                }
                if let exercise = setGroup.exercise {
                    Button {
                        sheetType = .exerciseSelection(
                            exercise: exercise,
                            setExercise: { setGroup.exercise = $0 },
                            forSecondary: false
                        )
                    } label: {
                        Label(
                            NSLocalizedString("replaceExercise", comment: ""),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                if setGroup.setType == .superSet, let secondaryExercise = setGroup.secondaryExercise
                {
                    Button {
                        sheetType = .exerciseSelection(
                            exercise: secondaryExercise,
                            setExercise: { setGroup.secondaryExercise = $0 },
                            forSecondary: true
                        )
                    } label: {
                        Label(
                            NSLocalizedString("replaceSecondaryExercise", comment: ""),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                Button {
                    isReordering.toggle()
                } label: {
                    Label(
                        NSLocalizedString(
                            isReordering ? "reorderingDone" : "reorderExercises",
                            comment: ""
                        ),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
            }
            Section {
                Button {
                    database.convertSetGroupToStandardSets(setGroup)
                } label: {
                    Label(
                        NSLocalizedString("standard", comment: ""),
                        systemImage: setGroup.setType == .standard ? "checkmark" : ""
                    )
                }
                Button {
                    database.convertSetGroupToSuperSet(setGroup)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        sheetType = .exerciseSelection(
                            exercise: setGroup.secondaryExercise,
                            setExercise: { setGroup.secondaryExercise = $0 },
                            forSecondary: true
                        )
                    }
                } label: {
                    Label(
                        NSLocalizedString("superSet", comment: ""),
                        systemImage: setGroup.setType == .superSet ? "checkmark" : ""
                    )
                }
                Button {
                    database.convertSetGroupToDropSets(setGroup)
                } label: {
                    Label(
                        NSLocalizedString("dropSet", comment: ""),
                        systemImage: setGroup.setType == .dropSet ? "checkmark" : ""
                    )
                }
            } header: {
                Text(NSLocalizedString("setType", comment: ""))
            }
        } label: {
            Image(systemName: "ellipsis")
                .padding(.vertical)
        }
    }

}

struct TemplateSetGroupCell_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    TemplateSetGroupCell(
                        setGroup: Database.preview.getTemplates().first!.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(false),
                        supplementaryText: "1 / 3"
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    TemplateSetGroupCell(
                        setGroup: Database.preview.getTemplates().first!.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(true),
                        supplementaryText: "1 / 3"
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    TemplateSetGroupCell(
                        setGroup: Database.preview.getTemplates().first!.setGroups.first!,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(false),
                        supplementaryText: "1 / 3"
                    )
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding()
                    .canEdit(false)
                }

            }
        }
        .environmentObject(Database.preview)
    }
}
