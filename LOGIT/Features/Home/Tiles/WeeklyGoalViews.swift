//
//  WeeklyGoalViews.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

// The weekly-goal views, shared by `WorkoutGoalScreen` and (for the streak milestones) the Summary's
// `WeeklyGoalCountPill`. The Summary's own hero tile that used to lead this file is gone: once
// This Week and Progress merged into one scroll, the week became one fact among many and shrank to
// the title-row pill, with the full week a tap away on the goal screen.
//
// The `StreakLine` and `StreakScoreboard` that used to live here went with the goal screen's
// redesign: the line's flame-and-number is now a row on that screen, and the scoreboard's
// current-versus-goal became the first row of its milestone list, ring and all.

// MARK: - Weekly goal strip (shared)

/// This week rendered like a calendar week row: each day is a muscle-group occurrence ring with the
/// weekday letter inside (accent outline for today, plain letter on rest days), optionally followed by
/// the week's completion ring on the right edge. Rendered by `WorkoutGoalScreen` under its arc.
struct WeeklyGoalStrip: View {
    let workouts: [Workout]
    let target: Int
    /// When `true`, the date sits inside each ring (a calendar context, so the dates line up with a
    /// month grid). When `false` (default) the weekday letter sits inside the ring.
    var showsDate: Bool = false
    /// The week's own progress ring on the trailing edge. Off wherever the count is already the
    /// subject above the strip — on the goal screen the arc says it, and two rings would say it twice.
    var showsCompletionRing: Bool = true

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    private let calendar = Calendar.current

    var body: some View {
        // Equal columns — the 7 days plus the completion ring when it's shown — each centred in its
        // own column, so the leading and trailing insets match (no flush-right ring).
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                dayCircle(day)
            }
            if showsCompletionRing {
                completionRing
                    .frame(maxWidth: .infinity)
            }
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

// MARK: - Streak milestones (shared)

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
        WeeklyGoalStrip(workouts: workouts, target: 4)
            .previewEnvironmentObjects()
            .padding()
    }
}
