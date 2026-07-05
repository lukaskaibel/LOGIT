//
//  TemplateEditorScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 02.04.22.
//

import SwiftUI

private enum TemplateInterSetGroupRestDisplayState: Equatable {
    case hidden
    case staticRest(Int)

    static func afterSetGroup(_ setGroup: TemplateSetGroup) -> Self {
        guard let lastSet = setGroup.sets.last else { return .hidden }
        guard lastSet.restDurationSeconds > 0 else { return .hidden }
        return .staticRest(lastSet.restDurationSeconds)
    }
}

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

    @State private var isShowingReorderSheet = false
    @State private var sheetType: SheetType? = nil
    @State private var selectedRestDurationSet: TemplateSet?
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isRenamingTemplate = false
    @State private var focusedIntegerFieldIndex: IntegerField.Index?
    @FocusState private var isFocusingRenameTemplateField: Bool

    // MARK: - Parameters

    let isEditingExistingTemplate: Bool
    var isImportedTemplate: Bool = false

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
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                .padding()
            }
            ScrollViewReader { scrollable in
                ScrollView {
                    VStack {
                        // Shared with you banner for imported templates
                        if isImportedTemplate {
                            SharedWithYouBanner(
                                title: NSLocalizedString("sharedTemplate", comment: ""),
                                subtitle: NSLocalizedString("sharedTemplateDescription", comment: "")
                            )
                            .padding(.bottom, SECTION_SPACING)
                        }
                        
                        VStack(spacing: 0) {
                            ForEach(template.setGroups) { setGroup in
                                VStack(spacing: 0) {
                                    TemplateSetGroupCell(
                                        setGroup: setGroup,
                                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                                        sheetType: $sheetType,
                                        isReordering: .constant(false),
                                        supplementaryText: nil,
                                        showDetailAsSheet: true,
                                        onTapRestDuration: { selectedRestDurationSet = $0 }
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 5)
                                    .zIndex(1)
                                    interSetGroupConnector(
                                        after: setGroup,
                                        showsTrailingLine: template.setGroups.last != setGroup
                                    )
                                    .zIndex(0)
                                }
                                .transition(.scale)
                                .id(setGroup)
                            }
                        }
                        .padding(.bottom, exerciseSelectionPresentationDetent == .medium ? (UIScreen.current?.bounds.height ?? 0) * 0.5 : BOTTOM_SHEET_SMALL)
                        .animation(.interactiveSpring(), value: template.setGroups.count)
                    }
                    .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                    .padding(.horizontal)
                    .id(1)
                }
                .scrollIndicators(.hidden)
                .sheet(isPresented: .constant(true)) {
                    NavigationView {
                        VStack(spacing: 0) {
                            ExerciseSelectionScreen(
                                selectedExercise: nil,
                                setExercise: { exercise in
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                                currentWorkoutExercises: [],
                                supersetPrimaryExercise: nil,
                                presentationDetentSelection: $exerciseSelectionPresentationDetent
                            )
                            .toolbar(.hidden, for: .navigationBar)
                            .sheet(item: $selectedRestDurationSet) { templateSet in
                                RestDurationEditorSheet(templateSet: templateSet)
                                    .presentationDetents([.fraction(0.65)])
                                    .padding()
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                            .sheet(isPresented: $isShowingReorderSheet) {
                                NavigationStack {
                                    List {
                                        ForEach(template.setGroups) { setGroup in
                                            HStack {
                                                VStack(alignment: .leading) {
                                                    Text(setGroup.exercise?.displayName ?? "")
                                                    if setGroup.setType == .superSet,
                                                       let secondaryExercise = setGroup.secondaryExercise {
                                                        HStack {
                                                            Image(systemName: "arrow.turn.down.right")
                                                            Text(secondaryExercise.displayName)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .onMove(perform: moveSetGroups)
                                    }
                                    .environment(\.editMode, .constant(.active))
                                    .navigationTitle(NSLocalizedString("reorderExercises", comment: ""))
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .topBarTrailing) {
                                            Button {
                                                isShowingReorderSheet = false
                                            } label: {
                                                Text(NSLocalizedString("done", comment: ""))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .presentationDetents([.height(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                    .presentationBackgroundInteraction(.enabled)
                    .interactiveDismissDisabled()
                }
            }
            .interactiveDismissDisabled()
            .background(Color.black.ignoresSafeArea())
            .presentationBackground(.black)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isRenamingTemplate)
            .onAppear {
                if !isEditingExistingTemplate {
                    database.flagAsTemporary(template)
                }
                exerciseSelectionPresentationDetent = template.setGroups.isEmpty ? .medium : .height(BOTTOM_SHEET_SMALL)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isFocusingRenameTemplateField = true
                            }
                            isRenamingTemplate = true
                            exerciseSelectionPresentationDetent = .height(BOTTOM_SHEET_SMALL)

                        } label: {
                            Label(NSLocalizedString("rename", comment: ""), systemImage: "pencil")
                        }
                    } label: {
                        HStack {
                            Text(templateName.wrappedValue.isEmpty ? NSLocalizedString("newTemplate", comment: "") : templateName.wrappedValue)
                                .foregroundStyle(templateName.wrappedValue.isEmpty ? Color.placeholder : Color.label)
                                .fontWeight(.bold)
                                .lineLimit(2)
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                        }
                        .frame(maxWidth: isImportedTemplate ? 140 : 200)
                    }
                }
                if !isRenamingTemplate {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isImportedTemplate ? NSLocalizedString("saveTemplate", comment: "") : NSLocalizedString("save", comment: "")) {
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
                            if focusedIntegerFieldIndex != nil, let templateSet = selectedTemplateSet {
                                Button {
                                    // Dismiss the keyboard first, then present the rest sheet on the next
                                    // runloop tick so the keyboard teardown and the sheet presentation
                                    // don't race. The sheet itself is presented from within the
                                    // exercise-selection sheet (see `selectedRestDurationSet`), so it
                                    // stacks on top of it instead of colliding.
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    focusedIntegerFieldIndex = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        selectedRestDurationSet = templateSet
                                    }
                                } label: {
                                    Image(systemName: "timer")
                                        .keyboardToolbarButtonStyle()
                                }
                            }
                            Button {
                                if focusedIntegerFieldIndex == nil {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                } else {
                                    focusedIntegerFieldIndex = nil
                                }
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .keyboardToolbarButtonStyle()
                            }
                            if focusedIntegerFieldIndex != nil {
                                Spacer()
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
        // Resolve `_default.` keys so bundled templates show their localized name here. Once
        // the user types, the literal text is stored and the template stops being localized —
        // renaming makes it theirs.
        Binding(get: { template.resolvedName ?? "" }, set: { template.name = $0 })
    }

    /// The template set whose rep/weight field currently holds focus, derived from the keyboard
    /// field index — mirrors the recorder's `selectedWorkoutSet`. `IntegerField.Index.primary` is
    /// the set's position in the flat `template.sets` list.
    private var selectedTemplateSet: TemplateSet? {
        guard let focusedIndex = focusedIntegerFieldIndex else { return nil }
        return template.sets.value(at: focusedIndex.primary)
    }

    @ViewBuilder
    private func interSetGroupConnector(
        after setGroup: TemplateSetGroup,
        showsTrailingLine: Bool
    ) -> some View {
        switch TemplateInterSetGroupRestDisplayState.afterSetGroup(setGroup) {
        case .hidden:
            if showsTrailingLine {
                Rectangle()
                    .foregroundStyle(.secondary)
                    .frame(width: 3, height: SECTION_SPACING)
            }

        case let .staticRest(seconds):
            templateInterSetGroupRestIndicator(showsTrailingLine: showsTrailingLine) {
                templateInterSetGroupRestCapsule {
                    let label = RestDurationLabel(
                        seconds: seconds,
                        foregroundColor: .secondary,
                        iconName: "timer",
                        textFont: .caption.weight(.semibold),
                        iconFont: .caption.weight(.semibold)
                    )

                    if let lastSet = setGroup.sets.last {
                        Button {
                            selectedRestDurationSet = lastSet
                        } label: {
                            label
                        }
                        .buttonStyle(.plain)
                    } else {
                        label
                    }
                }
            }
        }
    }

    private func templateInterSetGroupRestIndicator<Content: View>(
        showsTrailingLine: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 4) {
            Rectangle()
                .foregroundStyle(.secondary)
                .frame(width: 3, height: 6)
            content()
            if showsTrailingLine {
                Rectangle()
                    .foregroundStyle(.secondary)
                    .frame(width: 3, height: 6)
            }
        }
        .frame(minHeight: SECTION_SPACING + 10)
    }

    private func templateInterSetGroupRestCapsule<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondaryBackground)
            .clipShape(Capsule())
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
