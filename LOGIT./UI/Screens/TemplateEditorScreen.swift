//
//  TemplateEditorScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import SwiftUI

struct TemplateEditorScreen: View {

    enum SheetType: Identifiable {
        case exerciseDetail(exercise: Exercise)
        var id: Int {
            switch self {
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
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .fraction(0.09)


    // MARK: - Parameters

    let isEditingExistingTemplate: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollable in
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
                                isReordering: $isReordering
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
                    }
                    .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                    .padding(.horizontal)
                    .id(1)
                }
                .scrollIndicators(.hidden)
                .sheet(isPresented: .constant(true)) {
                    NavigationView {
                        ExerciseSelectionScreen(
                            selectedExercise: nil,
                            setExercise: { exercise in
                                database.newTemplateSetGroup(
                                    createFirstSetAutomatically: true,
                                    exercise: exercise,
                                    template: template
                                )
                                withAnimation {
                                    scrollable.scrollTo(1, anchor: .bottom)
                                }
                            },
                            forSecondary: false,
                            presentationDetentSelection: $exerciseSelectionPresentationDetent
                        )
                    }
                    .presentationDetents([.fraction(0.09), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .interactiveDismissDisabled()
                }
            }
            .interactiveDismissDisabled()
            .navigationTitle(
                isEditingExistingTemplate
                    ? NSLocalizedString("editTemplate", comment: "")
                    : NSLocalizedString("newTemplate", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !isEditingExistingTemplate {
                    database.flagAsTemporary(template)
                }
            }
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
                        database.discardUnsavedChanges()
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
//            .sheet(item: $sheetType) { style in
//                NavigationStack {
//                    switch style {
//                    case let .exerciseSelection(exercise, setExercise, forSecondary):
//                        ExerciseSelectionScreen(
//                            selectedExercise: exercise,
//                            setExercise: setExercise,
//                            forSecondary: forSecondary
//                        )
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarLeading) {
//                                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
//                                    sheetType = nil
//                                }
//                            }
//                        }
//                    case let .exerciseDetail(exercise):
//                        ExerciseDetailScreen(exercise: exercise)
//                            .toolbar {
//                                ToolbarItem(placement: .navigationBarLeading) {
//                                    Button(NSLocalizedString("dismiss", comment: ""), role: .cancel)
//                                    {
//                                        sheetType = nil
//                                    }
//                                }
//                            }
//                    }
//                }
//            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Computed Properties

    private var templateName: Binding<String> {
        Binding(get: { template.name ?? "" }, set: { template.name = $0 })
    }

    public func moveSetGroups(from source: IndexSet, to destination: Int) {
        template.setGroups.move(fromOffsets: source, toOffset: destination)
    }

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            TemplateEditorScreen(
                template: database.testTemplate,
                isEditingExistingTemplate: true
            )
        }
    }
}

struct TemplateEditorView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
