//
//  WorkoutListScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.12.21.
//

import SwiftUI

struct WorkoutListScreen: View {

    // MARK: - Environment

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var workoutRepository: WorkoutRepository

    // MARK: - State
    
    @State private var groupingKey: WorkoutRepository.WorkoutGroupingKey = .date(calendarComponents: [.month, .year])
    @State private var searchedText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var isShowingAddWorkout = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SECTION_SPACING) {
                MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                ForEach(groupedWorkouts.indices, id: \.self) { index in
                    VStack(spacing: SECTION_HEADER_SPACING) {
                        Text(header(for: index))
                            .sectionHeaderStyle2()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: CELL_SPACING) {
                            ForEach(groupedWorkouts.value(at: index) ?? [], id: \.objectID) {
                                workout in
                                Button {
                                    homeNavigationCoordinator.path.append(.workout(workout))
                                } label: {
                                    WorkoutCell(workout: workout)
                                        .padding(CELL_PADDING)
                                        .tileStyle()
                                }
                                .buttonStyle(TileButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .emptyPlaceholder(groupedWorkouts) {
                    Text(NSLocalizedString("noWorkouts", comment: ""))
                }
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .searchable(
            text: $searchedText,
            prompt: NSLocalizedString("searchWorkouts", comment: "")
        )
        .navigationTitle(NSLocalizedString("workoutHistory", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Section {
                        Button(action: { groupingKey = .name }) {
                            Label(NSLocalizedString("name", comment: ""), systemImage: "textformat")
                        }
                        Button(action: { groupingKey = .date(calendarComponents: [.month, .year]) }) {
                            Label(NSLocalizedString("date", comment: ""), systemImage: "calendar")
                        }
                    }
                } label: {
                    Label(
                        NSLocalizedString(groupingKey == .name ? "name" : "date", comment: ""),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                Button {
                    isShowingAddWorkout = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddWorkout) {
            WorkoutEditorScreen(workout: database.newWorkout(), isAddingNewWorkout: true)
        }
    }

    // MARK: - Computed Properties

    private var groupedWorkouts: [[Workout]] {
        workoutRepository.getGroupedWorkouts(
            withNameIncluding: searchedText,
            groupedBy: groupingKey,
            usingMuscleGroup: selectedMuscleGroup
        )
    }

    private func header(for index: Int) -> String {
        switch groupingKey {
        case .date:
            guard let date = groupedWorkouts.value(at: index)?.first?.date else { return "" }
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        case .name:
            return String(groupedWorkouts.value(at: index)?.first?.name?.first ?? " ").capitalized
        }
    }

}

struct AllWorkoutsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WorkoutListScreen()
        }
        .previewEnvironmentObjects()
    }
}
