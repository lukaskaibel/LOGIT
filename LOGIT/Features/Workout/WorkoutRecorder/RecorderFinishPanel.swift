//
//  RecorderFinishPanel.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.09.26.
//

import ColorfulX
import Observation
import SwiftUI


// MARK: - The reveal

/// The finish panel arrives in one movement: every section at once, top to bottom, the records still
/// plain rows on the best they beat and the week as it stood before. Then only the numbers move —
/// the week takes this workout, and each record counts up to its new best and becomes a record as it
/// lands. Nothing is held back for a beat of its own; a reveal that makes you watch it stops being a
/// reward.
enum FinishRevealPhase: Int, Comparable {
    /// Nothing to show yet — the sheet is still travelling to the floor while the recap is computed.
    case hidden
    /// Everything on screen, the goal hero holding the week as it stood *before* this workout.
    case hero
    /// The week moves: today's dot pops in, the arc sweeps on, the count punches up.
    case heroFilled
    /// The hero's verdict — "1 workout to go", "Goal reached" — and the swell if the week was won.
    case heroSettled
    case done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a record's number climbs from the best it beat to the new one: an odometer through round
/// steps, quick at first and slowing into the new best.
enum RecordCount {
    /// The values the number passes through: round steps in the unit on screen — whole kilos,
    /// quarter kilos for a small gain, single reps — so every frame of the count shows a number
    /// someone could have lifted, never "101.234 kg". Raw stored values, first the previous best,
    /// last the new one; at most 14 in all.
    static func values(from previous: Int, to current: Int, metric: ExercisePrimaryMetric, exercise: Exercise) -> [Int] {
        guard current > previous else { return [current] }
        let toDisplay: (Int) -> Double
        let toRaw: (Double) -> Int
        let niceSteps: [Double]
        switch metric {
        case .weight, .estimatedOneRepMax:
            toDisplay = { convertWeightForDisplayingDecimal($0) }
            toRaw = { Int(convertWeightForStoring($0)) }
            niceSteps = [0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100]
        case .repetitions:
            toDisplay = { Double($0) }
            toRaw = { Int($0.rounded()) }
            niceSteps = [1, 2, 5, 10, 25, 50, 100]
        case .duration:
            toDisplay = { Double($0) / 1000 }
            toRaw = { Int(($0 * 1000).rounded()) }
            niceSteps = [0.01, 0.05, 0.1, 0.25, 0.5, 1, 5, 10, 15, 30, 60, 300, 600]
        case .distance:
            let style = exercise.distanceStyle
            toDisplay = { convertDistanceForDisplayingDecimal(Int64($0), style: style) }
            toRaw = { Int(convertDistanceForStoring($0, style: style)) }
            niceSteps = [0.01, 0.05, 0.1, 0.25, 0.5, 1, 5, 10, 50, 100, 500, 1000]
        }
        let from = toDisplay(previous)
        let to = toDisplay(current)
        // The finest round step that still gets there in eight: 100 → 105 kg climbs in whole
        // kilos, not in halves — few enough that each one can be read as it rolls past.
        let step = niceSteps.first { (to - from) / $0 <= 8 } ?? niceSteps.last!
        var values = [previous]
        var multiple = (from / step).rounded(.down) + 1
        while multiple * step < to - step * 0.001 {
            values.append(toRaw(multiple * step))
            multiple += 1
        }
        values.append(current)
        // A gain beyond even the coarsest step: keep evenly spaced ones, ends included.
        if values.count > 14 {
            let last = values.count - 1
            values = (0 ..< 14).map { values[Int((Double($0) / 13 * Double(last)).rounded())] }
        }
        return values
    }

    /// How long the climb takes, start to new best: about a second — long enough to watch the
    /// number move, short enough that the old one doesn't linger. A climb of a step or two is
    /// quicker: one rep more shouldn't sit on the old number for a second before it moves.
    static func duration(steps: Int) -> Double {
        min(0.9, 0.3 + 0.25 * Double(steps))
    }

    /// When step `step` of `steps` shows, from the start of the climb: an ease-out, so the steps
    /// come quickly and slow into the new best — on a 1.5 power, not a square, with which the last
    /// step sat for 0.4 s and read as the count stalling.
    static func time(ofStep step: Int, of steps: Int) -> Double {
        let fraction = Double(step) / Double(max(steps, 1))
        return duration(steps: steps) * (1 - pow(1 - fraction, 1 / 1.5))
    }
}

/// The beat of the reveal: the rows land a hair apart, so the list arrives as one movement top to
/// bottom; the records then take their turns counting, a beat apart.
enum FinishRevealTiming {
    /// The first row's head start after the reveal.
    static let rowLead = 0.06
    /// Row to row.
    static let rowStagger = 0.035

    /// When row `index` lands, after the reveal.
    static func rowDelay(index: Int) -> Double { rowLead + Double(index) * rowStagger }

    /// When record `index` starts counting up, after the reveal: with the week moving, so the old
    /// best is up for less than half a second, and each record a beat after the one above.
    static func countStart(index: Int) -> Double { 0.45 + Double(index) * 0.15 }
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
    /// The confetti fired this reveal — one burst per personal record, from its number, in that
    /// exercise's colour, as the number climbs. Records only: the week's goal has its own small moment
    /// (the arc closing, swelling once, the verdict springing in) and keeps it small, so that the
    /// confetti stays the sign of a number nobody had lifted before.
    private(set) var bursts: [ConfettiBurst] = []
    /// Bumped when this workout wins the week; the arc swells on it.
    private(set) var goalPulseCount = 0
    /// The records whose number has rolled up from the best it beat, this reveal. Kept here, not on
    /// the rows: a row folded away by Show less is a new view when Show more brings it back, and
    /// with its own state it forgot the roll and played it again — confetti, haptic and all. A
    /// record rolls once per reveal, whatever the rows do after.
    private(set) var rolledRecordIDs: Set<WorkoutRecap.Highlight.ID> = []

    /// Measured by the hero, kept for the swell's origin.
    @ObservationIgnored var goalArcCenter: CGPoint?
    @ObservationIgnored private var burstCount = 0
    @ObservationIgnored private var hasPlayedCelebrationHaptic = false
    /// What the last reveal was for. Continue, then Finish again on an unchanged workout, shows the
    /// settled panel at once: the show is for the moment something happened, not for every look.
    @ObservationIgnored private var lastRevealedKey: String?

    /// Whether the sections are on screen — all of them from the first beat; only the week's and the
    /// records' own moments are still to come.
    var isOnScreen: Bool { phase >= .hero }

    func reset() {
        recap = nil
        phase = .hidden
        isStaged = false
        bursts = []
        rolledRecordIDs = []
        hasPlayedCelebrationHaptic = false
    }

    /// Plays the reveal. Runs inside the panel's `.task`, so Continue cancels it mid-beat.
    ///
    /// The timings are the choreography: the whole panel comes in, holding the week as it was; 0.3 s
    /// later the week takes the new workout — today's dot pops, the arc sweeps, the count punches up
    /// with a tick — and a won week says so (and swells) once its arc has closed. The records count
    /// up on their own clock meanwhile (see `RecorderFinishHighlightRow`), each landing with its
    /// confetti.
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

        withAnimation(.spring(duration: 0.45, bounce: 0.12)) { phase = .hero }
        guard await pause(0.3) else { return }

        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { phase = .heroFilled }
        // A won week waits for its arc to close before saying so; any other verdict comes at once.
        guard await pause(goalWon ? 0.25 : 0.1) else { return }

        withAnimation(.spring(duration: 0.35, bounce: 0.35)) { phase = .heroSettled }
        if goalWon { goalPulseCount += 1 }
        guard await pause(0.8) else { return }
        phase = .done
    }

    /// Marks a record's number as rolled. True the first time only — the caller pops the confetti
    /// on it — so a row that comes back finds its record already settled and stays still.
    func markRecordRolled(_ id: WorkoutRecap.Highlight.ID) -> Bool {
        rolledRecordIDs.insert(id).inserted
    }

    /// One record's pop: a small fountain out of its number in its exercise's colour. The first of
    /// a reveal carries the celebration haptic; the rest each get a tap from their own row, so three
    /// records feel like three and not like one long buzz.
    func celebrateRecord(from origin: CGRect?, color: Color) {
        burstCount += 1
        bursts.append(ConfettiBurst(id: burstCount, origin: origin, colors: [color, color.mix(with: .white, by: 0.4)]))
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
    /// Seconds after the phase turns before this one moves — how the lower sections follow the rows.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : rise)
            .animation(delay > 0 ? .spring(duration: 0.4, bounce: 0.2).delay(delay) : nil, value: isRevealed)
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
                    .modifier(FinishReveal(isRevealed: model.isOnScreen))
                RecorderFinishAchievements(recap: recap, model: model)
                // These come in with everything else, a step behind the rows above them, so the panel
                // fills top to bottom in one movement.
                RecorderFinishEffortNoteRow(workout: workout)
                    .modifier(FinishReveal(isRevealed: model.isOnScreen, delay: model.isStaged ? 0.14 : 0))
                RecorderFinishExercisesSection(workout: workout, scrollProxy: scrollProxy)
                    .modifier(FinishReveal(isRevealed: model.isOnScreen, rise: 24, delay: model.isStaged ? 0.18 : 0))
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

    /// The strip gets this workout the moment the arc does, so its day's dot pops in with the sweep.
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
    /// the header line, seven days with today's dot popping in, the week's own ring at pill size with
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
                    showsTodaysWorkout: true,
                    style: .dots
                )
                Rectangle()
                    .fill(Color.fill)
                    .frame(width: 1, height: 22)
                ZStack {
                    WeeklyGoalArc(
                        // A zero week still shows its starting dot, as the Summary's pill does.
                        progress: max(isFilled ? goal.progressAfter : goal.progressBefore, 0.005),
                        lineWidth: Self.arcLineWidth,
                        // Quick, with a little overshoot: the sweep is a push, not a crawl.
                        animation: .spring(duration: 0.5, bounce: 0.3)
                    )
                    .frame(width: Self.arcSize, height: Self.arcSize)
                    // Every workout: the ring swells a little as it takes it.
                    .keyframeAnimator(initialValue: 1.0, trigger: punch) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.14, duration: 0.14, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    }
                    // The week won: it swells again, harder, as the verdict springs in, and a ring of
                    // the accent runs out from it.
                    .keyframeAnimator(initialValue: 1.0, trigger: goalPulse) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.3, duration: 0.14, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.55, spring: .bouncy)
                    }
                    .background {
                        RippleRing(style: Color.accentColor, trigger: goalPulse, lineWidth: 2, reach: 2.3)
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
                        // The count lands with a punch: it jumps past the arc and drops back in.
                        .keyframeAnimator(initialValue: 1.0, trigger: punch) { content, scale in
                            content.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(1.55, duration: 0.15, spring: .snappy)
                            SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                        }
                }
                // Half of the arc's empty bottom band comes back, the Summary pill's own compromise.
                .padding(.bottom, -WeeklyGoalArc<EmptyView>.bottomInset(size: Self.arcSize, lineWidth: Self.arcLineWidth) / 2)
                .frame(width: 34, height: 34)
            }
        }
        .padding(CELL_PADDING)
        .frame(maxWidth: .infinity)
        .translucentTileStyle()
        // A firm tick as the count punches up — the week moving, felt as well as seen — and the
        // system's own "done" when this workout is the one that wins it.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.85), trigger: count)
        .sensoryFeedback(.success, trigger: isSettled && goal.isReachedByThisWorkout && model.isStaged) { _, won in won }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: NSLocalizedString("weeklyGoalAccessibility", comment: ""), goal.countAfter, goal.target)
                + ". " + verdictText(goal)
        )
        .accessibilityIdentifier("finishGoalHero")
    }

    private var goalPulse: Int { model.goalPulseCount }
    /// Flips when the week takes this workout, staged only: a settled panel arrives at rest.
    private var punch: Bool { isFilled && model.isStaged }

    /// "1 workout to go" in grey, "Goal reached" with its check in the accent — the header line's
    /// trailing half, so the card's first line already says how the week stands.
    private func verdict(_ goal: WorkoutRecap.Goal) -> some View {
        let isMet = goal.countAfter >= goal.target
        return HStack(spacing: 5) {
            if isMet {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, options: .speed(1.2), value: isSettled)
            }
            Text(verdictText(goal))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isMet ? Color.accentColor : Color.secondaryLabel)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(isSettled ? 1 : 0)
        .scaleEffect(isSettled ? 1 : 0.86, anchor: .trailing)
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
                            .keyframeAnimator(initialValue: 1.0, trigger: punch) { content, scale in
                                content.scaleEffect(scale, anchor: .bottom)
                            } keyframes: { _ in
                                SpringKeyframe(1.25, duration: 0.15, spring: .snappy)
                                SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                            }
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
                showsTodaysWorkout: true,
                style: .dots
            )
        }
        .padding(CELL_PADDING + 2)
        .frame(maxWidth: .infinity)
        .translucentTileStyle()
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.85), trigger: count)
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
        let isRevealed = model.isOnScreen
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
/// up from the best it beat and pops its confetti as it does — once. The rows Show more brings in
/// arrive settled, however often it is toggled.
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
            Text(NSLocalizedString("highlights", comment: ""))
                .foregroundStyle(Color.label)
                .font(.title3.weight(.bold))
                .padding(.leading)
                .modifier(FinishReveal(isRevealed: isRevealed, delay: model.isStaged ? 0.04 : 0))
                // On the header rather than the section: a container's identifier would overwrite
                // the rows' and the Show More button's own.
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
                    // What VoiceOver reads after the label — and what the UI tests check.
                    .accessibilityValue(
                        showsAll
                            ? NSLocalizedString("finishHighlightsAllShownValue", comment: "")
                            : String(
                                format: NSLocalizedString("finishHighlightsSomeShownValue", comment: ""),
                                shown.count,
                                highlights.count
                            )
                    )
                }
            }
        }
    }
}

/// One highlight: the kind and metric in the exercise's colour above the name — "Weight PR",
/// "Strength improved" — and the number on the right: the trophy for a record, the arrow for an
/// improvement.
///
/// A record arrives as a plain row — grey trophy outline, "Weight", the best it beat in grey, no
/// wash — and only becomes a record when its number reaches the new best: so the old value is never
/// dressed up as the record it isn't.
private struct RecorderFinishHighlightRow: View {
    let highlight: WorkoutRecap.Highlight
    let index: Int
    let isRevealed: Bool
    let model: RecorderFinishModel

    private var isStaged: Bool { model.isStaged }

    /// Whether a record's value has rolled up from the best it beat to the new one — on the model,
    /// not in this row's state, so it survives the row being folded away and back.
    private var hasRolled: Bool { model.rolledRecordIDs.contains(highlight.id) }
    /// Whether this row is one of the reveal's cascade. The rows past the cap only ever arrive by
    /// Show more, after the show — they come in settled: no roll, no confetti, no tap. The pop is
    /// for a record being set, and by then it has been.
    private var isInCascade: Bool { index < RecorderFinishHighlightsSection.collapsedCount }
    /// Whether the row shows its record (or is an improvement, which has nothing to wait for).
    private var isSet: Bool { !highlight.isRecord || hasRolled || !isStaged || !isInCascade }
    /// The number's frame on screen — what a record's confetti leaves, since that is where the
    /// record is seen being set.
    @State private var valueFrame: CGRect?
    /// How far a record's count has got: an index into its steps.
    @State private var step = 0

    /// The rows land a hair apart, top to bottom.
    private var rowDelay: Double { FinishRevealTiming.rowDelay(index: index) }

    var body: some View {
        let color = highlight.exercise.muscleGroup?.color ?? .accentColor
        let steps = highlight.isRecord
            ? RecordCount.values(
                from: highlight.previous, to: highlight.current, metric: highlight.metric, exercise: highlight.exercise
            )
            : [highlight.current]
        HStack(spacing: 12) {
            // The mark of what happened, leading and large: a trophy for a record, an arrow for a
            // gain. It carries the exercise's colour, so the row is read at a glance and the number
            // at the other end is left to be just a number. A record still on its way shows the
            // trophy's outline in grey, and fills it as it lands.
            Image(systemName: highlight.isRecord ? (isSet ? "trophy.fill" : "trophy") : "arrow.up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isSet ? color : Color.tertiaryLabel)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isSet)
                // A fixed slot, so the names line up down the list however wide the symbol is.
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(isSet ? highlight.label : highlight.metric.title)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(isSet ? color : Color.secondaryLabel)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
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
                steps: steps,
                step: step,
                isSet: isSet
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                valueFrame = frame
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 12)
        .translucentTileStyle()
        // A record glows faintly in its exercise's colour — the screen's own muscle wash, in one
        // hue, so it pools in soft patches rather than lying flat. An improvement stays plain: the
        // records are the bigger news and should read that way before a word is read. The wash
        // comes with the record: it fades in as the number lands.
        .background {
            if highlight.isRecord {
                RecordTileGlow(color: color)
                    .opacity(isSet ? 1 : 0)
            }
        }
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 12)
        .scaleEffect(isRevealed ? 1 : 0.94)
        .animation(isStaged ? .spring(duration: 0.4, bounce: 0.25).delay(rowDelay) : nil, value: isRevealed)
        // The roll is its own moment, flipped when it comes rather than scheduled with a delayed
        // animation: a numeric transition under `.delay` drops the old digits at once and only
        // holds back the new ones, and the frames showed a blank value for the whole delay.
        .task(id: isRevealed) {
            guard highlight.isRecord, isRevealed, isStaged, isInCascade, !hasRolled else { return }
            try? await Task.sleep(for: .seconds(FinishRevealTiming.countStart(index: index)))
            guard !Task.isCancelled else { return }
            await countUp(through: steps)
            guard !Task.isCancelled else { return }
            let rolls = withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                model.markRecordRolled(highlight.id)
            }
            guard rolls else { return }
            // The pop leaves the number as it climbs — the record, seen being set — in this
            // exercise's colour and no other — once the number has sprung forward, so it is seen
            // leaving it.
            try? await Task.sleep(for: .milliseconds(100))
            model.celebrateRecord(from: valueFrame, color: color)
        }
        // Each record's own tap, so three records feel like three. On the change only: a row that
        // comes back already rolled stays quiet.
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: hasRolled) { _, rolled in rolled }
        .accessibilityElement(children: .combine)
    }

    /// Rolls the number up through `steps` on the count's curve, short of the last one: that is the
    /// record itself, which the caller sets.
    private func countUp(through steps: [Int]) async {
        let last = steps.count - 1
        guard last > 0 else { return }
        let start = ContinuousClock.now
        for index in 1 ..< last {
            try? await Task.sleep(until: start + .seconds(RecordCount.time(ofStep: index, of: last)), clock: .continuous)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.16)) { step = index }
        }
        try? await Task.sleep(until: start + .seconds(RecordCount.duration(steps: last)), clock: .continuous)
    }
}

/// The wash behind a record's tile: the same drifting-blob gradient as the screen's background,
/// fed one colour at a few depths with dark gaps between, so it lands as soft patches of the
/// exercise's colour rather than a flat fill. Still, and faint — a tint, not a card colour.
private struct RecordTileGlow: View {
    let color: Color

    var body: some View {
        ColorfulView(
            color: [color, .black, color.mix(with: .white, by: 0.25), .black, color.mix(with: .black, by: 0.3)],
            speed: .constant(0)
        )
        .opacity(0.32)
        .clipShape(.rect(cornerRadius: 30))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The number at the end of a highlight row: the new value, large, in the exercise's colour, with
/// nothing around it — the symbol at the row's other end is the badge.
///
/// Weight, reps, time and distance show the value itself — a number that was on the bar. Strength is
/// an estimate, so it shows the percent it moved instead, the way the set-group cell's badge does; a
/// "125 kg" for a derived figure invites reading it as a lift that happened.
///
/// A record counts up to it: grey on the best it beat, rolling through round steps, coloured as it
/// lands.
private struct FinishHighlightValue: View {
    let color: Color
    let metric: ExercisePrimaryMetric
    let exercise: Exercise
    let previous: Int
    let current: Int
    /// The values the count passes through, from the previous best to the new one.
    let steps: [Int]
    /// The step the count has reached.
    let step: Int
    /// Whether the record has landed: the new value, in colour, springing forward on the change.
    let isSet: Bool

    private var shown: Int {
        if isSet || steps.isEmpty { return current }
        return steps[min(max(step, 0), steps.count - 1)]
    }

    /// Grey before the record, the exercise's colour once it is set.
    private var tint: Color { isSet ? color : Color.secondaryLabel }

    private var percent: Double {
        guard previous != 0 else { return 0 }
        return (Double(current) - Double(previous)) / abs(Double(previous))
    }

    var body: some View {
        Group {
            if metric == .estimatedOneRepMax {
                Text(min(abs(isSet ? percent : 0), 9.99), format: .percent.precision(.fractionLength(0)))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: isSet ? percent : 0))
            } else {
                // Laid out at the new value's width from the first frame: the old digits roll
                // inside that slot, so the row never changes width mid-roll and the exercise name
                // beside it never has to give way and come back.
                value(current)
                    .hidden()
                    .overlay(alignment: .trailing) {
                        value(shown)
                            .foregroundStyle(tint)
                            .fixedSize()
                            .contentTransition(.numericText(value: Double(shown)))
                    }
            }
        }
        // The record, set: as it lands on the new best the number springs forward — a touch bigger,
        // lifted, lit in its colour — holds there a beat while the celebration leaves it, and sinks
        // back into the row.
        .keyframeAnimator(initialValue: Lift(), trigger: isSet) { content, lift in
            content
                .shadow(color: color.opacity(0.75 * lift.glow), radius: 9 * lift.glow)
                .scaleEffect(lift.scale)
                .offset(y: lift.rise)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.14, duration: 0.14, spring: .snappy)
                LinearKeyframe(1.14, duration: 0.2)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            }
            KeyframeTrack(\.rise) {
                SpringKeyframe(-3, duration: 0.14, spring: .snappy)
                LinearKeyframe(-3, duration: 0.2)
                SpringKeyframe(0, duration: 0.45, spring: .smooth)
            }
            KeyframeTrack(\.glow) {
                LinearKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: 0.22)
                LinearKeyframe(0, duration: 0.45)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private struct Lift {
        var scale: CGFloat = 1
        var rise: CGFloat = 0
        var glow: Double = 0
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
            .accessibilityValue(
                NSLocalizedString(isExpanded ? "accessibilityExpanded" : "accessibilityCollapsed", comment: "")
            )

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
    ///
    /// The sums are of the logged sets only: the bar below says the rest won't be saved, and a total
    /// counting them would describe a workout End Workout isn't going to write. Summed here rather
    /// than through `WorkoutStatMetric.rawValue(of:)`, which reads saved workouts, where every set
    /// is a logged one.
    private var summary: some View {
        let count = workout.setGroups.count
        let loggedSets = workout.sets.filter { $0.hasEntry }
        func raw(_ metric: WorkoutStatMetric) -> Int {
            metric == .sets ? loggedSets.count : getVolume(of: loggedSets)
        }
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
                    value: metric.formattedValue(fromRaw: raw(metric)),
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
            // "3 / 4 sets" only when something is missing; a complete group just says "4 sets" —
            // or "1 set". Whole phrases per locale, not a count glued to the "Sets" title
            // lowercased: that read "1 sets", and German nouns keep their capital ("4 Sätze").
            Text(
                logged < total
                    ? String(format: NSLocalizedString("setsLoggedOfTotal", comment: ""), logged, total)
                    : total == 1
                        ? NSLocalizedString("setsCountOne", comment: "")
                        : String(format: NSLocalizedString("setsCountMany", comment: ""), total)
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
/// to fly out over everything around its number. Observes only the bursts, so one re-renders nothing else.
struct RecorderCelebrationOverlay: View {
    let model: RecorderFinishModel

    var body: some View {
        CelebrationConfetti(bursts: model.bursts)
    }
}
