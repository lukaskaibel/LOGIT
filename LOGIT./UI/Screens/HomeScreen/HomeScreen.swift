//
//  HomeScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 24.09.21.
//

import CoreData
import SwiftUI
import WishKit

struct HomeScreen: View {

    // MARK: - AppStorage

    @AppStorage("workoutPerWeekTarget") var targetPerWeek: Int = 3

    // MARK: - Environment

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

    // MARK: - State

    @State private var showNoWorkoutTip = false
    @State private var isShowingWorkoutRecorder = false
    @State private var isShowingSettings = false
    @State private var isShowingWishkit = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { workouts in
            NavigationStack(path: $homeNavigationCoordinator.path) {
                ScrollView {
                    VStack(spacing: 5) {
                        header
                            .padding([.top, .horizontal])
                        VStack(spacing: SECTION_SPACING) {
                            if showNoWorkoutTip {
                                noWorkoutTip
                                    .padding(.horizontal)
                            }
                            VStack(spacing: 0) {
                                Button {
                                    homeNavigationCoordinator.path.append(.exerciseList)
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
                                    .padding(.trailing)
                                    .padding(.vertical, 12)
                                }
                                Divider()
                                    .padding(.leading, 45)
                                Button {
                                    homeNavigationCoordinator.path.append(.templateList)
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
                                    .padding(.trailing)
                                    .padding(.vertical, 12)
                                }
                                Divider()
                                    .padding(.leading, 45)
                                Button {
                                    homeNavigationCoordinator.path.append(.measurements)
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
                                    .padding(.trailing)
                                    .padding(.vertical, 12)
                                }
                                Divider()
                                    .padding(.leading, 45)
                            }
                            .font(.title2)
                            .padding(.horizontal)
                            
                            VStack(spacing: SECTION_HEADER_SPACING) {
                                Text(NSLocalizedString("summary", comment: ""))
                                    .sectionHeaderStyle2()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(spacing: 8) {
                                    currentWeekWeeklyTargetWidget
                                    Button {
                                        homeNavigationCoordinator.path.append(.overallSets)
                                    } label: {
                                        OverallSetsTile(workouts: workouts)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TileButtonStyle())
                                    Button {
                                        homeNavigationCoordinator.path.append(.volume)
                                    } label: {
                                        VolumeTile(workouts: workouts)
                                    }
                                    .buttonStyle(TileButtonStyle())
                                    Button {
                                        homeNavigationCoordinator.path.append(.muscleGroupsOverview)
                                    } label: {
                                        MuscleGroupSplitTile(workouts: workouts)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(TileButtonStyle())

                                }
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: SECTION_HEADER_SPACING) {
                                HStack {
                                    Text(NSLocalizedString("recentWorkouts", comment: ""))
                                        .sectionHeaderStyle2()
                                    Spacer()
                                    Button {
                                        homeNavigationCoordinator.path.append(.workoutList)
                                    } label: {
                                        HStack {
                                            Text(NSLocalizedString("all", comment: ""))
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                        }
                                    }
                                    .fontWeight(.semibold)
                                }
                                VStack(spacing: CELL_SPACING) {
                                    let recentWorkouts = workouts.prefix(3)
                                    ForEach(recentWorkouts) { workout in
                                        Button {
                                            homeNavigationCoordinator.path.append(.workout(workout))
                                        } label: {
                                            WorkoutCell(workout: workout)
                                                .padding(CELL_PADDING)
                                                .secondaryTileStyle(backgroundColor: .secondaryBackground)
                                        }
                                        .buttonStyle(TileButtonStyle())
                                    }
                                    .emptyPlaceholder(recentWorkouts) {
                                        Text(NSLocalizedString("noWorkouts", comment: ""))
                                    }
                                }
                            }
                            .padding(.horizontal)
                            VStack {
                                Button {
                                    isShowingWishkit = true
                                } label: {
                                    Label(NSLocalizedString("whatsStillMissing", comment: ""), systemImage: "questionmark.bubble.fill")
                                }
                                .buttonStyle(SecondaryBigButtonStyle())
                            }
                            .padding(.horizontal)
                            .padding(.top, 30)
                        }
                        .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                    }
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
                .sheet(isPresented: $isShowingWishkit) {
                    WishKit.FeedbackListView().withNavigation()
                        .onAppear {
                            WishKit.configure(with: WISHKIT_API_KEY)
                            WishKit.config.allowUndoVote = true
                            WishKit.theme.primaryColor = .accentColor
                            WishKit.config.buttons.saveButton.textColor = .setBoth(to: .black)
                        }
                }
                .navigationDestination(for: HomeNavigationDestinationType.self) { destination in
                    switch destination {
                        case .exercise(let exercise):
                            ExerciseDetailScreen(exercise: exercise)
                        case .exerciseList: ExerciseListScreen()
                        case .measurements: MeasurementsScreen()
                        case .muscleGroupsOverview:
                            MuscleGroupSplitScreen()
                        case .overallSets: OverallSetsScreen()
                        case .targetPerWeek: TargetPerWeekDetailScreen()
                        case .template(let template):
                            TemplateDetailScreen(template: template)
                        case .templateList: TemplateListScreen()
                        case .volume: VolumeScreen()
                        case .workout(let workout):
                            WorkoutDetailScreen(
                                workout: workout,
                                canNavigateToTemplate: true
                            )
                        case .workoutList: WorkoutListScreen()
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
    
    private var currentWeekWeeklyTargetWidget: some View {
        Button {
            homeNavigationCoordinator.path.append(.targetPerWeek)
        } label: {
            CurrentWeekWeeklyTargetTile()
        }
        .buttonStyle(TileButtonStyle())
    }

    private var noWorkoutTip: some View {
        TipView(
            title: NSLocalizedString("noWorkoutsTip", comment: ""),
            description: NSLocalizedString("noWorkoutsTipDescription", comment: ""),
            buttonAction: nil,
            isShown: $showNoWorkoutTip
        )
        .padding(CELL_PADDING)
        .tileStyle()
    }

}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeScreen()
            .previewEnvironmentObjects()
    }
}
