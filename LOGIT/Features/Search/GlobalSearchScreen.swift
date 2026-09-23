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
                // Whitespace alone is still an empty search — it used to fall
                // through and score every exercise against a space.
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptySearchView
                } else {
                    searchResultsView
                }
            }
            // `.always` keeps the field under the title instead of hiding it
            // until the first scroll. On iOS 26 the search-role tab lifts the
            // field into the tab bar and ignores the placement; where it does
            // not, this is the difference between a visible field and none.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("searchEverything", comment: "")
            )
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
                    // Parsed against the library's names as shown — a built-in exercise stores a
                    // localisation key, not its name — so a half-typed date word that starts one of
                    // them ("mit", "Di") keeps finding the exercise instead of becoming a date.
                    let query = SearchQueryParser(
                        names: allExercises.map(\.displayName) + allTemplates.map(\.displayName)
                    ).parse(searchText)
                    let results = SearchEngine.shared.results(
                        for: query,
                        exercises: allExercises,
                        workouts: allWorkouts,
                        templates: allTemplates
                    )

                    ScrollView {
                        LazyVStack(spacing: SECTION_SPACING) {
                            // What the query was understood to mean. A date
                            // query can only match workouts, so the type filter
                            // has nothing left to choose between.
                            if query.hasDateConstraint {
                                dateTokenRow(tokens: query.dateTokens)
                            } else {
                                resultTypeSelector
                            }

                            // Exercises Section
                            if shouldShowSection(.exercises, in: query) && !results.exercises.isEmpty {
                                exercisesSection(exercises: results.exercises)
                            }

                            // Workouts Section
                            if shouldShowSection(.workouts, in: query) && !results.workouts.isEmpty {
                                workoutsSection(workouts: results.workouts)
                            }

                            // Templates Section
                            if shouldShowSection(.templates, in: query) && !results.templates.isEmpty {
                                templatesSection(templates: results.templates)
                            }

                            // No Results
                            if noResults(results, in: query) {
                                noResultsView(for: query)
                            }
                        }
                        .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                    }
                }
            }
        }
    }

    private func dateTokenRow(tokens: [SearchDateToken]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tokens) { token in
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                        Text(token.label())
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
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
                        TemplateCell(template: template)
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
    
    private func noResultsView(for query: SearchQuery) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(NSLocalizedString("noSearchResults", comment: ""))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("noSearchResultsFor", comment: ""), description(of: query)))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Methods

    /// A date query can only ever match workouts, so the remembered result type
    /// must not be allowed to hide the one section that has something to show.
    private func shouldShowSection(_ type: SearchResultType, in query: SearchQuery) -> Bool {
        guard !query.hasDateConstraint else { return type == .workouts }
        return selectedResultType == .all || selectedResultType == type
    }

    private func noResults(_ results: SearchResults, in query: SearchQuery) -> Bool {
        let showingExercises = shouldShowSection(.exercises, in: query) && !results.exercises.isEmpty
        let showingWorkouts = shouldShowSection(.workouts, in: query) && !results.workouts.isEmpty
        let showingTemplates = shouldShowSection(.templates, in: query) && !results.templates.isEmpty

        return !showingExercises && !showingWorkouts && !showingTemplates
    }

    /// What to quote back in "No results for …" — the date the query resolved to
    /// rather than the raw words, so "dez 24" reads back as "December 2024".
    private func description(of query: SearchQuery) -> String {
        guard query.hasDateConstraint else { return searchText }
        let dates = query.dateTokens.map { $0.label() }.joined(separator: ", ")
        return query.text.isEmpty ? dates : "\(query.text) · \(dates)"
    }
}

// MARK: - Preview

struct GlobalSearchScreen_Previews: PreviewProvider {
    static var previews: some View {
        GlobalSearchScreen()
            .previewEnvironmentObjects()
    }
}
