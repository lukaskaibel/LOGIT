//
//  TemplateEditorScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import SwiftUI

struct TemplateEditorScreen: View {

    enum SheetType: Identifiable {
        case exerciseSelection(
            exercise: Exercise?,
            setExercise: (Exercise) -> Void,
            forSecondary: Bool
        )
        case exerciseDetail(exercise: Exercise)
        var id: Int {
            switch self {
            case .exerciseSelection: return 0
            case .exerciseDetail: return 1
            }
        }
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var database: Database

    // MARK: - State

    @StateObject var template: Template

    @State private var isReordering: Bool = false
    @State private var sheetType: SheetType? = nil

    // MARK: - Parameters

    let isEditingExistingTemplate: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    TextField(
                        NSLocalizedString("title", comment: ""),
                        text: templateName,
                        axis: .vertical
                    )
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                    .padding(.vertical)

                    VStack(spacing: SECTION_SPACING) {
                        ReorderableForEach(
                            $template.setGroups,
                            isReordering: $isReordering,
                            onOrderChanged: { database.refreshObjects() }
                        ) { setGroup in
                            TemplateSetGroupCell(
                                setGroup: setGroup,
                                focusedIntegerFieldIndex: .constant(nil),
                                sheetType: $sheetType,
                                isReordering: $isReordering,
                                supplementaryText:
                                    "\(template.setGroups.firstIndex(of: setGroup)! + 1) / \(template.setGroups.count)  ·  \(setGroup.setType.description)"
                            )
                            .padding(CELL_PADDING)
                            .tileStyle()
                        }
                    }
                    .animation(.interactiveSpring())

                    addExerciseButton
                        .padding(.vertical, 30)
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .interactiveDismissDisabled()
            .navigationTitle(
                isEditingExistingTemplate
                    ? NSLocalizedString("editTemplate", comment: "")
                    : NSLocalizedString("newTemplate", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        template.exercises.forEach { database.unflagAsTemporary($0) }
                        database.unflagAsTemporary(template)
                        database.save()
                        dismiss()
                    }
                    .font(.body.weight(.bold))
                    .disabled(template.name?.isEmpty ?? true)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        database.deleteAllTemporaryObjects()
                        database.save()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Text(
                        "\(template.setGroups.count) \(NSLocalizedString("exercise\(template.setGroups.count == 1 ? "" : "s")", comment: ""))"
                    )
                    .font(.caption)
                }
            }
            .sheet(item: $sheetType) { style in
                NavigationStack {
                    switch style {
                    case let .exerciseSelection(exercise, setExercise, forSecondary):
                        ExerciseSelectionScreen(
                            selectedExercise: exercise,
                            setExercise: setExercise,
                            forSecondary: forSecondary
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                                    sheetType = nil
                                }
                            }
                        }
                    case let .exerciseDetail(exercise):
                        ExerciseDetailScreen(exercise: exercise)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(NSLocalizedString("dismiss", comment: ""), role: .cancel)
                                    {
                                        sheetType = nil
                                    }
                                }
                            }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Supporting Views

    private var addExerciseButton: some View {
        Button {
            sheetType = .exerciseSelection(
                exercise: nil,
                setExercise: { exercise in
                    database.newTemplateSetGroup(
                        createFirstSetAutomatically: true,
                        exercise: exercise,
                        template: template
                    )
                    database.refreshObjects()
                },
                forSecondary: false
            )
        } label: {
            Label(NSLocalizedString("addExercise", comment: ""), systemImage: "plus.circle.fill")
        }
        .buttonStyle(BigButtonStyle())
    }

    // MARK: - Computed Properties

    private var templateName: Binding<String> {
        Binding(get: { template.name ?? "" }, set: { template.name = $0 })
    }

    public func moveSetGroups(from source: IndexSet, to destination: Int) {
        template.setGroups.move(fromOffsets: source, toOffset: destination)
        database.refreshObjects()
    }

}

struct TemplateEditorView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            TemplateEditorScreen(
                template: Database.preview.testTemplate,
                isEditingExistingTemplate: true
            )
        }
        .environmentObject(Database.preview)
    }
}
