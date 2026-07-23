//
//  ExerciseSelectionScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.12.21.
//

import CoreData
import SwiftUI

struct ExerciseSelectionScreen: View {
    enum SheetType: Identifiable {
        case addExercise
        case exerciseDetail(exercise: Exercise)
        var id: Int {
            switch self {
            case .addExercise: return 0
            case .exerciseDetail: return 1
            }
        }
    }

    /// A Create Exercise presentation delegated to the host: the prefilled name
    /// (current search text) and the muscle-group filter at the moment of the request.
    struct AddExerciseRequest: Identifiable {
        let id = UUID()
        let name: String
        let muscleGroup: MuscleGroup?
    }

    // MARK: - Environment

    @EnvironmentObject private var exerciseSuggestionService: ExerciseSuggestionService

    // MARK: - State

    @State private var searchedText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var sheetType: SheetType?
    @State private var isShowingNoExercisesTip = false
    @State private var selectedExerciseForDetail: Exercise?
    @FocusState private var textFieldIsFocused

    // MARK: - Binding

    let selectedExercise: Exercise?
    let setExercise: (Exercise) -> Void
    let forSecondary: Bool
    let currentWorkoutExercises: [Exercise]
    let supersetPrimaryExercise: Exercise?
    @Binding var presentationDetentSelection: PresentationDetent
    /// When set, Create Exercise is delegated to the host instead of being presented
    /// from this screen's own hierarchy. Hosts that show this screen inside a
    /// persistent background-interactive tray MUST delegate: stacking a sheet onto the
    /// tray makes UIKit dismiss and re-present the tray, and a nested sheet whose
    /// owning state lives inside the recycled tray content is torn down with it —
    /// only host-owned state survives the cycle (see TemplateEditorScreen).
    var onRequestAddExercise: ((AddExerciseRequest) -> Void)? = nil
    /// Same delegation for the context menus' "Show Details" sheet.
    var onRequestExerciseDetail: ((Exercise) -> Void)? = nil

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: ExercisePredicateFactory.getExercises(
                nameIncluding: "",
                withMuscleGroup: selectedMuscleGroup
            )
        ) { allExercises in
            let exercises = FuzzySearchService.shared.searchExercises(searchedText, in: allExercises)
            let sortedExercises = searchedText.isEmpty 
                ? exercises.sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
                : exercises // Keep fuzzy search order when searching
            let groupedExercises = Dictionary(grouping: sortedExercises, by: {
                $0.displayNameFirstLetter
            }).sorted { $0.key < $1.key }
            let isSearching = !searchedText.isEmpty
            let suggestedExercises: [Exercise] = {
                if forSecondary, let primary = supersetPrimaryExercise {
                    return exerciseSuggestionService.suggestedSupersetPartners(
                        forPrimary: primary,
                        currentWorkoutExercises: currentWorkoutExercises,
                        allExercises: Array(allExercises)
                    )
                } else {
                    return exerciseSuggestionService.suggestedExercises(
                        currentWorkoutExercises: currentWorkoutExercises,
                        allExercises: Array(allExercises)
                    )
                }
            }()
            let isSmallDetent = presentationDetentSelection == .height(BOTTOM_SHEET_SMALL)
            VStack(spacing: 0) {
                searchRow(isSmallDetent: isSmallDetent)
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 12)
                if !isSmallDetent {
                    VStack(spacing: 12) {
                        MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                        exerciseList(
                            exercises: exercises,
                            sortedExercises: sortedExercises,
                            groupedExercises: groupedExercises,
                            suggestedExercises: suggestedExercises,
                            isSearching: isSearching
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isShowingNoExercisesTip = exercises.isEmpty
            }
            .onChange(of: textFieldIsFocused) { _, newValue in
                if newValue {
                    withAnimation {
                        presentationDetentSelection = .large
                    }
                }
            }
            .onChange(of: presentationDetentSelection) { _, newValue in
                if newValue != .large {
                    textFieldIsFocused = false
                }
                if newValue == .height(BOTTOM_SHEET_SMALL) {
                    searchedText = ""
                }
            }
            .sheet(item: $selectedExerciseForDetail) { exercise in
                NavigationStack {
                    ExerciseDetailScreen(exercise: exercise, isShowingAsSheet: true)
                }
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $sheetType) { type in
                switch type {
                case .addExercise:
                    ExerciseEditScreen(
                        onEditFinished: {
                            setExercise($0)
                            presentationDetentSelection = .height(BOTTOM_SHEET_SMALL)
                        },
                        initialExerciseName: searchedText.trimmingCharacters(in: .whitespacesAndNewlines).capitalized,
                        initialMuscleGroup: selectedMuscleGroup ?? .chest
                    )
                case let .exerciseDetail(exercise):
                    NavigationStack {
                        ExerciseDetailScreen(exercise: exercise, isShowingAsSheet: true)
                    }
                }
            }
        }
    }

    // MARK: - Presentation

    /// Create Exercise: delegated to the host when it asked for it (tray hosts —
    /// see `onRequestAddExercise`), otherwise presented from this screen.
    private func showAddExercise() {
        if let onRequestAddExercise {
            onRequestAddExercise(
                AddExerciseRequest(
                    name: searchedText.trimmingCharacters(in: .whitespacesAndNewlines).capitalized,
                    muscleGroup: selectedMuscleGroup
                )
            )
        } else {
            sheetType = .addExercise
        }
    }

    /// "Show Details": same host delegation as `showAddExercise`.
    private func showExerciseDetail(_ exercise: Exercise) {
        if let onRequestExerciseDetail {
            onRequestExerciseDetail(exercise)
        } else {
            selectedExerciseForDetail = exercise
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func searchRow(isSmallDetent: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.placeholder)
                TextField(
                    "Add Exercise",
                    text: $searchedText,
                    prompt: Text(NSLocalizedString("searchExercises", comment: ""))
                )
                .focused($textFieldIsFocused)
                if !searchedText.isEmpty {
                    Button {
                        searchedText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(Color.placeholder)
                }
            }
            .font(.title3)
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .background(Color(.systemGray5))
            .clipShape(.capsule)
            if !isSmallDetent {
                Button {
                    showAddExercise()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseList(
        exercises: [Exercise],
        sortedExercises: [Exercise],
        groupedExercises: [(key: String, value: [Exercise])],
        suggestedExercises: [Exercise],
        isSearching: Bool
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    if isShowingNoExercisesTip {
                        TipView(
                            category: NSLocalizedString("exerciseLibrary", comment: ""),
                            title: NSLocalizedString("noExercisesTip", comment: ""),
                            description: NSLocalizedString("noExercisesTipDescription", comment: ""),
                            buttonAction: .init(
                                title: NSLocalizedString("createExercise", comment: ""),
                                action: { showAddExercise() }
                            ),
                            isShown: $isShowingNoExercisesTip
                        )
                        .padding(.horizontal)
                    }
                    if !isSearching && !suggestedExercises.isEmpty && selectedMuscleGroup == nil {
                        suggestedSection(suggestedExercises: suggestedExercises)
                    }
                    if isSearching {
                        flatExerciseList(sortedExercises: sortedExercises)
                    } else {
                        groupedExerciseList(groupedExercises: groupedExercises)
                    }
                    EmptyView()
                        .emptyPlaceholder(exercises) {
                            if exercises.isEmpty {
                                Text(NSLocalizedString("pressPlusToAddExercise", comment: ""))
                            } else {
                                Text(String(format: NSLocalizedString("pressPlusToAdd", comment: ""), searchedText))
                            }
                        }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .onAppear {
                if let selected = selectedExercise {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            scrollProxy.scrollTo(selected.objectID, anchor: .center)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func suggestedSection(suggestedExercises: [Exercise]) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text(NSLocalizedString("suggested", comment: ""))
            }
            .sectionHeaderStyle2()
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: CELL_SPACING) {
                ForEach(suggestedExercises) { exercise in
                    Button {
                        setExercise(exercise)
                        presentationDetentSelection = .height(BOTTOM_SHEET_SMALL)
                    } label: {
                        HStack {
                            ExerciseCell(exercise: exercise)
                            Spacer()
                            NavigationChevron()
                                .foregroundStyle(.secondary)
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .contextMenu {
                        Button {
                            showExerciseDetail(exercise)
                        } label: {
                            Label(NSLocalizedString("showDetails", comment: ""), systemImage: "info.circle")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func flatExerciseList(sortedExercises: [Exercise]) -> some View {
        VStack(spacing: CELL_SPACING) {
            ForEach(sortedExercises) { exercise in
                Button {
                    setExercise(exercise)
                    presentationDetentSelection = .height(BOTTOM_SHEET_SMALL)
                } label: {
                    HStack {
                        ExerciseCell(exercise: exercise)
                        Spacer()
                        if exercise == selectedExercise {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundColor(exercise.muscleGroup?.color)
                        }
                        NavigationChevron()
                            .foregroundStyle(.secondary)
                    }
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                .contextMenu {
                    Button {
                        showExerciseDetail(exercise)
                    } label: {
                        Label(NSLocalizedString("showDetails", comment: ""), systemImage: "info.circle")
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func groupedExerciseList(groupedExercises: [(key: String, value: [Exercise])]) -> some View {
        ForEach(groupedExercises, id: \.0) { key, exercises in
            VStack(spacing: SECTION_HEADER_SPACING) {
                Text(key)
                    .textCase(.uppercase)
                    .sectionHeaderStyle2()
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: CELL_SPACING) {
                    ForEach(exercises) { exercise in
                        Button {
                            setExercise(exercise)
                            presentationDetentSelection = .height(BOTTOM_SHEET_SMALL)
                        } label: {
                            HStack {
                                ExerciseCell(exercise: exercise)
                                Spacer()
                                if exercise == selectedExercise {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(exercise.muscleGroup?.color ?? .accentColor)
                                }
                                NavigationChevron()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(CELL_PADDING)
                            .tileStyle()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TileButtonStyle())
                        .contextMenu {
                            Button {
                                showExerciseDetail(exercise)
                            } label: {
                                Label(NSLocalizedString("showDetails", comment: ""), systemImage: "info.circle")
                            }
                        }
                        .id(exercise.objectID)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Preview

private struct ExerciseSelectionScreenPreviewWrapper: View {
    @State private var presentationDetent: PresentationDetent = .medium

    var body: some View {
        Rectangle()
            .sheet(isPresented: .constant(true)) {
                NavigationView {
                    ExerciseSelectionScreen(
                        selectedExercise: nil,
                        setExercise: { _ in },
                        forSecondary: false,
                        currentWorkoutExercises: [],
                        supersetPrimaryExercise: nil,
                        presentationDetentSelection: $presentationDetent
                    )
                }
                .presentationDetents([.height(BOTTOM_SHEET_SMALL), .medium, .large], selection: $presentationDetent)
            }
            .previewEnvironmentObjects()
    }
}

struct ExerciseSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseSelectionScreenPreviewWrapper()
    }
}
