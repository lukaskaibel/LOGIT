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
    @Binding var presentationDetentSelection: PresentationDetent

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
            VStack(spacing: 12) {
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
                    .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                    if presentationDetentSelection != .fraction(BOTTOM_SHEET_SMALL) {
                        Button {
                            sheetType = .addExercise
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                        }
                    }
                }
                .padding(.horizontal)
                if presentationDetentSelection != .fraction(BOTTOM_SHEET_SMALL) {
                    Group {
                        MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
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
                                            action: { sheetType = .addExercise }
                                        ),
                                        isShown: $isShowingNoExercisesTip
                                    )
                                    .padding(.horizontal)
                                }
                                if isSearching {
                                    // Flat list when searching - results ordered by relevance
                                    VStack(spacing: CELL_SPACING) {
                                        ForEach(sortedExercises) { exercise in
                                            Button {
                                                setExercise(exercise)
                                                presentationDetentSelection = .fraction(BOTTOM_SHEET_SMALL)
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
                                        }
                                    }
                                    .padding(.horizontal)
                                } else {
                                    // Grouped by first letter when not searching
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
                                                        presentationDetentSelection = .fraction(BOTTOM_SHEET_SMALL)
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
                                                    .id(exercise.objectID)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
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
                    }
                    .transition(.opacity)
                }
                Spacer()
            }
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isShowingNoExercisesTip = exercises.isEmpty
            }
            .onChange(of: textFieldIsFocused) { newValue in
                if newValue {
                    withAnimation {
                        presentationDetentSelection = .large
                    }
                }
            }
            .onChange(of: presentationDetentSelection) { newValue in
                if newValue != .large {
                    textFieldIsFocused = false
                }
                if newValue == .fraction(BOTTOM_SHEET_SMALL) {
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
                            presentationDetentSelection = .fraction(BOTTOM_SHEET_SMALL)
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
                        presentationDetentSelection: $presentationDetent
                    )
                    .padding(.top)
                }
                .presentationDetents([.fraction(BOTTOM_SHEET_SMALL), .medium, .large], selection: $presentationDetent)
            }
            .previewEnvironmentObjects()
    }
}

struct ExerciseSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ExerciseSelectionScreenPreviewWrapper()
    }
}
