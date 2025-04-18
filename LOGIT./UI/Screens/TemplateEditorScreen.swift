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
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isRenamingTemplate = false
    @FocusState private var isFocusingRenameTemplateField: Bool


    // MARK: - Parameters

    let isEditingExistingTemplate: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            if isRenamingTemplate {
                HStack {
                    TextField(
                        NSLocalizedString("newTemplate", comment: ""),
                        text: templateName
                    )
                    .focused($isFocusingRenameTemplateField)
                    .onChange(of: isFocusingRenameTemplateField) {
                        if !isFocusingRenameTemplateField {
                            withAnimation {
                                isRenamingTemplate = false
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .fontWeight(.bold)
                    .onSubmit {
                        isFocusingRenameTemplateField = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isRenamingTemplate = false
                        }
                    }
                    .submitLabel(.done)
                    if !(template.name?.isEmpty ?? true) {
                        Button {
                            template.name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondaryLabel)
                                .font(.body)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .padding(10)
            }
            ScrollViewReader { scrollable in
                ScrollView {
                    VStack {
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
                        .padding(.top)
                        .toolbar {
                            if exerciseSelectionPresentationDetent == .fraction(BOTTOM_SHEET_SMALL) {
                                ToolbarItemGroup(placement: .bottomBar) {
                                    Spacer()
                                    Button {
                                        database.undo()
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .disabled(!database.canUndo)
                                    Spacer()
                                    Button {
                                        database.redo()
                                    } label: {
                                        Image(systemName: "arrow.uturn.forward")
                                    }
                                    .disabled(!database.canRedo)
                                    Spacer()
                                }
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
                    .presentationDetents([.fraction(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .presentationCornerRadius(30)
                    .interactiveDismissDisabled()
                }
            }
            .interactiveDismissDisabled()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isRenamingTemplate)
            .onAppear {
                if !isEditingExistingTemplate {
                    database.flagAsTemporary(template)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isFocusingRenameTemplateField = true
                            }
                            isRenamingTemplate = true
                            exerciseSelectionPresentationDetent = .fraction(BOTTOM_SHEET_SMALL)
                            
                        } label: {
                            Label(NSLocalizedString("rename", comment: ""), systemImage: "pencil")
                        }
                    } label: {
                        HStack {
                            Text(templateName.wrappedValue.isEmpty ? NSLocalizedString("newTemplate", comment: "") : templateName.wrappedValue)
                                .foregroundStyle(templateName.wrappedValue.isEmpty ? Color.placeholder : Color.label)
                                .fontWeight(.bold)
                                .lineLimit(1)
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                        }
                    }
                }
                if !isRenamingTemplate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(NSLocalizedString("save", comment: "")) {
                            template.name = template.name?.isEmpty ?? true ? NSLocalizedString("newTemplate", comment: "") : template.name
                            template.exercises.forEach { database.unflagAsTemporary($0) }
                            database.unflagAsTemporary(template)
                            database.save()
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button(NSLocalizedString("cancel", comment: "")) {
                            database.discardUnsavedChanges()
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                            }
                        }
                    }
                }
            }
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
