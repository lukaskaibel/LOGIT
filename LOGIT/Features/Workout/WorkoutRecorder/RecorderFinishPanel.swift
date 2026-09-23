//
//  RecorderFinishPanel.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.09.26.
//

import Observation
import SwiftUI


// MARK: - The reveal

/// The finish panel arrives in beats, top to bottom, so each answer lands on its own instead of the
/// whole screen at once: the week, then what moved it, then the rest.
enum FinishRevealPhase: Int, Comparable {
    /// Nothing to show yet — the sheet is still travelling to the floor while the recap is computed.
    case hidden
    /// The goal hero, holding the week as it stood *before* this workout.
    case hero
    /// The week moves: the arc sweeps on, the count rolls up, today's ring draws in.
    case heroFilled
    /// The hero's verdict — "1 workout to go", "Goal reached" — and the celebration if the week was won.
    case heroSettled
    /// The highlights: records, then improvements.
    case achievements
    /// Effort and note, the totals, the exercises.
    case details
    case done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The beat of the highlight rows: one, two, three — close enough to read as one cascade, far
/// enough apart to count.
enum FinishRevealTiming {
    /// The first row's head start after its section is revealed.
    static let rowLead = 0.15
    /// Row to row.
    static let rowStagger = 0.22
    /// A record's number climbs this long after its row has landed.
    static let rollAfterRow = 0.3

    /// When row `index` lands, after the highlights phase.
    static func rowDelay(index: Int) -> Double { rowLead + Double(index) * rowStagger }

    /// How long the whole cascade takes, from the highlights phase to the last row at rest.
    static func total(rowCount: Int) -> Double {
        rowCount == 0 ? 0 : rowDelay(index: rowCount - 1) + rollAfterRow + 0.5
    }
}

/// The finish panel's state: the recap, how far the reveal has got, and the celebration.
///
/// Observable and held by the recorder in plain `@State`, like `RecorderTopSheetModel`: the screen
/// never reads the phase, so a beat of the reveal re-renders the few panel views that show it and
/// never the recorder around them.
@MainActor
@Observable
final class RecorderFinishModel {
    private(set) var recap: WorkoutRecap?
    private(set) var phase: FinishRevealPhase = .hidden
    /// Whether the phases are being played out beat by beat. False when the panel reopens on a
    /// recap it has already shown, or with Reduce Motion — everything then arrives at once.
    private(set) var isStaged = false
    /// The confetti fired this reveal — one small burst per personal record, from its pill, in that
    /// exercise's colour, as its number climbs. Records only: the week's goal has its own small moment
    /// (the arc closing, swelling once, the verdict springing in) and keeps it small, so that the
    /// confetti stays the sign of a number nobody had lifted before.
    private(set) var bursts: [ConfettiBurst] = []
    /// Bumped when this workout wins the week; the arc swells on it.
    private(set) var goalPulseCount = 0

    /// Measured by the hero, kept for the swell's origin.
    @ObservationIgnored var goalArcCenter: CGPoint?
    @ObservationIgnored private var burstCount = 0
    @ObservationIgnored private var hasPlayedCelebrationHaptic = false
    /// What the last reveal was for. Continue, then Finish again on an unchanged workout, shows the
    /// settled panel at once: the show is for the moment something happened, not for every look.
    @ObservationIgnored private var lastRevealedKey: String?

    func reset() {
        recap = nil
        phase = .hidden
        isStaged = false
        bursts = []
        hasPlayedCelebrationHaptic = false
    }

    /// Plays the reveal. Runs inside the panel's `.task`, so Continue cancels it mid-beat.
    ///
    /// The timings are the choreography: the hero comes in holding last week's-worth of progress, the
    /// arc takes the new workout (count rolling, a light tick as it lands), a won week closes before
    /// it says so and fires the celebration, then records land (the celebration, if it was theirs),
    /// then everything else settles in together.
    func reveal(_ recap: WorkoutRecap, target: Int, reduceMotion: Bool) async {
        let key = recap.celebrationKey(target: target)
        let isFresh = key != lastRevealedKey
        lastRevealedKey = key
        let celebrates = isFresh && recap.celebrates(target: target)
        let goalWon = recap.goal(target: target)?.isReachedByThisWorkout == true
        self.recap = recap

        // Seen already, or motion is off: the settled panel, at once. A record still gets its
        // haptic — Reduce Motion is about movement, not about being told.
        guard isFresh, !reduceMotion else {
            isStaged = false
            // One frame at rest first, as below, so the settled panel fades in instead of popping.
            guard await pause(0.05) else { return }
            withAnimation(.easeOut(duration: 0.25)) { phase = .done }
            if celebrates { CelebrationHaptics.shared.play() }
            return
        }
        isStaged = true
        // Let the sections lay out once, invisible, before the first beat: set in the same update as
        // the recap they'd be inserted already revealed, and the hero would pop in on one frame.
        guard await pause(0.05) else { return }

        withAnimation(.smooth(duration: 0.45)) { phase = .hero }
        guard await pause(0.42) else { return }

        withAnimation(.spring(duration: 0.8, bounce: 0.12)) { phase = .heroFilled }
        // A won week waits for its arc to close before saying so.
        guard await pause(goalWon ? 0.62 : 0.45) else { return }

        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { phase = .heroSettled }
        if goalWon { goalPulseCount += 1 }
        guard await pause(goalWon ? 0.45 : 0.22) else { return }

        withAnimation(.spring(duration: 0.55, bounce: 0.15)) { phase = .achievements }
        let cascade = FinishRevealTiming.total(
            rowCount: min(recap.highlights.count, RecorderFinishHighlightsSection.collapsedCount)
        )
        // The records fire their own confetti, each from its pill as its number climbs (see
        // `RecorderFinishHighlightRow`); nothing to fire from here.
        _ = celebrates
        guard await pause(max(cascade, 0.2)) else { return }

        withAnimation(.smooth(duration: 0.5)) { phase = .details }
        guard await pause(0.6) else { return }
        phase = .done
    }

    /// One record's pop: a small burst from its pill in its exercise's colour. The first of a reveal
    /// carries the celebration haptic; the rest each get a tap from their own row, so three records
    /// feel like three and not like one long buzz.
    func celebrateRecord(from origin: CGPoint?, color: Color) {
        burstCount += 1
        bursts.append(ConfettiBurst(id: burstCount, origin: origin, colors: [color, color.mix(with: .white, by: 0.4)], scale: 0.36))
        if !hasPlayedCelebrationHaptic {
            hasPlayedCelebrationHaptic = true
            CelebrationHaptics.shared.play()
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// A section arriving: faded in and risen into place. Reduce Motion keeps the fade, drops the rise.
private struct FinishReveal: ViewModifier {
    let isRevealed: Bool
    var rise: CGFloat = 16
    /// Seconds after the phase turns before this one moves — how the improvements wait for the records.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : rise)
            .animation(delay > 0 ? .spring(duration: 0.55, bounce: 0.15).delay(delay) : nil, value: isRevealed)
            .allowsHitTesting(isRevealed)
    }
}

// MARK: - Content

/// The finish panel's scrolling body, in the order a lifter asks: did this count (the week), what was
/// the best of it (records, then improvements), how did it feel (effort and note), what was it (totals
/// and exercises). Nothing is laid out until the recap exists — the sections' sizes depend on it, and
/// a section popping in above another would shove it down the screen mid-reveal.
struct RecorderFinishPanelContent: View {
    @ObservedObject var workout: Workout
    let model: RecorderFinishModel
    /// The panel's scroll view, so the exercise list can bring itself into view when it unfolds.
    var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        VStack(spacing: SECTION_SPACING) {
            if let recap = model.recap {
                RecorderFinishGoalHero(workout: workout, recap: recap, model: model)
                    .modifier(FinishReveal(isRevealed: model.phase >= .hero))
                RecorderFinishAchievements(recap: recap, model: model)
                RecorderFinishEffortNoteRow(workout: workout)
                    .modifier(FinishReveal(isRevealed: model.phase >= .details))
                RecorderFinishExercisesSection(workout: workout, scrollProxy: scrollProxy)
                    .modifier(FinishReveal(isRevealed: model.phase >= .details, rise: 24))
            }
        }
    }
}

// MARK: - The week

/// The week's goal, moving by this workout: the same 240° arc as the goal screen and the Summary's
/// pill — one mark at three sizes — holding the week as it stood before, then sweeping on by one.
///
/// It leads because it is the one reward every finished workout earns. Records come and go; the week
/// always moves, and "1 workout to go" is the nearest goal there is (people speed up as a goal gets
/// close). Without a goal the week still counts up, with a way to set one.
private struct RecorderFinishGoalHero: View {
    @ObservedObject var workout: Workout
    let recap: WorkoutRecap
    let model: RecorderFinishModel

    @AppStorage("workoutPerWeekTarget") private var target: Int = -1
    @State private var isShowingGoalPicker = false

    /// The week's ring at the size the Summary's pill draws it — one mark, two sizes.
    private static let arcSize: CGFloat = 30
    private static let arcLineWidth: CGFloat = 3.5

    private var isFilled: Bool { model.phase >= .heroFilled }
    private var isSettled: Bool { model.phase >= .heroSettled }

    /// The strip gets this workout the moment the arc does, so its day ring draws in with the sweep.
    private var stripWorkouts: [Workout] {
        isFilled ? recap.weekWorkouts + [workout] : recap.weekWorkouts
    }

    var body: some View {
        VStack(spacing: 0) {
            if let goal = recap.goal(target: target) {
                goalCard(goal)
            } else {
                noGoalCard
            }
        }
        .sheet(isPresented: $isShowingGoalPicker) {
            NavigationStack {
                ChangeWeeklyWorkoutGoalScreen()
            }
        }
    }

    // MARK: With a goal

    /// The week is the hero, not a gauge: the shape the Summary's weekly-goal tile had. The verdict on
    /// the header line, seven day rings with today's drawing in, the week's own ring at pill size with
    /// the count inside at the end of the row. It reads left to right in the order it animates. The
    /// streak isn't repeated here: it lives on the goal screen, and this card is about the week.
    private func goalCard(_ goal: WorkoutRecap.Goal) -> some View {
        let count = isFilled ? goal.countAfter : goal.countBefore
        let isMet = goal.countAfter >= goal.target
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(NSLocalizedString("weeklyGoal", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                Spacer(minLength: 8)
                verdict(goal)
            }

            HStack(spacing: 10) {
                WeeklyGoalStrip(
                    workouts: stripWorkouts,
                    target: goal.target,
                    showsCompletionRing: false,
                    weekOf: recap.workoutDate,
                    showsTodaysWorkout: true
                )
                Rectangle()
                    .fill(Color.fill)
                    .frame(width: 1, height: 22)
                ZStack {
                    WeeklyGoalArc(
                        // A zero week still shows its starting dot, as the Summary's pill does.
                        progress: max(isFilled ? goal.progressAfter : goal.progressBefore, 0.005),
                        lineWidth: Self.arcLineWidth,
                        // Slower than the arc's default: here the sweep *is* the moment.
                        animation: .spring(duration: 0.85, bounce: 0.12)
                    )
                    .frame(width: Self.arcSize, height: Self.arcSize)
                    // The week won: the ring swells once as the verdict springs in.
                    .keyframeAnimator(initialValue: 1.0, trigger: goalPulse) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.18, duration: 0.16, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.7, spring: .bouncy)
                    }
                    .onGeometryChange(for: CGPoint.self) { proxy in
                        let frame = proxy.frame(in: .global)
                        return CGPoint(x: frame.midX, y: frame.midY)
                    } action: { center in
                        model.goalArcCenter = center
                    }
                    Text("\(count)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isMet && isFilled ? Color.accentColor : Color.label)
                        .contentTransition(.numericText(value: Double(count)))
                }
                // Half of the arc's empty bottom band comes back, the Summary pill's own compromise.
                .padding(.bottom, -WeeklyGoalArc<EmptyView>.bottomInset(size: Self.arcSize, lineWidth: Self.arcLineWidth) / 2)
                .frame(width: 34, height: 34)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity)
        .translucentTileStyle()
        // One light tick as the count rolls over — the week moving, felt as well as seen — and the
        // system's own "done" when this workout is the one that wins it.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.9), trigger: count)
        .sensoryFeedback(.success, trigger: isSettled && goal.isReachedByThisWorkout && model.isStaged) { _, won in won }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: NSLocalizedString("weeklyGoalAccessibility", comment: ""), goal.countAfter, goal.target)
                + ". " + verdictText(goal)
        )
        .accessibilityIdentifier("finishGoalHero")
    }

    private var goalPulse: Int { model.goalPulseCount }

    /// "1 workout to go" in grey, "Goal reached" with its check in the accent — the header line's
    /// trailing half, so the card's first line already says how the week stands.
    private func verdict(_ goal: WorkoutRecap.Goal) -> some View {
        let isMet = goal.countAfter >= goal.target
        return HStack(spacing: 5) {
            if isMet {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, options: .speed(0.8), value: isSettled)
            }
            Text(verdictText(goal))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isMet ? Color.accentColor : Color.secondaryLabel)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(isSettled ? 1 : 0)
        .scaleEffect(isSettled ? 1 : 0.94, anchor: .trailing)
    }

    private func verdictText(_ goal: WorkoutRecap.Goal) -> String {
        if goal.countAfter < goal.target {
            return goal.remaining == 1
                ? NSLocalizedString("weeklyGoalToGoOne", comment: "")
                : String(format: NSLocalizedString("weeklyGoalToGoMany", comment: ""), goal.remaining)
        }
        if goal.wasAlreadyMet {
            return goal.beyond == 1
                ? NSLocalizedString("weeklyGoalBeyondOne", comment: "")
                : String(format: NSLocalizedString("weeklyGoalBeyondMany", comment: ""), goal.beyond)
        }
        return NSLocalizedString("weeklyGoalReached", comment: "")
    }

    // MARK: Without a goal

    private var noGoalCard: some View {
        let count = isFilled ? recap.weekCountAfter : recap.weekCountBefore
        return VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(recap.workoutDate.weekDescription)
                        .font(.system(size: 10, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.accentColor)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(count)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.label)
                            .contentTransition(.numericText(value: Double(count)))
                        Text(NSLocalizedString(count == 1 ? "workout" : "workouts", comment: ""))
                            .font(.headline)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.secondaryLabel)
                    }
                }
                // The identifier sits on the count, not on the card: a container's identifier
                // overwrites its children's, and the Set Goal button needs its own.
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("finishGoalHero")
                Spacer(minLength: 8)
                Button {
                    isShowingGoalPicker = true
                } label: {
                    Label(NSLocalizedString("setGoal", comment: ""), systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("finishSetGoalButton")
            }
            WeeklyGoalStrip(
                workouts: stripWorkouts,
                target: 0,
                showsCompletionRing: false,
                weekOf: recap.workoutDate,
                showsTodaysWorkout: true
            )
        }
        .padding(CELL_PADDING + 2)
        .frame(maxWidth: .infinity)
        .translucentTileStyle()
        .sensoryFeedback(.impact(weight: .light, intensity: 0.9), trigger: count)
    }
}

// MARK: - Highlights

/// What the session beat, in one list: the personal records first, then the exercises that beat
/// their recent best — each exercise once, each row saying in which metric. On a session with
/// neither, the exercises trained for the first time say that they now have a best to beat; on one
/// with nothing at all to report, the section stays out of the way rather than announce a zero.
private struct RecorderFinishAchievements: View {
    let recap: WorkoutRecap
    let model: RecorderFinishModel

    var body: some View {
        let isRevealed = model.phase >= .achievements
        if !recap.highlights.isEmpty {
            RecorderFinishHighlightsSection(recap: recap, model: model, isRevealed: isRevealed)
        } else if recap.firstSessionCount > 0 {
            firstSessions
                .modifier(FinishReveal(isRevealed: isRevealed))
        }
    }

    private var firstSessions: some View {
        let count = recap.firstSessionCount
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: "flag.fill")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    count == 1
                        ? NSLocalizedString("finishFirstSessionsOne", comment: "")
                        : String(format: NSLocalizedString("finishFirstSessionsMany", comment: ""), count)
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                Text(NSLocalizedString("finishFirstSessionsDetail", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(Color.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(CELL_PADDING)
        .translucentTileStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("finishFirstSessions")
    }
}

/// The highlights: one tile per exercise, records on top, then the improvements, capped with a
/// "Show more" once the list runs long. Each row lands one after the other; a record's number rolls
/// up from the best it beat and pops its confetti as it does.
struct RecorderFinishHighlightsSection: View {
    let recap: WorkoutRecap
    let model: RecorderFinishModel
    let isRevealed: Bool

    static let collapsedCount = 5
    @State private var showsAll = false

    var body: some View {
        let highlights = recap.highlights
        let shown = showsAll ? highlights : Array(highlights.prefix(Self.collapsedCount))
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        highlights.compactMap { $0.exercise.muscleGroup }
                            .weightedSpectrumGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
                    )
                    .symbolEffect(.bounce, options: .speed(0.9), value: isRevealed)
                Text(NSLocalizedString("highlights", comment: ""))
                    .foregroundStyle(Color.label)
            }
            .font(.title3.weight(.bold))
            .padding(.leading)
            .modifier(FinishReveal(isRevealed: isRevealed))
            // On the header rather than the section: a container's identifier would overwrite the
            // rows' and the Show More button's own.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("finishHighlights")

            // One tile per exercise, not rows on a shared card: each arrives as its own object,
            // one, two, three, rather than a list filling in.
            VStack(spacing: 8) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, highlight in
                    RecorderFinishHighlightRow(
                        highlight: highlight,
                        index: index,
                        isRevealed: isRevealed,
                        model: model
                    )
                }
                if highlights.count > Self.collapsedCount {
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { showsAll.toggle() }
                    } label: {
                        Text(
                            showsAll
                                ? NSLocalizedString("showLess", comment: "")
                                : String(
                                    format: NSLocalizedString("showMoreCount", comment: ""),
                                    highlights.count - Self.collapsedCount
                                )
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Arrives with the last shown row, as plain opacity: gating its hit-testing on
                    // the reveal left it dead to taps.
                    .opacity(isRevealed ? 1 : 0)
                    .animation(
                        model.isStaged ? .easeOut(duration: 0.3).delay(FinishRevealTiming.rowDelay(index: shown.count)) : nil,
                        value: isRevealed
                    )
                    .accessibilityIdentifier("finishHighlightsShowMore")
                    .accessibilityValue(showsAll ? "all" : "capped")
                }
            }
        }
    }
}

/// One highlight: the kind and metric in the exercise's colour above the name — "Weight PR",
/// "Strength improved" — and the pill with the number on the right: the trophy for a record, the
/// arrow for an improvement.
private struct RecorderFinishHighlightRow: View {
    let highlight: WorkoutRecap.Highlight
    let index: Int
    let isRevealed: Bool
    let model: RecorderFinishModel

    private var isStaged: Bool { model.isStaged }

    /// Whether a record's value has rolled up from the best it beat to the new one.
    @State private var hasRolled = false
    /// The number's centre on screen — where a record's confetti leaves from, since that is where
    /// the record is seen being set.
    @State private var valueCenter: CGPoint?

    /// Rows land one, two, three; a record's value rolls once its own row has landed.
    private var rowDelay: Double { FinishRevealTiming.rowDelay(index: index) }
    private var rollDelay: Double { rowDelay + FinishRevealTiming.rollAfterRow }

    var body: some View {
        let color = highlight.exercise.muscleGroup?.color ?? .accentColor
        HStack(spacing: 12) {
            // The mark of what happened, leading and large: a trophy for a record, an arrow for a
            // gain. It carries the exercise's colour, so the row is read at a glance and the number
            // at the other end is left to be just a number.
            Image(systemName: highlight.isRecord ? "trophy.fill" : "arrow.up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                // A fixed slot, so the names line up down the list however wide the symbol is.
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlight.label)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Text(highlight.exercise.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            FinishHighlightValue(
                color: color,
                metric: highlight.metric,
                exercise: highlight.exercise,
                previous: highlight.previous,
                current: highlight.current,
                // Staged, a record arrives on the best it beat and rolls up to the new one.
                showsCurrent: !highlight.isRecord || hasRolled || !isStaged
            )
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { center in
                valueCenter = center
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 12)
        .translucentTileStyle()
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 14)
        .animation(isStaged ? .spring(duration: 0.5, bounce: 0.18).delay(rowDelay) : nil, value: isRevealed)
        // The roll is its own moment, flipped when it comes rather than scheduled with a delayed
        // animation: a numeric transition under `.delay` drops the old digits at once and only
        // holds back the new ones, and the frames showed a blank value for the whole delay.
        .task(id: isRevealed) {
            guard highlight.isRecord, isRevealed, isStaged, !hasRolled else { return }
            try? await Task.sleep(for: .seconds(rollDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { hasRolled = true }
            // The pop leaves the pill as the number climbs — the record, seen being set — in this
            // exercise's colour and no other.
            model.celebrateRecord(from: valueCenter, color: color)
        }
        // Each record's own tap, so three records feel like three.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: hasRolled) { _, rolled in rolled }
        .accessibilityElement(children: .combine)
    }
}

/// The number at the end of a highlight row: the new value, large, in the exercise's colour, with
/// nothing around it — the symbol at the row's other end is the badge.
///
/// Weight, reps, time and distance show the value itself — a number that was on the bar. Strength is
/// an estimate, so it shows the percent it moved instead, the way the set-group cell's badge does; a
/// "125 kg" for a derived figure invites reading it as a lift that happened.
private struct FinishHighlightValue: View {
    let color: Color
    let metric: ExercisePrimaryMetric
    let exercise: Exercise
    let previous: Int
    let current: Int
    /// While false the value still reads as the old one, so flipping it rolls the number up.
    let showsCurrent: Bool

    private var percent: Double {
        guard previous != 0 else { return 0 }
        return (Double(current) - Double(previous)) / abs(Double(previous))
    }

    var body: some View {
        Group {
            if metric == .estimatedOneRepMax {
                Text(min(abs(showsCurrent ? percent : 0), 9.99), format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: showsCurrent ? percent : 0))
            } else {
                // Laid out at the new value's width from the first frame: the old digits roll
                // inside that slot, so the row never changes width mid-roll and the exercise name
                // beside it never has to give way and come back.
                value(current)
                    .hidden()
                    .overlay(alignment: .trailing) {
                        value(showsCurrent ? current : previous)
                            .foregroundStyle(color)
                            .fixedSize()
                            .contentTransition(.numericText(value: Double(showsCurrent ? current : previous)))
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func value(_ base: Int) -> some View {
        let display = personalRecordDisplay(base, metric: metric, exercise: exercise)
        return UnitView(value: display.value, unit: display.unit, configuration: .normal)
            .monospacedDigit()
    }

    private var accessibilityLabel: String {
        if metric == .estimatedOneRepMax {
            return "\(metric.title): " + abs(percent).formatted(.percent.precision(.fractionLength(0)))
        }
        let to = personalRecordDisplay(current, metric: metric, exercise: exercise)
        return "\(metric.title): \(to.value) \(to.unit)"
    }
}

// MARK: - Effort and note

/// The workout's own account of itself — how hard it was, and what to remember — as one row of two
/// tiles, each opening its sheet. Side by side they cost a row instead of two sections, and the note
/// shows as much of itself as fits the row.
private struct RecorderFinishEffortNoteRow: View {
    @ObservedObject var workout: Workout

    @State private var isRatingEffort = false
    @State private var isEditingNote = false

    private var tint: AnyShapeStyle {
        // Top to bottom: the rating's marker is a tall, narrow capsule (see `WorkoutEffortBars`).
        workout.sets.muscleGroupGradientStyle(startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        LeadingHeightPairLayout(spacing: 8) {
            WorkoutEffortTile(score: workout.effortScore, tint: tint, style: .translucent, layout: .compact) {
                isRatingEffort = true
            }
            WorkoutNoteTile(workout: workout) {
                isEditingNote = true
            }
        }
        .workoutEffortRatingSheet(
            isPresented: $isRatingEffort,
            score: Binding(get: { workout.effortScore }, set: { workout.effortScore = $0 }),
            tint: tint,
            muscleGroups: workout.muscleGroups
        )
        .workoutNoteEditorSheet(isPresented: $isEditingNote, workout: workout)
    }
}

/// Two tiles side by side at equal widths, as tall as the first. The second is handed that height to
/// fill — the note takes the effort tile's height and shows as much of itself as fits, instead of
/// growing the row with every line written.
private struct LeadingHeightPairLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        let width = proposal.width ?? first.sizeThatFits(.unspecified).width * 2 + spacing
        let height = first.sizeThatFits(ProposedViewSize(width: columnWidth(width), height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(bounds.width)
        let size = ProposedViewSize(width: column, height: bounds.height)
        for (index, subview) in subviews.prefix(2).enumerated() {
            let x = bounds.minX + CGFloat(index) * (column + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: size)
        }
    }

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        max((width - spacing) / 2, 0)
    }
}

// MARK: - Exercises

/// Everything the session contained, folded: one row saying how much it was — exercises, sets,
/// volume — which unfolds into the exercise rows. The records and the improvements above already say
/// how it went, so the rows carry no badges any more; what they keep is the check before End Workout
/// writes the session: which sets are logged and which will be thrown away. The bar below only says
/// how many, so the count isn't repeated up here.
private struct RecorderFinishExercisesSection: View {
    @ObservedObject var workout: Workout
    var scrollProxy: ScrollViewProxy? = nil

    @State private var isExpanded = false

    private static let scrollID = "finishPanelExercises"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.32)) { isExpanded.toggle() }
                // The tile sits at the bottom of the panel, so the rows would unfold under the pinned
                // bar: bring its header to the top as they open, and the rows come with it. A frame
                // later, once the rows are in the layout — in the same update the content is still
                // its folded height and there is nothing to scroll to yet.
                if isExpanded {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(340))
                        withAnimation(.snappy(duration: 0.4)) {
                            scrollProxy?.scrollTo(Self.scrollID, anchor: .top)
                        }
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("exercises", comment: ""))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.label)
                        summary
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.tertiaryLabel)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("finishExercisesToggle")
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")

            if isExpanded {
                ForEach(workout.setGroups, id: \.objectID) { setGroup in
                    Divider().overlay(Color.fill)
                    row(for: setGroup)
                }
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 2)
        .translucentTileStyle()
        // `.contain`, or the tile's identifier would overwrite the toggle's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.scrollID)
        .id(Self.scrollID)
    }

    /// "8 exercises · 30 SETS · 17595 KG" — the count in words, the sums as units, like the caption.
    private var summary: some View {
        let count = workout.setGroups.count
        return HStack(spacing: 6) {
            Text(
                count == 1
                    ? NSLocalizedString("exercisesCountOne", comment: "")
                    : String(format: NSLocalizedString("exercisesCountMany", comment: ""), count)
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.secondaryLabel)
            ForEach([WorkoutStatMetric.sets, .volume], id: \.id) { metric in
                Text("·").foregroundStyle(Color.tertiaryLabel)
                UnitView(
                    value: metric.formattedValue(fromRaw: metric.rawValue(of: workout)),
                    unit: metric.unit,
                    configuration: .extraSmall,
                    unitColor: .tertiaryLabel
                )
                .foregroundStyle(Color.secondaryLabel)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityIdentifier("finishPanelTotals")
    }

    /// One row per set group: the exercise (both, for a superset), its muscle groups in colour, and
    /// how many of its sets were logged.
    private func row(for setGroup: WorkoutSetGroup) -> some View {
        let exercises = [setGroup.exercise, setGroup.secondaryExercise].compactMap { $0 }
        let logged = setGroup.sets.filter { $0.hasEntry }.count
        let total = setGroup.sets.count
        let muscleGroups = exercises.compactMap { $0.muscleGroup }
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercises.map { $0.displayName }.joined(separator: " + "))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(
                    Set(muscleGroups)
                        .sorted { $0.rawValue < $1.rawValue }
                        .map { $0.description }
                        .joined(separator: " · ")
                )
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(muscleGroups.weightedSpectrumGradientStyle())
            }
            Spacer(minLength: 0)
            // "3 / 4 sets" only when something is missing; a complete group just says "4 sets".
            Text(
                (logged < total ? "\(logged) / \(total)" : "\(total)")
                    + " " + NSLocalizedString("sets", comment: "").lowercased()
            )
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(logged < total ? Color.secondaryLabel : Color.label)
            .fixedSize()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Celebration

/// The confetti, over the whole recorder — the panel clips to its own edge, and a burst has to be free
/// to fall through everything below its pill. Observes only the bursts, so one re-renders nothing else.
struct RecorderCelebrationOverlay: View {
    let model: RecorderFinishModel

    var body: some View {
        CelebrationConfetti(bursts: model.bursts)
    }
}
