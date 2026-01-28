//
//  GlobalSearchScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.12.24.
//

import SwiftUI

struct GlobalSearchScreen: View {
    
    enum SearchResultType: String, CaseIterable, Identifiable {
        case all = "all"
        case exercises = "exercises"
        case workouts = "workouts"
        case templates = "templates"
        
        var id: String { rawValue }
        
        var displayName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }
    
    // MARK: - Environment
    
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @Environment(\.isSearching) private var isSearching
    
    // MARK: - State
    
    @State private var searchText: String = ""
    
    @State private var selectedResultType: SearchResultType = .all
    @State private var selectedExercise: Exercise?
    @State private var selectedWorkout: Workout?
    @State private var selectedTemplate: Template?
    @State private var isNavigatedToExerciseList = false
    @State private var isNavigatedToWorkoutList = false
    @State private var isNavigatedToTemplateList = false
    @State private var isNavigatedToMeasurementList = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    emptySearchView
                } else {
                    searchResultsView
                }
            }
            .searchable(text: $searchText, prompt: NSLocalizedString("searchEverything", comment: ""))
            .navigationTitle(NSLocalizedString("search", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedExercise) { exercise in
                ExerciseDetailScreen(exercise: exercise)
            }
            .navigationDestination(item: $selectedWorkout) { workout in
                WorkoutDetailScreen(workout: workout, canNavigateToTemplate: true)
            }
            .navigationDestination(item: $selectedTemplate) { template in
                TemplateDetailScreen(template: template)
            }
            .navigationDestination(isPresented: $isNavigatedToExerciseList) {
                ExerciseListScreen()
            }
            .navigationDestination(isPresented: $isNavigatedToWorkoutList) {
                WorkoutListScreen()
            }
            .navigationDestination(isPresented: $isNavigatedToTemplateList) {
                TemplateListScreen()
            }
            .navigationDestination(isPresented: $isNavigatedToMeasurementList) {
                MeasurementsScreen()
            }
        }
    }
    
    // MARK: - Views
    
    private var emptySearchView: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("searchPrompt", comment: ""))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("searchPromptDescription", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 60)
                Button {
                    isNavigatedToExerciseList = true
                } label: {
                    HStack {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(.tint)
                            .frame(minWidth: 30)
                        Text(NSLocalizedString("exercises", comment: ""))
                            .foregroundStyle(Color.label)
                        Spacer()
                        NavigationChevron()
                    }
                }
                Divider()
                Button {
                    isNavigatedToWorkoutList = true
                } label: {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.tint)
                            .frame(minWidth: 30)
                        Text(NSLocalizedString("workouts", comment: ""))
                            .foregroundStyle(Color.label)
                        Spacer()
                        NavigationChevron()
                    }
                }
                Divider()
                Button {
                    isNavigatedToTemplateList = true
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .foregroundStyle(.tint)
                            .frame(minWidth: 30)
                        Text(NSLocalizedString("templates", comment: ""))
                            .foregroundStyle(Color.label)
                        Spacer()
                        NavigationChevron()
                    }
                }
                Divider()
                Button {
                    isNavigatedToMeasurementList = true
                } label: {
                    HStack {
                        Image(systemName: "ruler.fill")
                            .foregroundStyle(.tint)
                            .frame(minWidth: 30)
                            .rotationEffect(.degrees(-45))
                        Text(NSLocalizedString("measurements", comment: ""))
                            .foregroundStyle(Color.label)
                        Spacer()
                        NavigationChevron()
                    }
                }
            }
            .font(.title2)
            .padding([.top, .horizontal])
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    
    private var searchResultsView: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.name)]
        ) { allExercises in
            FetchRequestWrapper(
                Workout.self,
                sortDescriptors: [SortDescriptor(\Workout.date, order: .reverse)]
            ) { allWorkouts in
                FetchRequestWrapper(
                    Template.self,
                    sortDescriptors: [SortDescriptor(\.name)]
                ) { allTemplates in
                    let filteredExercises = FuzzySearchService.shared.searchExercises(searchText, in: allExercises)
                    let filteredWorkouts = FuzzySearchService.shared.searchWorkouts(searchText, in: allWorkouts)
                    let filteredTemplates = FuzzySearchService.shared.searchTemplates(searchText, in: allTemplates)
                    
                    ScrollView {
                        LazyVStack(spacing: SECTION_SPACING) {
                            // Result type filter
                            resultTypeSelector
                            
                            // Exercises Section
                            if shouldShowSection(.exercises) && !filteredExercises.isEmpty {
                                exercisesSection(exercises: filteredExercises)
                            }
                            
                            // Workouts Section
                            if shouldShowSection(.workouts) && !filteredWorkouts.isEmpty {
                                workoutsSection(workouts: filteredWorkouts)
                            }
                            
                            // Templates Section
                            if shouldShowSection(.templates) && !filteredTemplates.isEmpty {
                                templatesSection(templates: filteredTemplates)
                            }
                            
                            // No Results
                            if noResults(
                                exercises: filteredExercises,
                                workouts: filteredWorkouts,
                                templates: filteredTemplates
                            ) {
                                noResultsView
                            }
                        }
                        .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                    }
                }
            }
        }
    }
    
    private var resultTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchResultType.allCases) { type in
                    Button {
                        withAnimation {
                            selectedResultType = type
                        }
                    } label: {
                        Text(type.displayName)
                            .font(.subheadline)
                            .fontWeight(selectedResultType == type ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedResultType == type
                                    ? Color.accentColor
                                    : Color(.systemGray5)
                            )
                            .foregroundColor(
                                selectedResultType == type
                                    ? .white
                                    : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    private func exercisesSection(exercises: [Exercise]) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("exercises", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text("\(exercises.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: CELL_SPACING) {
                ForEach(exercises.prefix(selectedResultType == .all ? 5 : exercises.count)) { exercise in
                    Button {
                        selectedExercise = exercise
                    } label: {
                        HStack {
                            ExerciseCell(exercise: exercise)
                            Spacer()
                            NavigationChevron()
                                .foregroundColor(exercise.muscleGroup?.color ?? .secondaryLabel)
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                    }
                    .buttonStyle(TileButtonStyle())
                }
                
                if selectedResultType == .all && exercises.count > 5 {
                    showMoreButton(count: exercises.count - 5, type: .exercises)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func workoutsSection(workouts: [Workout]) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("workouts", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text("\(workouts.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: CELL_SPACING) {
                ForEach(workouts.prefix(selectedResultType == .all ? 5 : workouts.count)) { workout in
                    Button {
                        selectedWorkout = workout
                    } label: {
                        WorkoutCell(workout: workout)
                    }
                    .buttonStyle(TileButtonStyle())
                }
                
                if selectedResultType == .all && workouts.count > 5 {
                    showMoreButton(count: workouts.count - 5, type: .workouts)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func templatesSection(templates: [Template]) -> some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("templates", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text("\(templates.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: CELL_SPACING) {
                ForEach(templates.prefix(selectedResultType == .all ? 5 : templates.count)) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        HStack {
                            TemplateCell(template: template)
                            NavigationChevron()
                                .foregroundStyle(.secondary)
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                    }
                    .buttonStyle(TileButtonStyle())
                }
                
                if selectedResultType == .all && templates.count > 5 {
                    showMoreButton(count: templates.count - 5, type: .templates)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func showMoreButton(count: Int, type: SearchResultType) -> some View {
        Button {
            withAnimation {
                selectedResultType = type
            }
        } label: {
            HStack {
                Text(String(format: NSLocalizedString("showMoreResults", comment: ""), count))
                    .font(.subheadline)
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(NSLocalizedString("noSearchResults", comment: ""))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("noSearchResultsFor", comment: ""), searchText))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Helper Methods
    
    private func shouldShowSection(_ type: SearchResultType) -> Bool {
        selectedResultType == .all || selectedResultType == type
    }
    
    private func noResults(
        exercises: [Exercise],
        workouts: [Workout],
        templates: [Template]
    ) -> Bool {
        let showingExercises = shouldShowSection(.exercises) && !exercises.isEmpty
        let showingWorkouts = shouldShowSection(.workouts) && !workouts.isEmpty
        let showingTemplates = shouldShowSection(.templates) && !templates.isEmpty
        
        return !showingExercises && !showingWorkouts && !showingTemplates
    }
}

// MARK: - Preview

struct GlobalSearchScreen_Previews: PreviewProvider {
    static var previews: some View {
        GlobalSearchScreen()
            .previewEnvironmentObjects()
    }
}
