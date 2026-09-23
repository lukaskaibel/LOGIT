//
//  RecorderTopSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 13.09.26.
//

import Observation
import SwiftUI

/// Room between the sheet's bottom edge and the first set group resting under it. The list's fade
/// band is centred on that edge, so this is also what keeps a resting row fully legible.
let RECORDER_SHEET_LIST_GAP: CGFloat = 20

/// Everything below the compact row that is part of the sheet even when it is closed: the grab
/// handle (12pt of air above a 5pt capsule) and the 10pt under it.
let RECORDER_SHEET_CLOSED_CHROME: CGFloat = 27

// MARK: - Model

/// The recorder's top sheet: the compact workout row with a panel hanging from it that opens to
/// four stops — closed, the actions, the summary above them, and the whole screen for finishing.
///
/// **The sheet floats over the set list; it is not part of its layout.** The previous header sat in
/// flow above the list, so its height set the scroll viewport, the viewport set the maximum scroll
/// offset, and the offset set the height again. Every glitch came out of that loop: a one-exercise
/// workout could only ever fold half its panel, the list needed padding that tracked the fold, and
/// every scroll frame re-rendered the whole recorder. Here the list's viewport never changes and
/// the sheet reads one number.
///
/// **One number.** `reveal` is how far the panel hangs below the compact row, in points. Only the
/// small views that draw the panel, the title and the list's fade observe it, so a fold never
/// invalidates the recorder screen itself.
@Observable
final class RecorderTopSheetModel {
    // MARK: Measured geometry

    /// The sheet's height with the panel closed: the compact row plus its handle chrome.
    var closedHeight: CGFloat = 0
    /// The actions row with the air above it — the first stop.
    var actionsHeight: CGFloat = 0
    /// The recording panel's natural height: the summary and the actions — the second stop.
    var panelHeight: CGFloat = 0
    /// The height the sheet can grow into, from the top of the recorder to the bottom safe area.
    var containerHeight: CGFloat = 0

    // MARK: State

    /// How far the panel hangs below the compact row.
    var reveal: CGFloat = 0
    /// Finishing is the fourth stop: the panel takes the screen and shows the finish content.
    var isFinishing = false
    /// A finger is on the sheet. The scroll leaves the reveal alone while it is.
    var isDragging = false
    /// Keeps the recording panel in the tree while a close animates, so it is clipped away by the
    /// travelling edge instead of vanishing the instant the target becomes zero.
    var isClosing = false
    /// Set for the Continue animation, so the recording panel fades back in behind the finish
    /// content rather than popping into place on top of it.
    var isReturningFromFinish = false

    @ObservationIgnored private(set) var scrollOffset: CGFloat = 0
    @ObservationIgnored private var hasBootstrapped = false
    /// Where the reveal stood when Finish was tapped — Continue goes back there.
    @ObservationIgnored var revealBeforeFinishing: CGFloat = 0
    /// Captured when a drag on the sheet begins.
    @ObservationIgnored var dragStart: DragStart?

    struct DragStart {
        let reveal: CGFloat
        let scrollOffset: CGFloat
        /// Nothing was left to open — only then may a long pull hand over to the dismissal.
        let wasFullyOpen: Bool
    }

    // MARK: Derived

    /// The reveal that shows the actions and nothing above them.
    var compactStop: CGFloat {
        guard actionsHeight > 0 else { return panelHeight }
        guard panelHeight > 0 else { return actionsHeight }
        return min(actionsHeight, panelHeight)
    }

    /// The reveal that runs the sheet to the bottom of the screen.
    var fullReveal: CGFloat {
        max(containerHeight - closedHeight, 0)
    }

    /// The largest reveal a drag rests at while recording.
    var openStop: CGFloat {
        max(panelHeight, compactStop)
    }

    /// Every reveal a released drag can come to rest at, ascending.
    var stops: [CGFloat] {
        let compact = compactStop
        guard compact > 0 else { return [0] }
        return panelHeight > compact + 1 ? [0, compact, panelHeight] : [0, compact]
    }

    /// 0 closed … 1 once the actions are out. The title's growth and the panel's fade ride this:
    /// by the time the actions are out the header has arrived.
    var primaryRevealFraction: CGFloat {
        if isFinishing { return 1 }
        guard compactStop > 0 else { return 1 }
        return min(max(reveal / compactStop, 0), 1)
    }

    /// A tolerance, not an equality: a panel that looks open must never swallow its own taps.
    var panelIsInteractive: Bool {
        isFinishing || (compactStop > 0 && reveal >= compactStop * 0.9)
    }

    /// Whether the summary above the actions has come out from behind the edge. Rows still parked
    /// above it are laid out over the compact row, so they have to stand down, not merely be clipped.
    var summaryIsRevealed: Bool {
        reveal > compactStop + 1
    }

    /// Whether opening or closing the sheet should move the list as well: in the large-title zone at
    /// the top of the list, the actions stop still belongs to the rows. Closing counts only a list
    /// that has not yet scrolled past the stop; opening also counts one resting exactly at it —
    /// where the rows sit right under the closed sheet and would otherwise be covered.
    func movesList(whenSettlingTo target: CGFloat) -> Bool {
        guard compactStop > 0 else { return false }
        return target <= 0.5 ? scrollOffset < compactStop - 1 : scrollOffset <= compactStop + 1
    }

    /// Where a release lands: the next stop in the direction of a fling, otherwise the nearest.
    func stop(nearestTo reveal: CGFloat, velocity: CGFloat) -> CGFloat {
        let stops = stops
        let nearest = stops.min(by: { abs($0 - reveal) < abs($1 - reveal) }) ?? 0
        if velocity > 400 { return stops.first(where: { $0 > reveal + 1 }) ?? stops.last ?? nearest }
        if velocity < -400 { return stops.last(where: { $0 < reveal - 1 }) ?? stops.first ?? nearest }
        return nearest
    }

    // MARK: Scrolling

    /// Folds and unfolds the sheet from the list's scroll.
    ///
    /// - Scrolling down folds by exactly the distance scrolled, wherever the list is. Nothing ever
    ///   *opens* on a downward scroll — that is what made the old header expand and contract again.
    /// - Scrolling up only raises the sheet to the large-title floor: the actions stop minus the
    ///   offset. Deep in the list a small scroll up therefore brings nothing back; near the top the
    ///   actions return in lock-step with the rows.
    /// - Offsets are clamped at zero first, so the rubber band at the top of the list — which pulls
    ///   the offset negative and then springs it back — counts as no scroll at all.
    func scrollDidChange(to rawOffset: CGFloat, isFrozen: Bool) {
        let offset = max(rawOffset, 0)
        let delta = offset - scrollOffset
        scrollOffset = offset
        guard hasBootstrapped, !isFrozen, !isDragging, delta != 0 else { return }
        let current = reveal
        let next = delta > 0
            ? max(current - delta, 0)
            : max(current, largeTitleFloor(at: offset))
        if next != current { reveal = next }
    }

    private func largeTitleFloor(at offset: CGFloat) -> CGFloat {
        let compact = compactStop
        return min(max(compact - offset, 0), compact)
    }

    // MARK: Measurement

    func actionsDidMeasure(_ height: CGFloat) {
        guard height > 0, abs(height - actionsHeight) > 0.5 else { return }
        let restingStop = restingStopIndex
        actionsHeight = height
        bootstrapIfNeeded()
        keepResting(at: restingStop)
    }

    func panelDidMeasure(_ height: CGFloat) {
        guard height > 0, abs(height - panelHeight) > 0.5 else { return }
        let restingStop = restingStopIndex
        panelHeight = height
        bootstrapIfNeeded()
        keepResting(at: restingStop)
    }

    /// Which stop the sheet was resting at before a measurement changed the stops, if any.
    private var restingStopIndex: Int? {
        guard hasBootstrapped, !isDragging, !isFinishing else { return nil }
        return stops.firstIndex(where: { abs($0 - reveal) < 1 })
    }

    /// A measurement moves the stops — the first layout pass can size the actions at a narrower
    /// width, the summary grows when the first set is logged, the note's recall collapses — but it
    /// must not move the sheet *between* stops. Resting at one, it stays at the same one; anywhere
    /// else it only has to fit.
    private func keepResting(at index: Int?) {
        guard hasBootstrapped, !isDragging, !isFinishing else { return }
        let stops = stops
        if let index, index < stops.count {
            if reveal != stops[index] { reveal = stops[index] }
        } else if reveal > openStop {
            reveal = openStop
        }
    }

    func containerDidMeasure(_ height: CGFloat) {
        guard height > 0, abs(height - containerHeight) > 0.5 else { return }
        containerHeight = height
        if isFinishing, !isDragging { reveal = fullReveal }
    }

    /// The first reveal comes from wherever the list already rests: a fresh workout opens at the
    /// actions stop, a resumed one that opened scrolled into its sets opens closed.
    private func bootstrapIfNeeded() {
        guard !hasBootstrapped, actionsHeight > 0, panelHeight > 0 else { return }
        hasBootstrapped = true
        reveal = largeTitleFloor(at: scrollOffset)
    }

    // MARK: Dragging

    /// A drag past the last stop stretches instead of stopping dead, the way a scroll view does.
    static func rubberBand(_ value: CGFloat, upper: CGFloat) -> CGFloat {
        guard value > upper else { return max(value, 0) }
        let overshoot = value - upper
        return upper + overshoot * 40 / (overshoot + 80)
    }
}

// MARK: - Panel

/// The part of the sheet below the compact row, clipped to the live reveal.
///
/// Two layers share the same edge. While recording, the panel (summary over actions) is
/// bottom-anchored, so a short pull shows the actions and a longer one brings the summary down
/// above them. While finishing, the finish content is top-anchored under the title and its action
/// bar rides the bottom edge. Finish and Continue are therefore one animation of one number —
/// the edge travels, the layers cross over — instead of two screens fading into each other.
struct RecorderTopSheetPanel<Summary: View, Actions: View, FinishContent: View, FinishBar: View>: View {
    let model: RecorderTopSheetModel
    let summary: Summary
    let actions: Actions
    let finishContent: FinishContent
    let finishBar: FinishBar

    init(
        model: RecorderTopSheetModel,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder finishContent: () -> FinishContent,
        @ViewBuilder finishBar: () -> FinishBar
    ) {
        self.model = model
        self.summary = summary()
        self.actions = actions()
        self.finishContent = finishContent()
        self.finishBar = finishBar()
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            // While finishing (and not being pulled) the height is the LIVE full reveal rather than
            // the stored one: the title row grows during the finish animation, so the room below it
            // shrinks by the same amount and the bar stays on the screen's bottom edge.
            .frame(height: max(model.isFinishing && !model.isDragging ? model.fullReveal : model.reveal, 0))
            .overlay(alignment: .bottom) { recordingPanel }
            .overlay(alignment: .top) { finishLayer }
            .overlay(alignment: .bottom) { finishBarLayer }
            .clipped()
    }

    // MARK: Recording

    /// In the tree until the first measurement, while open, while a finger could pull it out, and
    /// for the length of a close — never while finishing.
    private var recordingPanelIsPresent: Bool {
        guard !model.isFinishing else { return false }
        return model.actionsHeight == 0 || model.panelHeight == 0
            || model.reveal > 0.5 || model.isDragging || model.isClosing
    }

    @ViewBuilder
    private var recordingPanel: some View {
        if recordingPanelIsPresent {
            VStack(spacing: 13) {
                // `.hidden()`, not clipping: parked above the edge these rows sit over the compact
                // row, and a clipped view still takes taps and stays in the accessibility tree.
                // Hidden rather than removed, because their height is what the second stop is.
                if model.summaryIsRevealed {
                    summary
                } else {
                    summary.hidden()
                }
                actions
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        model.actionsDidMeasure(height)
                    }
            }
            .padding(.top, 12)
            .padding(.horizontal)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                model.panelDidMeasure(height)
            }
            .opacity(model.primaryRevealFraction)
            .allowsHitTesting(model.panelIsInteractive)
            .transition(
                .asymmetric(
                    // An ordinary open needs no fade — the travelling edge reveals the panel. Coming
                    // back from finishing it waits for the finish content to clear first.
                    insertion: model.isReturningFromFinish
                        ? .opacity.animation(.easeOut(duration: 0.22).delay(0.05))
                        : .identity,
                    removal: .opacity.animation(.easeIn(duration: 0.16))
                )
            )
        }
    }

    // MARK: Finishing

    /// The incoming layer starts almost at once and the outgoing one takes a little longer to leave,
    /// so the two overlap briefly instead of leaving the sheet empty while the edge travels.
    private var finishTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.24).delay(0.04)),
            removal: .opacity.animation(.easeIn(duration: 0.16))
        )
    }

    @ViewBuilder
    private var finishLayer: some View {
        if model.isFinishing {
            // Laid out at the full height once, top-anchored, and uncovered by the edge — so the
            // travel never re-lays out the scroll view inside.
            finishContent
                .frame(height: model.fullReveal, alignment: .top)
                .transition(finishTransition)
        }
    }

    @ViewBuilder
    private var finishBarLayer: some View {
        if model.isFinishing {
            finishBar
                .transition(finishTransition)
        }
    }
}

// MARK: - Title

/// The workout title, growing into a large title as the actions come out, and larger still while
/// finishing — the name is the finish panel's headline. Its line is sized for the large size at all
/// times while recording, so the compact row's height never changes with the reveal; only the
/// finish stop grows the row, and the panel below reads the live full reveal for that.
struct RecorderTopSheetTitleField: View {
    let model: RecorderTopSheetModel
    let text: Binding<String>
    let isFocused: FocusState<Bool>.Binding

    @ScaledMetric(relativeTo: .body) private var collapsedSize: CGFloat = 17
    @ScaledMetric(relativeTo: .title2) private var expandedSize: CGFloat = 22

    /// Finishing keeps the size the title had a moment before, when Finish was tapped. It used to
    /// grow to a large title, which cut most names off ("Tuesday Night Wo…") for a line that is the
    /// least interesting thing on the finish panel; the room goes to the week and the highlights.
    private var size: CGFloat {
        if model.isFinishing { return expandedSize }
        return collapsedSize + (expandedSize - collapsedSize) * model.primaryRevealFraction
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "Ag")
                .modifier(AnimatableTitleFont(size: max(size, expandedSize)))
                .hidden()
            TextField(
                "",
                text: text,
                prompt: Text(Workout.getStandardName(for: Date())).foregroundStyle(Color.label)
            )
            .submitLabel(.done)
            .focused(isFocused)
            .lineLimit(1)
            .foregroundColor(.label)
            .modifier(AnimatableTitleFont(size: size))
            .accessibilityIdentifier("recorderTitleField")
        }
    }
}

/// Animates a bold title's point size: because `size` is the `animatableData`, SwiftUI
/// interpolates it frame-by-frame inside a `withAnimation`, so the workout title scales
/// smoothly between its folded and unfolded sizes instead of snapping.
struct AnimatableTitleFont: ViewModifier, Animatable {
    var size: CGFloat

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .bold))
    }
}

// MARK: - List fade

/// The set list's mask: rows dissolve along the sheet's bottom edge, wherever that edge is. It
/// follows the edge on its own, so the list's content never re-lays out while the sheet moves.
struct RecorderListFadeMask: View {
    let model: RecorderTopSheetModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: max(model.closedHeight + model.reveal - 10, 0))
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 26)
            Color.black
        }
    }
}
