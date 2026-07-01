//
//  WeeklyGoalHeroTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The always-on weekly-goal hero at the top of the Summary screen — the fix for the dead Monday: it
/// has something to show even before the first workout of the week. Shows the shared `WeeklyGoalStrip`
/// (this week's 7 days as muscle-group rings with the weekday letter + the week's completion ring) and,
/// once a run is going, the streak scoreboard (the goal ahead vs. the current streak). Free.
struct WeeklyGoalHeroTile: View {
    let workouts: [Workout]

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(NSLocalizedString("weeklyGoal", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            WeeklyGoalStrip(workouts: workouts, target: target)
            if streak > 0 {
                StreakScoreboard(current: streak, target: streakGoal.value, targetIsBest: streakGoal.isBest)
                    .padding(CELL_PADDING - 2)
                    .secondaryTileStyle()
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    private var streak: Int {
        SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
    }

    private var previousBest: Int {
        SummaryViewModel.previousBestWeeklyStreak(workouts: workouts, target: target)
    }

    /// The goal shown in the scoreboard — the next milestone, or the best when it's the nearer goal.
    private var streakGoal: (value: Int, isBest: Bool) {
        StreakMilestone.target(current: streak, previousBest: previousBest)
    }
}

// MARK: - Weekly goal strip (shared)

/// This week rendered like a calendar week row: each day is a muscle-group occurrence ring with the
/// weekday letter inside (accent outline for today, plain letter on rest days), followed by the week's
/// completion ring on the right edge. Shared by `WeeklyGoalHeroTile` (Summary) and `WorkoutGoalScreen`'s
/// "This week" tile so the two read identically.
struct WeeklyGoalStrip: View {
    let workouts: [Workout]
    let target: Int
    /// When `true`, the date sits inside each ring (the calendar "This week" tile, so its dates line up
    /// with the month grid above). When `false` (default) the weekday letter sits inside the ring — the
    /// standalone Summary hero.
    var showsDate: Bool = false

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    private let calendar = Calendar.current

    var body: some View {
        // 8 equal columns: the 7 days + the completion ring, each centred in its column, so the leading
        // and trailing insets match (no flush-right ring) and the columns line up with the calendar grid.
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                dayCircle(day)
            }
            completionRing
                .frame(maxWidth: .infinity)
        }
    }

    private var weekDays: [Date] {
        let start = Date.now.startOfWeek
        return (0 ..< 7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
    }

    private func dayCircle(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: dayWorkouts(on: day))
        let hasWorkout = !occurrences.isEmpty
        let centerLabel = showsDate
            ? "\(calendar.component(.day, from: day))"
            : day.formatted(.dateTime.weekday(.narrow))
        return ZStack {
            if isToday {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.7)
                    .frame(width: 32, height: 32)
            } else if hasWorkout {
                MuscleOccurrenceRing(occurrences: occurrences, lineWidth: 4)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }
            Text(centerLabel)
                .font(.system(size: 13, weight: (isToday || hasWorkout) ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.accentColor : (hasWorkout ? Color.primary : Color.secondaryLabel))
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var completionRing: some View {
        let count = weekWorkoutCount
        if target > 0, count >= target {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.black)
            }
            .frame(width: 34, height: 34)
        } else if count > 0 {
            ZStack {
                CompletionRing(progress: Double(count) / Double(max(target, 1)), lineWidth: 3.5)
                Text("\(count)").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)
        } else {
            Circle()
                .strokeBorder(Color.fill, lineWidth: 2)
                .frame(width: 34, height: 34)
        }
    }

    private func dayWorkouts(on day: Date) -> [Workout] {
        workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return calendar.isDate(d, inSameDayAs: day)
        }
    }

    private var weekWorkoutCount: Int {
        let range = Date.now.startOfWeek ... Date.now.endOfWeek
        return workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return range.contains(d)
        }.count
    }
}

// MARK: - Streak line (shared)

/// A small flame + "N week streak" line shown under the weekly strip once a run is going.
struct StreakLine: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.accentColor)
            Text("\(streak)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentColor)
            Text(NSLocalizedString("weekStreakSuffix", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Streak milestones + scoreboard (shared)

/// The weekly-streak milestone ladder — a month, quarter, half-year, year, two years — shared by the
/// Summary hero and the Workout Goal screen so the two never disagree on what the next goal is.
enum StreakMilestone {
    static let all: [Int] = [4, 12, 26, 52, 104]

    /// The first milestone beyond `current`; once every milestone is passed, keep pulling a year ahead.
    static func next(after current: Int) -> Int {
        all.first(where: { $0 > current }) ?? (current + 52)
    }

    /// A calendar meaning for a milestone ("a full quarter", "a full year"). Empty for off-ladder values.
    static func fact(for weeks: Int) -> String {
        switch weeks {
        case 4: return NSLocalizedString("streakFactMonth", comment: "")
        case 12: return NSLocalizedString("streakFactQuarter", comment: "")
        case 26: return NSLocalizedString("streakFactHalfYear", comment: "")
        case 52: return NSLocalizedString("streakFactYear", comment: "")
        case 104: return NSLocalizedString("streakFactTwoYears", comment: "")
        default: return ""
        }
    }

    /// The goal to chase: the next milestone by default, so there's always a near goal ahead — unless the
    /// previous best falls between the current streak and that milestone, in which case the best is the
    /// nearer goal worth beating first.
    static func target(current: Int, previousBest: Int) -> (value: Int, isBest: Bool) {
        let next = next(after: current)
        let bestIsNearer = previousBest > current && previousBest < next
        return bestIsNearer ? (previousBest, true) : (next, false)
    }
}

/// The streak scoreboard: the goal ahead on the leading side — the next milestone (flag) or, when it's
/// the nearer goal, the personal best (flame), with a ring tracking progress — and the current streak,
/// the hero, on the trailing side. Shared by the Summary hero (in a secondary tile) and the Workout Goal
/// screen so the two read identically.
struct StreakScoreboard: View {
    let current: Int
    let target: Int
    let targetIsBest: Bool

    private var progress: Double { target > 0 ? min(Double(current) / Double(target), 1) : 0 }
    private var fact: String { targetIsBest ? "" : StreakMilestone.fact(for: target) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 11) {
                ZStack {
                    CompletionRing(progress: progress, lineWidth: 3)
                    Image(systemName: targetIsBest ? "flame.fill" : "flag")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString(targetIsBest ? "personalBest" : "nextMilestone", comment: ""))
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                    UnitView(value: "\(target)", unit: Self.weeksUnit(target), configuration: .normal, unitColor: Color.secondaryLabel)
                    if !fact.isEmpty {
                        Text(fact)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("current", comment: ""))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.secondary)
                UnitView(value: "\(current)", unit: Self.weeksUnit(current), configuration: .large, unitColor: Color.secondaryLabel)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    static func weeksUnit(_ n: Int) -> String {
        NSLocalizedString(n == 1 ? "week" : "weeks", comment: "")
    }
}

// MARK: - Muscle occurrence ring (shared)

/// A thin ring split into arcs — one per muscle group trained that day, each arc sized by that group's
/// share of the day's sets (via `getMuscleGroupOccurances`). The centre stays transparent so the day
/// number / weekday letter reads on whatever tile sits behind it.
struct MuscleOccurrenceRing: View {
    let occurrences: [(MuscleGroup, Int)]
    var lineWidth: CGFloat = 4

    var body: some View {
        let total = max(occurrences.reduce(0) { $0 + $1.1 }, 1)
        return ZStack {
            ForEach(Array(arcs(total: total).enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private func arcs(total: Int) -> [(start: CGFloat, end: CGFloat, color: Color)] {
        var result: [(start: CGFloat, end: CGFloat, color: Color)] = []
        var cursor: CGFloat = 0
        for (group, count) in occurrences {
            let end = cursor + CGFloat(count) / CGFloat(total)
            result.append((start: cursor, end: end, color: group.color))
            cursor = end
        }
        return result
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        WeeklyGoalHeroTile(workouts: workouts)
            .previewEnvironmentObjects()
            .padding()
    }
}
