//
//  WorkoutEffortViews.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.08.26.
//

import SwiftUI

// MARK: - The bars

/// The 1…10 effort scale, drawn the way Apple's Fitness app draws it: four bars rising left to
/// right, one per band, each as wide as the number of ratings it covers (3 · 3 · 2 · 2). The
/// rating is a white capsule standing in one of the ten slots — the dots show where the others
/// are, so the scale reads as ten answers grouped into four words rather than four buttons.
///
/// **The scale is deliberately colourless.** In LOGIT a colour *means a muscle group*, everywhere:
/// the donut, the set-group rails, the balance chart. An effort ramp painted teal-to-rose would
/// spend that vocabulary on something that has nothing to do with muscles, and a 7 would read as
/// "shoulders". The muscle groups still colour the *background* the picker sits on — that is
/// LOGIT's one departure from Apple here — and the scale itself stays grey and white.
///
/// One view serves every size: the rating screen and the tile's read-only echo both draw these
/// bars, so the shape a rating is made on is the shape it is later recognised by.
struct WorkoutEffortBars: View {
    /// How big the bars are drawn, and with it how much of the anatomy survives: the mini size
    /// drops the dots and the marker (there is no room to aim at 26pt) and shows the level by
    /// filling whole bands instead.
    struct Size {
        var height: CGFloat
        var spacing: CGFloat
        var cornerRadius: CGFloat
        var dotDiameter: CGFloat
        var dotBottomInset: CGFloat
        /// How far inside its bar the marker sits, on every side. The marker never crosses the
        /// bar's silhouette — not over the slanted top, not past a rounded corner — so the bar
        /// always frames it.
        var markerPadding: CGFloat
        /// Whether the dots and the marker are drawn.
        var showsMarkers: Bool

        /// The rating screen's size: full height, aimable slots.
        static let rating = Size(
            height: 186,
            spacing: 10,
            cornerRadius: 22,
            dotDiameter: 7,
            dotBottomInset: 13,
            markerPadding: 7,
            showsMarkers: true
        )

        /// The tile's read-only echo, small enough to sit at the trailing edge of a row.
        static let mini = Size(
            height: 26,
            spacing: 2.5,
            cornerRadius: 3,
            dotDiameter: 0,
            dotBottomInset: 0,
            markerPadding: 0,
            showsMarkers: false
        )
    }

    let score: Int?
    /// The marker's fill. The workout's muscle-group gradient at every call site — run **top to
    /// bottom**: the marker is a narrow, tall capsule, and a leading-to-trailing sweep squeezes a
    /// whole spectrum into ~25pt and reads as mud.
    let tint: AnyShapeStyle
    var size: Size = .rating
    /// Whether a finger can move the rating. Read-only everywhere but the picker.
    var isInteractive: Bool = false
    var onSelect: ((Int) -> Void)? = nil
    /// Called when the finger lifts (and after an accessibility adjustment), so a host can write
    /// a drafted rating back to its model once instead of on every slot the drag crosses.
    var onEnded: (() -> Void)? = nil

    /// Bumped on every selection a finger makes. `sensoryFeedback` fires off it rather than off
    /// `score`, so opening a sheet on an already-rated workout doesn't tick.
    @State private var selections = 0
    /// Set while a finger is down so a tick only fires when the value actually changes.
    @State private var lastSelectedScore: Int?

    /// How tall the shortest point of the ramp is, as a fraction of the tallest. The ramp is one
    /// straight line across all four bars; the generous corner radius is what makes the narrow
    /// bands at the top read as nearly flat while the wide ones at the bottom read as wedges.
    private static let minimumHeightFraction: CGFloat = 0.22

    private static let slotCount = CGFloat(WorkoutEffort.scoreRange.count)

    /// How much narrower than its slot the marker is, on each side — enough that two neighbouring
    /// slots never look joined, little enough that the marker still reads as "this one".
    private static let markerSlotInset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = max(
                0,
                (geometry.size.width - size.spacing * CGFloat(WorkoutEffort.allCases.count - 1))
                    / Self.slotCount
            )
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: size.spacing) {
                    ForEach(WorkoutEffort.allCases) { effort in
                        band(effort, slotWidth: slotWidth)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                if size.showsMarkers, let score, let geometry = marker(for: score, slotWidth: slotWidth) {
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.width, height: geometry.height)
                        .offset(x: geometry.x, y: -size.markerPadding)
                        .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
                }
            }
            // One marker that slides and grows between slots, rather than one appearing where
            // another vanished: the rating is a value moving along a scale, and it should look
            // like one wherever it is changed from — a drag, a row in the description list, Skip.
            .animation(.snappy(duration: 0.3, extraBounce: 0.1), value: score)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isInteractive else { return }
                        select(atX: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { _ in
                        guard isInteractive else { return }
                        lastSelectedScore = nil
                        onEnded?()
                    },
                isEnabled: isInteractive
            )
        }
        .frame(height: size.height)
        // The system's own selection feedback, which SwiftUI keeps prepared. A throwaway
        // `UISelectionFeedbackGenerator` fired and released inside the gesture drops the tick or
        // lands it late (see `MuscleFocusScreen`).
        .sensoryFeedback(.selection, trigger: selections)
        .accessibilityElement(children: .ignore)
        // Read-only copies (the tile's echo, the Skip icon) carry no identifier and no element of
        // their own: they are a picture of a rating, and a second `effortScale` in the tree is
        // one a test's `firstMatch` can land on instead of the real control.
        .accessibilityIdentifier(isInteractive ? "effortScale" : "")
        .accessibilityLabel(NSLocalizedString("effort", comment: ""))
        .accessibilityValue(score.map { "\($0)" } ?? NSLocalizedString("notRated", comment: ""))
        .accessibilityHidden(!isInteractive)
        .accessibilityAdjustableAction { direction in
            guard isInteractive else { return }
            let current = score ?? WorkoutEffort.scoreRange.lowerBound
            switch direction {
            case .increment: onSelect?(min(current + 1, WorkoutEffort.scoreRange.upperBound))
            case .decrement: onSelect?(max(current - 1, WorkoutEffort.scoreRange.lowerBound))
            default: break
            }
            selections += 1
            onEnded?()
        }
    }

    // MARK: - One band

    private func band(_ effort: WorkoutEffort, slotWidth: CGFloat) -> some View {
        let leadingSlot = CGFloat(effort.scores.lowerBound - 1)
        let slots = CGFloat(effort.scores.count)
        return RampBar(
            leadingHeight: rampHeight(atSlot: leadingSlot),
            trailingHeight: rampHeight(atSlot: leadingSlot + slots),
            cornerRadius: size.cornerRadius
        )
        .fill(fill(for: effort))
        .frame(width: slotWidth * slots)
        .overlay(alignment: .bottom) {
            if size.showsMarkers {
                dots(effort, slotWidth: slotWidth)
            }
        }
    }

    /// One dot per slot, on one line across all four bars. The slot holding the rating shows none:
    /// the marker is standing in its place.
    private func dots(_ effort: WorkoutEffort, slotWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(effort.scores), id: \.self) { value in
                Circle()
                    .fill(Color.label.opacity(0.35))
                    .frame(width: size.dotDiameter, height: size.dotDiameter)
                    .opacity(value == score ? 0 : 1)
                    .frame(width: slotWidth)
            }
        }
        .padding(.bottom, size.dotBottomInset)
    }

    // MARK: - The marker

    private struct MarkerGeometry {
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    /// Where the marker stands, and how much of its bar it is allowed to fill. Its height comes
    /// from the bar's own silhouette at its two edges — the slanted top *and* the rounded corners
    /// — less the padding, so it can never break out of the bar it belongs to.
    private func marker(for score: Int, slotWidth: CGFloat) -> MarkerGeometry? {
        guard slotWidth > 0, let effort = WorkoutEffort(score: score) else { return nil }
        let bandIndex = CGFloat(WorkoutEffort.allCases.firstIndex(of: effort) ?? 0)
        let leadingSlot = CGFloat(effort.scores.lowerBound - 1)
        let bandWidth = slotWidth * CGFloat(effort.scores.count)
        let bandX = leadingSlot * slotWidth + bandIndex * size.spacing

        let slotCentre = (CGFloat(score - effort.scores.lowerBound) + 0.5) * slotWidth
        let fullWidth = max(2, slotWidth - Self.markerSlotInset * 2)
        // Centred on its slot, then nudged in if that would put it against the band's side wall:
        // at 2pt the nudge is invisible, and it keeps the padding even all the way round.
        let localX = min(
            max(slotCentre - fullWidth / 2, size.markerPadding),
            bandWidth - size.markerPadding - fullWidth
        )
        let ceiling = min(
            topSurface(atX: localX, in: effort, bandWidth: bandWidth),
            topSurface(atX: localX + fullWidth, in: effort, bandWidth: bandWidth)
        )
        let height = max(2, ceiling - size.markerPadding * 2)
        // The lowest ratings sit in a bar barely taller than a slot is wide, and a capsule as wide
        // as it is tall reads as a blob rather than a marker. Those taper instead — narrowing can
        // only raise the ceiling the width was measured against, so containment still holds.
        let width = min(fullWidth, height / 1.5)
        return MarkerGeometry(
            x: bandX + localX + (fullWidth - width) / 2,
            width: width,
            height: height
        )
    }

    /// The height of a bar's top surface at one x inside it, arcs included. The straight top edge
    /// is the ceiling everywhere except under the two top corners, where the rounded silhouette
    /// dips below it — and the corner is exactly where a naive line would let the marker escape.
    private func topSurface(atX x: CGFloat, in effort: WorkoutEffort, bandWidth: CGFloat) -> CGFloat {
        let leadingSlot = CGFloat(effort.scores.lowerBound - 1)
        let leading = rampHeight(atSlot: leadingSlot)
        let trailing = rampHeight(atSlot: leadingSlot + CGFloat(effort.scores.count))
        let radius = RampBar.resolvedRadius(
            cornerRadius: size.cornerRadius,
            width: bandWidth,
            leadingHeight: leading,
            trailingHeight: trailing
        )
        let slope = (trailing - leading) / max(bandWidth, 1)
        var height = leading + slope * x
        guard radius > 0 else { return max(0, height) }
        // Each corner's arc is tangent to the top edge from below, so its circle never rises above
        // the line: taking the lower of line and circle gives the silhouette without case analysis.
        let normal = (slope * slope + 1).squareRoot()
        for centreX in [radius, bandWidth - radius] {
            let dx = x - centreX
            guard abs(dx) <= radius else { continue }
            let centreY = leading + slope * centreX - radius * normal
            height = min(height, centreY + (radius * radius - dx * dx).squareRoot())
        }
        return max(0, height)
    }

    /// Every bar wears the same neutral track — only the marker says where the rating is, exactly
    /// as on Apple's screen. The mini size has no marker, so there it falls back to filling the
    /// bands up to the rating: at 26pt the level has to come from somewhere.
    private func fill(for effort: WorkoutEffort) -> AnyShapeStyle {
        guard !size.showsMarkers, let score, let rated = WorkoutEffort(score: score) else {
            return AnyShapeStyle(Color.secondaryFill)
        }
        if effort == rated { return tint }
        return AnyShapeStyle(
            effort.scores.upperBound < rated.scores.lowerBound
                ? Color.label.opacity(0.35)
                : Color.secondaryFill
        )
    }

    /// The ramp: one straight line from `minimumHeightFraction` at the far left of the first bar
    /// to the full height at the far right of the last.
    private func rampHeight(atSlot slot: CGFloat) -> CGFloat {
        let fraction = Self.minimumHeightFraction
            + (1 - Self.minimumHeightFraction) * (slot / Self.slotCount)
        return size.height * fraction
    }

    private func select(atX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let step = width / Self.slotCount
        let raw = Int(x / step) + 1
        let clamped = min(
            max(raw, WorkoutEffort.scoreRange.lowerBound),
            WorkoutEffort.scoreRange.upperBound
        )
        guard clamped != lastSelectedScore else { return }
        lastSelectedScore = clamped
        selections += 1
        onSelect?(clamped)
    }
}

/// One bar of the ramp: a rectangle whose top edge is slanted, with every corner rounded by the
/// same radius. Drawn by hand because SwiftUI can only round the corners of a rectangle, and the
/// slanted top is the whole point — the four bars share one ascending line.
private struct RampBar: Shape {
    var leadingHeight: CGFloat
    var trailingHeight: CGFloat
    var cornerRadius: CGFloat

    /// The radius actually drawn. It can't exceed half the shortest side, or the arcs overrun each
    /// other and the shape folds in on itself — a mini bar is 3pt tall at its left edge. The
    /// marker's containment maths reads this too, so both agree on where the corner is.
    static func resolvedRadius(
        cornerRadius: CGFloat,
        width: CGFloat,
        leadingHeight: CGFloat,
        trailingHeight: CGFloat
    ) -> CGFloat {
        min(cornerRadius, width / 2, max(1, min(leadingHeight, trailingHeight) / 2))
    }

    func path(in rect: CGRect) -> Path {
        let corners = [
            CGPoint(x: rect.minX, y: rect.maxY - leadingHeight),
            CGPoint(x: rect.maxX, y: rect.maxY - trailingHeight),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let radius = Self.resolvedRadius(
            cornerRadius: cornerRadius,
            width: rect.width,
            leadingHeight: leadingHeight,
            trailingHeight: trailingHeight
        )
        var path = Path()
        path.move(to: midpoint(corners[3], corners[0]))
        for index in corners.indices {
            path.addArc(
                tangent1End: corners[index],
                tangent2End: corners[(index + 1) % corners.count],
                radius: radius
            )
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(leadingHeight, trailingHeight) }
        set {
            leadingHeight = newValue.first
            trailingHeight = newValue.second
        }
    }
}

// MARK: - The rating, spelled out

/// The rating in words: the score in a circle, the band it falls in, and — where the caller
/// offers one — the ⓘ that opens the description list. Unrated, the whole capsule is the
/// invitation instead.
///
/// It is a capsule under the bars on the rating screen, so "what a 5 means" is answered in the same
/// place and the same shape wherever you are rating from.
struct WorkoutEffortValueCapsule: View {
    let score: Int?
    var onInfo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let score, let effort = WorkoutEffort(score: score) {
                WorkoutEffortScoreBadge(score: score)
                Text(effort.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(Color.secondaryLabel)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("effortDescriptions", comment: ""))
                    .accessibilityIdentifier("effortDescriptionsButton")
                }
            } else {
                Spacer(minLength: 0)
                Text(NSLocalizedString("rateYourEffort", comment: ""))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.secondaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(Color.tertiaryFill, in: .capsule)
        .animation(.snappy(duration: 0.2), value: score)
    }
}

/// The score in a circle. The one place a number appears in the effort UI, so it looks the same
/// in the capsule and in every row of the description list.
struct WorkoutEffortScoreBadge: View {
    let score: Int
    var diameter: CGFloat = 30

    var body: some View {
        Text("\(score)")
            .font(.system(size: diameter * 0.52, weight: .semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(Color.label)
            .frame(width: diameter, height: diameter)
            .background(Color.quaternaryFill, in: .circle)
    }
}

// MARK: - The picker

/// The bars and the capsule together — the rating itself, without any chrome around it. The
/// rating sheet shows exactly this, and every place a workout is rated opens that sheet (the
/// recorder's finish panel included, from its effort tile), so rating is the same act everywhere.
struct WorkoutEffortPicker: View {
    @Binding var score: Int?
    /// The marker's fill — the workout's muscle-group gradient, top to bottom.
    let tint: AnyShapeStyle
    var size: WorkoutEffortBars.Size = .rating
    /// What the capsule's ⓘ does — the sheet pushes the description list. Passing `nil` drops the
    /// button.
    var showDescriptions: (() -> Void)? = nil

    /// The rating while a finger is still on it. Writing through on every slot a drag crosses
    /// republishes whatever the binding reaches — bound straight to the managed object, that is the
    /// whole screen observing it — which is what used to make the scale feel laggy. The drag moves
    /// this; only the lift writes.
    @State private var draft: Int?

    var body: some View {
        VStack(spacing: 22) {
            WorkoutEffortBars(
                score: draft,
                tint: tint,
                size: size,
                isInteractive: true,
                onSelect: { draft = $0 },
                onEnded: { if score != draft { score = draft } }
            )
            WorkoutEffortValueCapsule(score: draft, onInfo: showDescriptions)
        }
        .onAppear { draft = score }
        // An external change — a row picked in the description list, a Skip — must show here too.
        .onChange(of: score) { if score != draft { draft = score } }
    }
}

// MARK: - The tile

/// "Effort" over the rating, with the bars echoing it at the trailing edge — or "Add Effort"
/// where there is nothing to echo yet. The workout editor and the workout detail screen both
/// show this and nothing else, so an unrated workout offers the rating instead of hiding it.
///
/// Tapping is the caller's business: the editor lives inside a pass-through sheet tray that has
/// to know a sheet is stacking on it, so the tile never owns the presentation itself
/// (see `WorkoutEditorScreen`).
struct WorkoutEffortTile: View {
    enum Style {
        /// The app's standard opaque cell, for the editor and the detail screen.
        case tile
        /// A translucent card, for anything floating over the muscle wash.
        case translucent
    }

    enum Layout {
        /// Label and rating on the leading side, the bars' echo at the trailing edge — a full-width row.
        case wide
        /// Half a row, beside the note on the finish panel: the label and a small echo on top, the
        /// rating under them, so the band's name never has to share its line with the bars.
        case compact
    }

    let score: Int?
    /// The rated band's fill in the echo at the trailing edge — the workout's muscle-group
    /// gradient, so the tile carries the same colour the marker did on the rating screen.
    let tint: AnyShapeStyle
    var style: Style = .tile
    var layout: Layout = .wide
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content
                .padding(CELL_PADDING)
                .contentShape(Rectangle())
        }
        // The identifier and label ride the Button itself: wrapping it in an
        // `accessibilityElement(children:)` container drops the button trait, and with it every
        // `app.buttons["effortTile"]` lookup (see the Summary's title row for the same trap).
        .buttonStyle(.plain)
        .accessibilityIdentifier("effortTile")
        .accessibilityLabel(effortLabel)
        .modifier(EffortTileSurface(style: style))
        .animation(.snappy(duration: 0.25), value: score)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .wide: wideContent
        case .compact: compactContent
        }
    }

    private var wideContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("effort", comment: ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.label)
                if let score, let effort = WorkoutEffort(score: score) {
                    HStack(spacing: 10) {
                        WorkoutEffortScoreBadge(score: score, diameter: 26)
                        Text(effort.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.label)
                    }
                } else {
                    Label(
                        NSLocalizedString("addEffort", comment: ""),
                        systemImage: "plus.circle"
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.secondaryLabel)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            WorkoutEffortBars(score: score, tint: tint, size: .mini)
                .frame(width: 58)
        }
    }

    /// Half a row: the label, the rating under it, and the bars' echo along the bottom at the tile's
    /// full width. Fills whatever height the row gives it.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("effort", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
            Group {
                if let score, let effort = WorkoutEffort(score: score) {
                    HStack(spacing: 8) {
                        WorkoutEffortScoreBadge(score: score, diameter: 24)
                        Text(effort.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.label)
                    }
                } else {
                    // "Rate", not "Add Effort": the label above already says what is being rated,
                    // and at half width the long form wraps in every language but English.
                    Label(NSLocalizedString("rateEffortShort", comment: ""), systemImage: "plus.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.secondaryLabel)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 4)
            Spacer(minLength: 12)
            WorkoutEffortBars(score: score, tint: tint, size: .mini)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var effortLabel: String {
        let effort = score.flatMap { WorkoutEffort(score: $0) }
        guard let score, let effort else {
            return NSLocalizedString("addEffort", comment: "")
        }
        return NSLocalizedString("effort", comment: "") + ": \(effort.name) \(score)"
    }
}

private struct EffortTileSurface: ViewModifier {
    let style: WorkoutEffortTile.Style

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .tile: content.tileStyle()
        case .translucent: content.translucentTileStyle()
        }
    }
}

#Preview {
    struct Wrapper: View {
        @State private var score: Int? = 5
        private let tint = [MuscleGroup.chest, .shoulders, .triceps]
            .weightedSpectrumGradientStyle(startPoint: .top, endPoint: .bottom)
        var body: some View {
            VStack(spacing: 30) {
                WorkoutEffortPicker(score: $score, tint: tint, showDescriptions: {})
                WorkoutEffortTile(score: score, tint: tint, action: {})
                WorkoutEffortTile(score: nil, tint: tint, action: {})
            }
            .padding()
            .frame(maxHeight: .infinity)
            .background(Color.black)
        }
    }
    return Wrapper()
}
