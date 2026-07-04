//
//  MuscleGroupDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import Charts
import CoreData
import SwiftUI

/// The single-muscle detail: a target-share tile (the diverging `MuscleBalanceBar` showing how the
/// group's share sits against target, with a "↓ Below target / ↑ Above target / ✓ On target" pill),
/// a 2×2 stat grid, a 12-week sets chart, and the top exercises that train it. Pro — the full
/// per-muscle breakdown is the analytics behind the wall.
struct MuscleGroupDetailScreen: View {
    /// The weekly-sets chart shows 12 weeks at a time and can be panned back through history.
    private static let twelveWeeksInSeconds = 3600 * 24 * 7 * 12

    let muscleGroup: MuscleGroup

    @State private var period: StatPeriod = .month
    @State private var weeklyChartScrollPosition: Date = .now
    @State private var selectedWeekDate: Date?

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
                PeriodPicker(selection: $period)
                if groupSetCount > 0 {
                    targetShare(entry: entry, percent: percent)
                    statGrid(setCount: groupSetCount, volume: volume, sessions: sessions, rank: rank)
                    weeklyChart(allWorkouts: allWorkouts)
                    topExercises(in: periodWorkouts)
                } else {
                    emptyState
                        .containerRelativeFrame(.vertical, alignment: .center) { height, _ in
                            max(height - 96, 320)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .isBlockedWithoutPro()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // Muscle names carry their colour themselves — bold, rounded, no identity dot.
                Text(muscleGroup.description)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .onAppear {
            // Right edge shows the current week.
            weeklyChartScrollPosition = Calendar.current.date(
                byAdding: .second,
                value: -Self.twelveWeeksInSeconds,
                to: Date.now.endOfWeek
            )!
        }
    }

    // MARK: - Hero

    /// The target-share tile: the group's standing (↓ Below target / ↑ Above target / ✓ On target) +
    /// its share of sets, over the diverging `MuscleBalanceBar` — the fill grows out of the centred
    /// target tick, left when under, right when over.
    private func targetShare(entry: MuscleBalanceEntry, percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("targetShare", comment: ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.label)
                    Text(String(format: NSLocalizedString("muscleDetailPercentOfSets", comment: ""), percent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stateBadge(entry.state)
            }
            MuscleBalanceBar(entry: entry, showsName: false, showsDelta: true)
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private func stateBadge(_ state: MuscleBalanceState) -> some View {
        let word: String
        let icon: String
        let isGood: Bool
        switch state {
        case .under: word = "muscleBalanceBelowTarget"; icon = "arrow.down"; isGood = false
        case .over: word = "muscleBalanceAboveTarget"; icon = "arrow.up"; isGood = false
        case .onTarget: word = "muscleBalanceOnTargetSection"; icon = "checkmark"; isGood = true
        }
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(NSLocalizedString(word, comment: ""))
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isGood ? Color.accentColor : Color.secondaryLabel)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(isGood ? Color.accentColor.opacity(0.16) : Color.secondaryFill))
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(color.gradient)
            }
            VStack(spacing: 6) {
                Text(NSLocalizedString("muscleBalanceEmpty", comment: ""))
                    .font(.headline)
                Text(NSLocalizedString("muscleDetailEmptySubtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
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
        let weeks = grouped
            .map { (date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
        let points = weeks.map { (date: $0.date, value: Double($0.count)) }
        let yScaleCap = chartYScaleCap(
            visibleMax: chartVisibleMax(
                of: points,
                from: weeklyChartScrollPosition,
                to: Calendar.current.date(byAdding: .second, value: Self.twelveWeeksInSeconds, to: weeklyChartScrollPosition)!,
                bucketLength: 3600 * 24 * 7
            ),
            fallbackMax: points.map(\.value).max()
        )
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
                    .opacity(selectedWeekDate == nil || selectedWeekDate?.startOfWeek == week.date ? 1.0 : 0.4)
                }
                if let selectedWeekDate {
                    let snapped = selectedWeekDate.startOfWeek
                    let count = weeks.first { $0.date == snapped }?.count ?? 0
                    RuleMark(x: .value("Selected", snapped, unit: .weekOfYear))
                        .foregroundStyle(color.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            VStack(alignment: .leading) {
                                UnitView(value: "\(count)", unit: NSLocalizedString("sets", comment: ""), unitColor: .secondaryLabel)
                                    .foregroundStyle(color.gradient)
                                Text("\(snapped.formatted(.dateTime.day().month())) - \(snapped.endOfWeek.formatted(.dateTime.day().month()))")
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                        }
                }
            }
            .chartXScale(domain: weeklyXDomain(earliestWeek: weeks.first?.date))
            .chartYScale(domain: 0 ... yScaleCap)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $weeklyChartScrollPosition)
            .chartScrollTargetBehavior(.valueAligned(matching: DateComponents(weekday: Calendar.current.firstWeekday)))
            .chartXSelection(value: $selectedWeekDate)
            .chartXVisibleDomain(length: Self.twelveWeeksInSeconds)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { value in
                    // A month tick within days of the domain's end has no room for its label —
                    // it would clip to "…" — so the newest label only appears once its month
                    // has properly begun.
                    if let date = value.as(Date.self),
                       date < Calendar.current.date(byAdding: .day, value: -10, to: Date.now.endOfWeek)! {
                        AxisValueLabel {
                            Text(date.formatted(.dateTime.month(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.secondaryLabel)
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(height: 150)
            .padding(CELL_PADDING)
            .tileStyle()
        }
    }

    /// From the first trained week (or one full window back, whichever is earlier) to the end of
    /// the current week.
    private func weeklyXDomain(earliestWeek: Date?) -> ClosedRange<Date> {
        let endDate = Date.now.endOfWeek
        let minStartDate = Calendar.current.date(byAdding: .second, value: -Self.twelveWeeksInSeconds, to: endDate)!
        guard let earliestWeek, earliestWeek < minStartDate else { return minStartDate ... endDate }
        return earliestWeek ... endDate
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
