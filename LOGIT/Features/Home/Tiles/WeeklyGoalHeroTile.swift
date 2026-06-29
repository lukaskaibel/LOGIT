//
//  WeeklyGoalHeroTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The always-on weekly-goal hero at the top of the Summary screen — the fix for the dead Monday: it
/// has something to show even before the first workout of the week. A locale-ordered 7-day check
/// strip (each day done / today / rest from this week's workouts grouped by calendar day), a
/// "N workouts to go" footer, and a flame streak pill counting consecutive met weeks. Carried by the
/// streak so a fresh week still reads as a continuing run. Free.
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
            strip
            HStack {
                Text(footerText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if streak > 0 {
                    streakPill
                }
            }
        }
        .padding(CELL_PADDING)
        .tileStyle()
    }

    // MARK: - Strip

    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 7) {
                    marker(for: day.state)
                    Text(day.letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(day.state == .today ? Color.accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func marker(for state: DayMark.State) -> some View {
        switch state {
        case .done:
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.black)
            }
            .frame(width: 26, height: 26)
        case .today:
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 1.6)
                .frame(width: 26, height: 26)
        case .rest:
            Circle()
                .fill(Color.fill)
                .frame(width: 26, height: 26)
        }
    }

    private var streakPill: some View {
        ProgressIndicatorPill(symbol: "flame.fill", color: .orange) {
            Text(String(format: NSLocalizedString("weeklyStreakWeeks", comment: ""), streak))
                .font(.system(.footnote, design: .rounded, weight: .bold))
        }
    }

    // MARK: - Data

    private struct DayMark: Identifiable {
        enum State { case done, today, rest }
        let id: Int
        let letter: String
        let state: State
    }

    private var currentWeekWorkouts: [Workout] {
        let range = Date.now.startOfWeek ... Date.now.endOfWeek
        return workouts.filter { workout in
            guard !workout.isEmpty, let date = workout.date else { return false }
            return range.contains(date)
        }
    }

    private var days: [DayMark] {
        let calendar = Calendar.current
        let weekStart = Date.now.startOfWeek
        let workoutDays = Set(currentWeekWorkouts.compactMap(\.date).map { calendar.startOfDay(for: $0) })
        return (0 ..< 7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let hasWorkout = workoutDays.contains(calendar.startOfDay(for: day))
            let state: DayMark.State = hasWorkout ? .done : (calendar.isDateInToday(day) ? .today : .rest)
            return DayMark(id: offset, letter: day.formatted(.dateTime.weekday(.narrow)), state: state)
        }
    }

    private var remaining: Int { max(0, target - currentWeekWorkouts.count) }

    private var footerText: String {
        switch remaining {
        case 0: return NSLocalizedString("weeklyGoalReached", comment: "")
        case 1: return NSLocalizedString("weeklyGoalToGoOne", comment: "")
        default: return String(format: NSLocalizedString("weeklyGoalToGoMany", comment: ""), remaining)
        }
    }

    private var streak: Int {
        SummaryViewModel.currentWeeklyStreak(workouts: workouts, target: target)
    }
}

#Preview {
    FetchRequestWrapper(Workout.self) { workouts in
        WeeklyGoalHeroTile(workouts: workouts)
            .previewEnvironmentObjects()
            .padding()
    }
}
