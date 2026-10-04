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
    /// Any day in the week to draw. The current week everywhere but the recorder's finish panel,
    /// which draws the week the finished workout is filed under.
    var weekOf: Date = .now
    /// Whether today's cell draws its workout's muscle ring instead of the plain accent outline (the
    /// letter stays accent-coloured either way). The goal screen marks today as *today*; the finish
    /// panel marks it as the day that just got its workout — the ring drawing in is the week moving.
    var showsTodaysWorkout: Bool = false
    var style: Style = .rings

    enum Style {
        /// A muscle ring around the letter of each day with a workout — the calendar's own mark.
        case rings
        /// A filled dot under the letter of each day with a workout, its muscle colours pooling into
        /// one another; a rest day is just its letter. Today's dot pops in when it gets its workout.
        case dots
    }

    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let start = weekOf.startOfWeek
        return (0 ..< 7).map { calendar.date(byAdding: .day, value: $0, to: start) ?? start }
    }

    @ViewBuilder
    private func dayCircle(_ day: Date) -> some View {
        switch style {
        case .rings: dayRing(day)
        case .dots: dayDot(day)
        }
    }

    private func centerLabel(_ day: Date) -> String {
        showsDate
            ? "\(calendar.component(.day, from: day))"
            : day.formatted(.dateTime.weekday(.narrow))
    }

    private func dayRing(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: dayWorkouts(on: day))
        let hasWorkout = !occurrences.isEmpty
        let centerLabel = centerLabel(day)
        return ZStack {
            if isToday && !(showsTodaysWorkout && hasWorkout) {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.7)
                    .frame(width: 32, height: 32)
            } else if hasWorkout {
                MuscleOccurrenceRing(occurrences: occurrences, lineWidth: 4)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                    // Today's ring, arriving: it draws itself clockwise from the top, the way the
                    // muscle arcs are laid down, rather than popping or scaling in.
                    .modifier(RingDrawIn(isEnabled: isToday && showsTodaysWorkout))
            }
            Text(centerLabel)
                .font(.system(size: 13, weight: (isToday || hasWorkout) ? .bold : .semibold))
                .foregroundStyle(isToday ? Color.accentColor : (hasWorkout ? Color.primary : Color.secondaryLabel))
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
    }

    private func dayDot(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let workouts = dayWorkouts(on: day)
        let occurrences = muscleGroupService.getMuscleGroupOccurances(in: workouts)
        let hasWorkout = !occurrences.isEmpty
        let pops = isToday && showsTodaysWorkout && !reduceMotion
        return ZStack {
            if hasWorkout {
                MuscleColorDot(occurrences: occurrences)
                    .frame(width: 30, height: 30)
                    .modifier(DotPop(isEnabled: pops, workoutCount: workouts.count, colors: occurrences.map { $0.0.color }))
                    .accessibilityHidden(true)
                    // Today's dot, arriving: it springs up from a speck, past its size and back.
                    .transition(
                        pops
                            ? AnyTransition.scale(scale: 0.1).combined(with: .opacity)
                                .animation(.spring(duration: 0.42, bounce: 0.5))
                            : .identity
                    )
            }
            Text(centerLabel(day))
                .font(.system(size: 13, weight: (isToday || hasWorkout) ? .bold : .semibold))
                // Dark on a dot — every muscle colour is a light pastel — and the accent marks today
                // only while it has no dot to sit on.
                .foregroundStyle(hasWorkout ? Color.black.opacity(0.8) : (isToday ? Color.accentColor : Color.secondaryLabel))
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
        let range = weekOf.startOfWeek ... weekOf.endOfWeek
        return workouts.filter {
            guard !$0.isEmpty, let d = $0.date else { return false }
            return range.contains(d)
        }.count
    }
}

/// Draws a ring in clockwise on appearance — a stroke mask whose trim runs 0 → 1 — for the day that
/// just got its workout. Off everywhere else, where the rings are simply there.
private struct RingDrawIn: ViewModifier {
    let isEnabled: Bool
    @State private var drawn = false

    func body(content: Content) -> some View {
        content
            .mask {
                if isEnabled {
                    Circle()
                        .trim(from: 0, to: drawn ? 1 : 0.001)
                        .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .padding(-2)
                } else {
                    // Outset past the frame: the ring's stroke is centred on the circle's edge, so half
                    // its width lies outside the view, and a frame-sized mask clipped every ring to a
                    // rounded square.
                    Rectangle()
                        .padding(-4)
                }
            }
            .onAppear {
                guard isEnabled else { return }
                withAnimation(.easeOut(duration: 0.6)) { drawn = true }
            }
    }
}

/// A day's dot: filled with the day's muscle colours the way the screens' `ColorfulView` washes are —
/// each colour welling up from its own side and pooling into the next, not a linear blend — with a
/// lighter and a darker shade mixed in, so a one-group day still has depth.
///
/// Soft radial pools over a base rather than a `MeshGradient`: the first mesh drawn in a session
/// stalled the main thread for ~450 ms (measured on the finish panel, where that first draw is the
/// moment the week moves), and at this size the pools read the same.
struct MuscleColorDot: View {
    let occurrences: [(MuscleGroup, Int)]

    /// Where the pools well up: the corners across the diagonals first, so two groups land on
    /// opposite sides rather than side by side, then one just off the middle.
    private static let centers: [UnitPoint] = [
        UnitPoint(x: 0.1, y: 0.1), UnitPoint(x: 0.9, y: 0.9), UnitPoint(x: 0.92, y: 0.12),
        UnitPoint(x: 0.1, y: 0.9), UnitPoint(x: 0.55, y: 0.45),
    ]
    /// Each pool's shade — towards white when positive, towards black when negative.
    private static let shades: [Double] = [0.3, -0.15, 0.05, 0.15, 0.12]

    var body: some View {
        let colors = poolColors
        ZStack {
            colors[0].mix(with: colors[1], by: 0.5)
            ForEach(colors.indices, id: \.self) { index in
                EllipticalGradient(
                    colors: [colors[index], colors[index].opacity(0)],
                    center: Self.centers[index],
                    startRadiusFraction: 0,
                    endRadiusFraction: index == Self.centers.count - 1 ? 0.4 : 0.6
                )
            }
        }
        .clipShape(Circle())
    }

    /// The pools' colours, shared out by the groups' set counts: each pool goes to the group
    /// furthest behind its share, so the bigger group takes more of the dot and none is left out.
    private var poolColors: [Color] {
        guard !occurrences.isEmpty else { return Array(repeating: Color.fill, count: Self.centers.count) }
        let total = Double(max(occurrences.reduce(0) { $0 + $1.1 }, 1))
        var dealt = Array(repeating: 0, count: occurrences.count)
        return Self.centers.indices.map { turn in
            func lag(_ index: Int) -> Double {
                Double(occurrences[index].1) / total * Double(turn + 1) - Double(dealt[index])
            }
            let index = occurrences.indices.max { lag($0) < lag($1) } ?? 0
            dealt[index] += 1
            let base = occurrences[index].0.color
            let shade = Self.shades[turn]
            return shade >= 0 ? base.mix(with: .white, by: shade) : base.mix(with: .black, by: -shade)
        }
    }
}

/// Today's dot, landing with a push: a ripple in its own colours runs out from it as it arrives, and
/// a dot that was already there — a second workout today — punches up once before the ripple.
private struct DotPop: ViewModifier {
    let isEnabled: Bool
    let workoutCount: Int
    let colors: [Color]

    @State private var ripples = 0
    @State private var punches = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: punches) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.22, duration: 0.14, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
            .background {
                if isEnabled {
                    // Leaves the dot as the dot reaches its full size.
                    RippleRing(
                        style: AngularGradient(colors: colors + colors.prefix(1), center: .center),
                        trigger: ripples,
                        delay: 0.1
                    )
                }
            }
            .onAppear {
                guard isEnabled else { return }
                ripples += 1
            }
            .onChange(of: workoutCount) { old, new in
                guard isEnabled, new > old else { return }
                punches += 1
                ripples += 1
            }
    }
}

// MARK: - Weekly goal arc (shared)

/// The weekly goal's gauge: a 240° arc opening at the bottom, wearing `CompletionRing`'s round caps,
/// `.fill` track and accent gradient so the app's progress shapes read as one family. Worn by the
/// goal screen at full size and by the Summary's `WeeklyGoalCountPill` at control size, so the week
/// keeps one silhouette wherever it appears.
///
/// The label is laid over the arc unrotated — only the two circles take the rotation that moves the
/// arc's start to 8 o'clock.
struct WeeklyGoalArc<Label: View>: View {
    /// Completion 0…1; values outside are clamped.
    let progress: Double
    var lineWidth: CGFloat = 14
    /// How the sweep moves when `progress` changes. The finish panel slows it down: there the sweep
    /// *is* the moment, the week moving by one workout.
    var animation: Animation = .snappy
    @ViewBuilder var label: () -> Label

    /// 240° of the circle, which leaves a 120° opening centred on the bottom.
    private static var sweep: CGFloat { 240.0 / 360.0 }

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .trim(from: 0, to: Self.sweep)
                    .stroke(Color.fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: Self.sweep * clampedProgress)
                    .stroke(
                        Color.accentColor.gradient,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .animation(animation, value: clampedProgress)
            }
            // A circle's trim starts at 3 o'clock; 150° puts the arc's start at 8 o'clock, so the
            // sweep runs up over the top and ends at 4 o'clock — symmetric about the vertical.
            .rotationEffect(.degrees(150))
            label()
        }
    }

    /// The empty band under the arc: its ends stop half a radius below the centre, so the bottom
    /// quarter of the square box carries no ink. Call sites subtract this as bottom padding, or
    /// whatever sits underneath floats away from the gauge.
    static func bottomInset(size: CGFloat, lineWidth: CGFloat) -> CGFloat {
        size / 4 - lineWidth / 2
    }
}

extension WeeklyGoalArc where Label == EmptyView {
    /// A bare arc with nothing in its middle.
    init(progress: Double, lineWidth: CGFloat = 14, animation: Animation = .snappy) {
        self.init(progress: progress, lineWidth: lineWidth, animation: animation, label: { EmptyView() })
    }
}

// MARK: - Streak milestones (shared)

/// The weekly-streak milestone ladder — the first week, then a month, quarter, half-year, year, two
/// years. The first week is a milestone too, so a new streak has a goal one week away and the chain on
/// the Workout Goal screen always ends on a flag: the week the streak started.
enum StreakMilestone {
    static let all: [Int] = [1, 4, 12, 26, 52, 104]

    /// The first milestone beyond `current`; once every milestone is passed, keep pulling a year ahead.
    static func next(after current: Int) -> Int {
        all.first(where: { $0 > current }) ?? (current + 52)
    }

    /// A calendar meaning for a milestone ("a full quarter", "a full year"). Empty for off-ladder values.
    ///
    /// The one-week milestone is "your first week" only for someone who has never held a streak
    /// before (`isFirstStreak`). Anyone whose earlier streaks ended has had a first week already, and
    /// for them the flag simply marks one week.
    static func fact(for weeks: Int, isFirstStreak: Bool) -> String {
        switch weeks {
        case 1:
            return NSLocalizedString(isFirstStreak ? "streakFactFirstWeek" : "streakFactOneWeek", comment: "")
        case 4: return NSLocalizedString("streakFactMonth", comment: "")
        case 12: return NSLocalizedString("streakFactQuarter", comment: "")
        case 26: return NSLocalizedString("streakFactHalfYear", comment: "")
        case 52: return NSLocalizedString("streakFactYear", comment: "")
        case 104: return NSLocalizedString("streakFactTwoYears", comment: "")
        default: return ""
        }
    }

    /// The goal to chase: the next milestone by default, so there's always a near goal ahead — unless
    /// beating the previous best comes first, in which case that is the nearer goal.
    ///
    /// Beating, not matching: the goal is `previousBest + 1`, the week the streak becomes the longest
    /// ever — exactly where the chain plants its "New record" mark. Counting down to the tie read
    /// "1 to go" for a week that then passed with no record, and the record landed a week later.
    /// When beating the best coincides with a milestone, the milestone is the goal and the record
    /// shares its row.
    static func target(current: Int, previousBest: Int) -> (value: Int, isBest: Bool) {
        let next = next(after: current)
        let beatsBest = previousBest + 1
        let bestIsNearer = previousBest > 0 && beatsBest > current && beatsBest < next
        return bestIsNearer ? (beatsBest, true) : (next, false)
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
