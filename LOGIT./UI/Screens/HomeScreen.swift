//
//  HomeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.09.21.
//

import CoreData
import SwiftUI

struct HomeScreen: View {

    enum NavigationDestinationType: Hashable {
        case targetPerWeek, muscleGroupsOverview, exerciseList, templateList, overallSets
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
    @State private var selectedWorkout: Workout?
    @State private var showNoWorkoutTip = false
    @State private var isShowingWorkoutRecorder = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SECTION_SPACING) {
                    header
                        .padding([.horizontal, .top])

                    if showNoWorkoutTip {
                        noWorkoutTip
                            .padding(.horizontal)
                    }

                    VStack(spacing: 0) {
                        Button {
                            navigationDestinationType = .exerciseList
                        } label: {
                            HStack {
                                HStack {
                                    Image(systemName: "dumbbell")
                                        .frame(width: 40)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("exercises", comment: ""))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                NavigationChevron()
                                    .foregroundStyle(Color.secondaryLabel)
                            }
                            .padding(.trailing)
                            .padding(.vertical, 12)
                        }
                        Divider()
                            .padding(.leading, 45)
                        Button {
                            navigationDestinationType = .templateList
                        } label: {
                            HStack {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                        .frame(width: 40)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("templates", comment: ""))
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                NavigationChevron()
                                    .foregroundStyle(Color.secondaryLabel)
                            }
                            .padding(.trailing)
                            .padding(.vertical, 12)
                        }
                        Divider()
                            .padding(.leading, 45)
                    }
                    .font(.title2)
                    .padding(.leading)

                    WidgetCollectionView(
                        type: .homeScreen,
                        title: NSLocalizedString("overview", comment: ""),
                        views: [
                            currentWeekWeeklyTargetWidget,
                            muscleGroupPercentageView.widget(ofType: .muscleGroupsInLastTen, isAddedByDefault: true),
                            overallSetsView.widget(ofType: .setsPerWeek, isAddedByDefault: true),
                            workoutsPerMonth.widget(ofType: .workoutsPerMonth, isAddedByDefault: false),
                            volumePerDay.widget(ofType: .homeScreenVolumePerDay, isAddedByDefault: false)
                        ],
                        database: database
                    )
                    .padding(.horizontal)
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                .padding(.top)
            }
            .onAppear {
                showNoWorkoutTip = workouts.isEmpty
            }
            .scrollIndicators(.hidden)
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

    var workouts: [Workout] {
        workoutRepository.getWorkouts(sortedBy: .date)
    }

}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeScreen()
            .previewEnvironmentObjects()
    }
}
