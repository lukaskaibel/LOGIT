//
//  ExerciseListScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 19.03.22.
//

import SwiftUI

struct ExerciseListScreen: View {

    // MARK: - Environment

    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    
    // MARK: - State
    
    @State private var searchedText = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var showingAddExercise = false
    @State private var isShowingNoExercisesTip = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: ExercisePredicateFactory.getExercises(
                nameIncluding: searchedText,
                withMuscleGroup: selectedMuscleGroup
            )
        ) { exercises in
            let groupedExercises = Dictionary(grouping: exercises, by: {
                $0.name?.prefix(1) ?? ""
            }).sorted { $0.key < $1.key }
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isShowingNoExercisesTip {
                        TipView(title: NSLocalizedString("noExercisesTip", comment: ""),
                                description: NSLocalizedString("noExercisesTipDescription", comment: ""),
                                buttonAction: .init(title: NSLocalizedString("createExercise", comment: ""), action: { showingAddExercise = true }),
                                isShown: $isShowingNoExercisesTip)
                        .padding(CELL_PADDING)
                        .tileStyle()
                        .padding(.horizontal)
                    }
                    ForEach(groupedExercises, id:\.0) { key, exercises in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(key)
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(exercises) { exercise in
                                    Button {
                                        homeNavigationCoordinator.path.append(.exercise(exercise))
                                    } label: {
                                        HStack {
                                            ExerciseCell(exercise: exercise)
                                            Spacer()
                                            NavigationChevron()
                                                .foregroundColor(
                                                    exercise.muscleGroup?.color ?? .secondaryLabel
                                                )
                                        }
                                        .padding(CELL_PADDING)
                                        .tileStyle()
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .emptyPlaceholder(exercises) {
                        Text(NSLocalizedString("noExercises", comment: ""))
                    }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .searchable(text: $searchedText)
            .onAppear {
                isShowingNoExercisesTip = exercises.isEmpty
            }
            .navigationTitle(NSLocalizedString("exercises", comment: "sports activity"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddExercise.toggle() }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddExercise) {
                ExerciseEditScreen(initialMuscleGroup: selectedMuscleGroup ?? .chest)
            }
        }
    }

    // MARK: - Methods / Computed Properties

    private func getLetter(for group: [Exercise]) -> String {
        String(group.first?.name?.first ?? Character(" "))
    }

}

struct AllExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ExerciseListScreen()
        }
        .previewEnvironmentObjects()
    }
}
