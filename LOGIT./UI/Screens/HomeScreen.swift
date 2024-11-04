//
//  HomeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.09.21.
//

import CoreData
import SwiftUI

struct HomeScreen: View {

    enum NavigationDestinationType: Hashable, Identifiable {
        var id: String {
            switch self {
            case .workout(let workout): return "workout\(String(describing: workout.id))"
            default: return String(describing: self)
            }
        }
        
        case targetPerWeek, muscleGroupsOverview, exerciseList, templateList, overallSets, workoutList, measurements, workout(Workout)
    }

    // MARK: - AppStorage

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3

    // MARK: - Environment

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRepository: WorkoutRepository
    @EnvironmentObject private var workoutSetRepository: WorkoutSetRepository
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    // MARK: - State

    @State private var navigationDestinationType: NavigationDestinationType?
    @State private var showNoWorkoutTip = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingSettings = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    header
                        .padding(.horizontal)
                    
                    if showNoWorkoutTip {
                        noWorkoutTip
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 8) {
                        currentWeekWeeklyTargetWidget
                        muscleGroupPercentageView
                        overallSetsView
                        workoutsPerMonth
                        volumePerDay
                    }
                    .padding(.horizontal)
                    
                    
                    VStack(spacing: SECTION_HEADER_SPACING) {
                        HStack {
                            Text(NSLocalizedString("recentWorkouts", comment: ""))
                                .sectionHeaderStyle2()
                            Spacer()
                            Button {
                                navigationDestinationType = .workoutList
                            } label: {
                                Text(NSLocalizedString("all", comment: ""))
                            }
                        }
                        VStack(spacing: CELL_SPACING) {
                            ForEach(recentWorkouts) { workout in
                                WorkoutCell(workout: workout)
                                    .padding(CELL_PADDING)
                                    .secondaryTileStyle(backgroundColor: .secondaryBackground)
                                    .onTapGesture {
                                        navigationDestinationType = .workout(workout)
                                    }
                            }
                            .emptyPlaceholder(recentWorkouts) {
                                Text(NSLocalizedString("noWorkouts", comment: ""))
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    VStack(spacing: SECTION_HEADER_SPACING) {
                        Text(NSLocalizedString("library", comment: ""))
                            .sectionHeaderStyle2()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(spacing: CELL_SPACING) {
                            Button {
                                navigationDestinationType = .exerciseList
                            } label: {
                                HStack {
                                    HStack {
                                        Image(systemName: "dumbbell")
                                            .frame(width: 40)
                                            .foregroundStyle(Color.accentColor)
                                        Text(NSLocalizedString("exercises", comment: ""))
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                    NavigationChevron()
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                                .padding(CELL_PADDING)
                                .secondaryTileStyle(backgroundColor: .secondaryBackground)
                            }
                            
                            Button {
                                navigationDestinationType = .templateList
                            } label: {
                                HStack {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle.portrait")
                                            .frame(width: 40)
                                            .foregroundStyle(Color.accentColor)
                                        Text(NSLocalizedString("templates", comment: ""))
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                    NavigationChevron()
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                                .padding(CELL_PADDING)
                                .secondaryTileStyle(backgroundColor: .secondaryBackground)
                            }
                            Button {
                                navigationDestinationType = .measurements
                            } label: {
                                HStack {
                                    HStack {
                                        Image(systemName: "ruler")
                                            .frame(width: 40)
                                            .foregroundStyle(Color.accentColor)
                                        Text(NSLocalizedString("measurements", comment: ""))
                                            .foregroundStyle(.white)
                                    }
                                    Spacer()
                                    NavigationChevron()
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                                .padding(CELL_PADDING)
                                .secondaryTileStyle(backgroundColor: .secondaryBackground)
                            }
                        }
                        .font(.title2)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                .padding(.top)
            }
            .onAppear {
                showNoWorkoutTip = workouts.isEmpty
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsScreen()
                        .navigationTitle(NSLocalizedString("settings", comment: ""))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(NSLocalizedString("done", comment: "")) {
                                    isShowingSettings = false
                                }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $isShowingWorkoutRecorder) {
                WorkoutRecorderScreen()
                    .onAppear {
                        workoutRecorder.startWorkout()
                    }
            }
            .navigationDestination(item: $navigationDestinationType) { destination in
                switch destination {
                case .exerciseList: ExerciseListScreen()
                case .templateList: TemplateListScreen()
                case .targetPerWeek: TargetPerWeekDetailScreen()
                case .muscleGroupsOverview:
                    MuscleGroupSplitScreen()
                case .overallSets: OverallSetsScreen()
                case .workoutList: WorkoutListScreen()
                case .measurements: MeasurementsScreen()
                case .workout(let workout):
                    WorkoutDetailScreen(
                        workout: workout,
                        canNavigateToTemplate: true
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }

    // MARK: - Supporting Views

    private var header: some View {
        VStack(alignment: .leading) {
            Text(Date.now.formatted(date: .long, time: .omitted))
                .screenHeaderTertiaryStyle()
            if !purchaseManager.hasUnlockedPro {
                Text("LOGIT")
                    .screenHeaderStyle()
            } else {
                LogitProLogo()
                    .screenHeaderStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var currentWeekWeeklyTargetWidget: WidgetView<AnyView> {
        Button {
            navigationDestinationType = .targetPerWeek
        } label: {
            CurrentWeekWeeklyTargetTile()
        }
        .buttonStyle(TileButtonStyle())
        .widget(ofType: .currentWeekTargetPerWeek, isAddedByDefault: true)
    }

    private var muscleGroupPercentageView: some View {
        Button {
            navigationDestinationType = .muscleGroupsOverview
        } label: {
            MuscleGroupSplitTile()
                .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
    }
    
    private var overallSetsView: some View {
        Button {
            navigationDestinationType = .overallSets
        } label: {
            OverallSetsTile()
                .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
    }

    private var workoutsPerMonth: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("workouts", comment: ""))
                    .tileHeaderStyle()
                Text(NSLocalizedString("PerMonth", comment: ""))
                    .tileHeaderSecondaryStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DateBarChart(dateUnit: .month) {
                workoutRepository.getGroupedWorkouts(groupedBy: .date(calendarComponents: [.month, .year]))
                    .compactMap {
                        guard let date = $0.first?.date else { return nil }
                        return DateBarChart.Item(date: date, value: $0.count)
                    }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }
    
    private var volumePerDay: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("overallVolume", comment: ""))
                    .tileHeaderStyle()
                Text(WeightUnit.used.rawValue.uppercased() + " " + NSLocalizedString("perDay", comment: ""))
                    .tileHeaderSecondaryStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DateLineChart(dateDomain: .threeMonths) {
                getVolume(of: workoutSetRepository.getGroupedWorkoutsSets(in: .day))
                    .map { .init(date: $0.0, value: $0.1) }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private var noWorkoutTip: some View {
        TipView(
            title: NSLocalizedString("noWorkoutsTip", comment: ""),
            description: NSLocalizedString("noWorkoutsTipDescription", comment: ""),
            buttonAction: .init(
                title: NSLocalizedString("startWorkout", comment: ""),
                action: { isShowingWorkoutRecorder = true }
            ),
            isShown: $showNoWorkoutTip
        )
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Supportings Methods
    
    private var workouts: [Workout] {
        workoutRepository.getWorkouts()
    }

    private var recentWorkouts: [Workout] {
        Array(workouts.prefix(3))
    }
    
    

}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeScreen()
            .previewEnvironmentObjects()
    }
}
