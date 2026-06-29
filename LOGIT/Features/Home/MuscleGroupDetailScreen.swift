//
//  MuscleGroupDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import CoreData
import SwiftUI

/// The single-muscle detail (`muscle-group-screens.html` screen 2): a muscle-coloured gradient header
/// with the `BodyMapFigure`, a target-share tile, a 2×2 stat grid, a 12-week sets chart, and the top
/// exercises that train it. Pro — the full per-muscle breakdown is the analytics behind the wall.
struct MuscleGroupDetailScreen: View {
    let muscleGroup: MuscleGroup

    @State private var period: StatPeriod = .month

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var targetSplitStore: MuscleTargetSplitStore
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator

    private var color: Color { muscleGroup.color }

    var body: some View {
        FetchRequestWrapper(
            Workout.self,
            sortDescriptors: [SortDescriptor(\.date, order: .reverse)],
            predicate: WorkoutPredicateFactory.getWorkouts()
        ) { allWorkouts in
            content(allWorkouts: allWorkouts)
        }
    }

    private func content(allWorkouts: [Workout]) -> some View {
        let range = period.currentRange()
        let periodWorkouts = allWorkouts.filter { ($0.date).map { range.contains($0) } ?? false }
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: periodWorkouts)
        let total = occurrences.reduce(0) { $0 + $1.1 }
        let groupSetCount = occurrences.first { $0.0 == muscleGroup }?.1 ?? 0
        let percent = total > 0 ? Int((Double(groupSetCount) / Double(total) * 100).rounded()) : 0
        let rank = (occurrences.firstIndex { $0.0 == muscleGroup }).map { $0 + 1 } ?? MuscleGroup.allCases.count
        let setGroups = setGroupsTraining(in: periodWorkouts)
        let sessions = Set(setGroups.compactMap { $0.workout?.objectID }).count
        let volume = getVolume(of: setGroups.flatMap { $0.sets })
        let calculator = MuscleBalanceCalculator(workouts: periodWorkouts, target: targetSplitStore.split, muscleGroupService: muscleGroupService)
        let entry = calculator.entries.first { $0.muscleGroup == muscleGroup }
            ?? MuscleBalanceEntry(muscleGroup: muscleGroup, setCount: 0, actualPercent: 0, targetPercent: targetSplitStore.target(for: muscleGroup))

        return ScrollView {
            VStack(spacing: SECTION_SPACING) {
                header(percent: percent)
                VStack(spacing: 16) {
                    PeriodPicker(selection: $period)
                    targetShareTile(entry: entry)
                    statGrid(setCount: groupSetCount, volume: volume, sessions: sessions, rank: rank)
                    weeklyChart(allWorkouts: allWorkouts)
                    topExercises(in: periodWorkouts)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private func header(percent: Int) -> some View {
        HStack(spacing: 16) {
            BodyMapFigure(
                highlighted: BodyRegion(muscleGroup),
                color: .black.opacity(0.5),
                baseColor: .black.opacity(0.28)
            )
            .frame(width: 52, height: 116)
            VStack(alignment: .leading, spacing: 4) {
                Text(muscleGroup.description)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.black)
                Text(String(format: NSLocalizedString("muscleDetailPercentOfSets", comment: ""), percent))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 60)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.gradient)
    }

    // MARK: - Target share

    private func targetShareTile(entry: MuscleBalanceEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("targetShare", comment: ""))
                .font(.subheadline.weight(.semibold))
            MuscleBalanceBar(entry: entry, showsName: false, showsDelta: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Stat grid

    private func statGrid(setCount: Int, volume: Int, sessions: Int, rank: Int) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            statTile(title: NSLocalizedString("sets", comment: ""), value: "\(setCount)", unit: NSLocalizedString("sets", comment: ""), caption: periodCaption)
            statTile(title: NSLocalizedString("volume", comment: ""), value: formatWeightForDisplay(volume), unit: WeightUnit.used.rawValue, caption: periodCaption)
            statTile(title: NSLocalizedString("sessions", comment: ""), value: "\(sessions)", unit: "", caption: periodCaption)
            statTile(title: NSLocalizedString("rank", comment: ""), value: "#\(rank)", unit: "", caption: NSLocalizedString("muscleDetailRankCaption", comment: ""))
        }
    }

    private func statTile(title: String, value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
            UnitView(value: value, unit: unit, configuration: .large, unitColor: .secondaryLabel)
                .foregroundStyle(color.gradient)
                .padding(.top, 10)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Weekly chart

    private func weeklyChart(allWorkouts: [Workout]) -> some View {
        let sets = setsTraining(in: allWorkouts)
        let grouped = Dictionary(grouping: sets) { ($0.workout?.date ?? .now).startOfWeek }
        let weeks: [(date: Date, count: Int)] = (0 ..< 12).reversed().map { weeksAgo in
            let start = (Calendar.current.date(byAdding: .weekOfYear, value: -weeksAgo, to: .now) ?? .now).startOfWeek
            return (start, grouped[start]?.count ?? 0)
        }
        let maxCount = weeks.map(\.count).max() ?? 0
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("weeklySets", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                Text(NSLocalizedString("twelveWeeks", comment: ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(weeks, id: \.date) { week in
                    BarMark(
                        x: .value("Week", week.date, unit: .weekOfYear),
                        y: .value("Sets", week.count),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(Calendar.current.isDate(week.date, equalTo: .now, toGranularity: .weekOfYear) ? color : Color.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .chartYScale(domain: 0 ... max(maxCount, 1))
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 120)
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    // MARK: - Top exercises

    private func topExercises(in workouts: [Workout]) -> some View {
        var byExercise: [NSManagedObjectID: (exercise: Exercise, count: Int)] = [:]
        for setGroup in setGroupsTraining(in: workouts) {
            let count = setGroup.sets.count
            if setGroup.exercise?.muscleGroup == muscleGroup, let exercise = setGroup.exercise {
                byExercise[exercise.objectID, default: (exercise, 0)].count += count
            }
            if setGroup.secondaryExercise?.muscleGroup == muscleGroup, let exercise = setGroup.secondaryExercise {
                byExercise[exercise.objectID, default: (exercise, 0)].count += count
            }
        }
        let top = byExercise.values.sorted { $0.count > $1.count }.prefix(5)
        return VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("topExercises", comment: ""))
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                let items = Array(top)
                ForEach(Array(items.enumerated()), id: \.element.exercise.objectID) { index, item in
                    Button {
                        homeNavigationCoordinator.path.append(.exercise(item.exercise))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.subheadline)
                                .foregroundStyle(color.gradient)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Color.fill))
                            Text(item.exercise.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.label)
                                .lineLimit(1)
                            Spacer()
                            UnitView(value: "\(item.count)", unit: NSLocalizedString("sets", comment: ""), unitColor: .secondaryLabel)
                                .foregroundStyle(.secondary)
                            NavigationChevron()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < items.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, CELL_PADDING)
            .tileStyle()
            .emptyPlaceholder(Array(top)) {
                Text(NSLocalizedString("noData", comment: ""))
            }
        }
    }

    // MARK: - Helpers

    private var periodCaption: String {
        switch period {
        case .week: return NSLocalizedString("thisWeek", comment: "")
        case .month: return NSLocalizedString("thisMonth", comment: "")
        case .year: return NSLocalizedString("thisYear", comment: "")
        }
    }

    private func setGroupsTraining(in workouts: [Workout]) -> [WorkoutSetGroup] {
        workouts.flatMap { $0.setGroups }.filter {
            $0.exercise?.muscleGroup == muscleGroup || $0.secondaryExercise?.muscleGroup == muscleGroup
        }
    }

    private func setsTraining(in workouts: [Workout]) -> [WorkoutSet] {
        setGroupsTraining(in: workouts).flatMap { $0.sets }
    }
}
