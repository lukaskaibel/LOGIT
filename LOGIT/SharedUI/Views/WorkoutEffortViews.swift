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
/// One view serves every size: the rating screen, the recorder's finish panel and the tile's
/// read-only echo all draw these bars, so the shape a rating is made on is the shape it is later
/// recognised by.
struct WorkoutEffortBars: View {
    /// How big the bars are drawn, and with it how much of the anatomy survives: the mini size
    /// drops the dots and the capsule (there is no room to aim at 26pt) and shows the level by
    /// filling whole bands instead.
    struct Size {
        var height: CGFloat
        var spacing: CGFloat
        var cornerRadius: CGFloat
        var dotDiameter: CGFloat
        var dotBottomInset: CGFloat
        /// How far the selected capsule pokes out above its bar's top edge.
        var markerOvershoot: CGFloat
        var markerInset: CGFloat
        /// Whether the dots and the selected capsule are drawn. The mini size has no room for
        /// them, which is why its bars carry the rating in their fill instead.
        var showsMarkers: Bool

        /// The rating screen's size: full height, aimable slots.
        static let rating = Size(
            height: 186,
            spacing: 10,
            cornerRadius: 22,
            dotDiameter: 7,
            dotBottomInset: 13,
            markerOvershoot: 9,
            markerInset: 5,
            showsMarkers: true
        )

        /// The recorder's finish panel, where the rating shares the screen with everything else
        /// that just happened.
        static let compact = Size(
            height: 132,
            spacing: 8,
            cornerRadius: 18,
            dotDiameter: 6,
            dotBottomInset: 11,
            markerOvershoot: 7,
            markerInset: 4,
            showsMarkers: true
        )

        /// The tile's read-only echo, small enough to sit at the trailing edge of a row.
        static let mini = Size(
            height: 26,
            spacing: 2.5,
            cornerRadius: 3,
            dotDiameter: 0,
            dotBottomInset: 0,
            markerOvershoot: 0,
            markerInset: 0,
            showsMarkers: false
        )
    }

    let score: Int?
    var size: Size = .rating
    /// Whether a finger can move the rating. Read-only everywhere but the picker.
    var isInteractive: Bool = false
    var onSelect: ((Int) -> Void)? = nil
    /// Called when the finger lifts (and after an accessibility adjustment), so a host can write
    /// a drafted rating back to its model once instead of on every slot the drag crosses.
    var onEnded: (() -> Void)? = nil

    /// Set while a finger is down so the haptic only fires when the value actually changes.
    @State private var lastHapticScore: Int?

    /// How tall the shortest point of the ramp is, as a fraction of the tallest. The ramp is one
    /// straight line across all four bars; the generous corner radius is what makes the narrow
    /// bands at the top read as nearly flat while the wide ones at the bottom read as wedges.
    private static let minimumHeightFraction: CGFloat = 0.22

    private static let slotCount = CGFloat(WorkoutEffort.scoreRange.count)

    /// How much narrower than its slot the selected capsule is, on each side — enough that two
    /// neighbouring slots never look joined, little enough that the capsule still reads as
    /// "this one".
    private static let markerSlotInset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = max(
                0,
                (geometry.size.width - size.spacing * CGFloat(WorkoutEffort.allCases.count - 1))
                    / Self.slotCount
            )
            HStack(spacing: size.spacing) {
                ForEach(WorkoutEffort.allCases) { effort in
                    band(effort, slotWidth: slotWidth)
                }
            }
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
                        lastHapticScore = nil
                        onEnded?()
                    },
                isEnabled: isInteractive
            )
        }
        .frame(height: size.height)
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
            onEnded?()
        }
    }

    // MARK: - One band

    private func band(_ effort: WorkoutEffort, slotWidth: CGFloat) -> some View {
        let slots = CGFloat(effort.scores.count)
        let width = slotWidth * slots
        let leadingSlot = CGFloat(effort.scores.lowerBound - 1)
        return RampBar(
            leadingHeight: rampHeight(atSlot: leadingSlot),
            trailingHeight: rampHeight(atSlot: leadingSlot + slots),
            cornerRadius: size.cornerRadius
        )
        .fill(fill(for: effort))
        .frame(width: width)
        .overlay(alignment: .bottom) {
            if size.showsMarkers {
                slotMarks(effort, slotWidth: slotWidth)
            }
        }
    }

    /// The dots, and — where the rating landed — the capsule standing in that dot's place.
    private func slotMarks(_ effort: WorkoutEffort, slotWidth: CGFloat) -> some View {
        // Bottom-aligned, or the slot holding the tall marker would set the row's height and
        // centre every other slot's dot against it — the dots have to sit on one line.
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(effort.scores), id: \.self) { value in
                ZStack(alignment: .bottom) {
                    Circle()
                        .fill(Color.label.opacity(0.35))
                        .frame(width: size.dotDiameter, height: size.dotDiameter)
                        .padding(.bottom, size.dotBottomInset)
                        .opacity(value == score ? 0 : 1)
                    if value == score {
                        Capsule()
                            .fill(Color.label)
                            .frame(
                                width: max(0, slotWidth - Self.markerSlotInset * 2),
                                height: rampHeight(atSlot: CGFloat(value) - 0.5)
                                    - size.markerInset + size.markerOvershoot
                            )
                            .padding(.bottom, size.markerInset)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(width: slotWidth, alignment: .bottom)
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Every bar wears the same neutral track — only the white capsule says where the rating is,
    /// exactly as on Apple's screen. The mini size has no capsule, so there it falls back to
    /// filling the bands up to the rating: at 26pt the level has to come from somewhere.
    private func fill(for effort: WorkoutEffort) -> AnyShapeStyle {
        guard !size.showsMarkers, let score, let rated = WorkoutEffort(score: score) else {
            return AnyShapeStyle(Color.secondaryFill)
        }
        if effort == rated { return AnyShapeStyle(Color.label) }
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
        guard clamped != lastHapticScore else { return }
        lastHapticScore = clamped
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            onSelect?(clamped)
        }
    }
}

/// One bar of the ramp: a rectangle whose top edge is slanted, with every corner rounded by the
/// same radius. Drawn by hand because SwiftUI can only round the corners of a rectangle, and the
/// slanted top is the whole point — the four bars share one ascending line.
private struct RampBar: Shape {
    var leadingHeight: CGFloat
    var trailingHeight: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let corners = [
            CGPoint(x: rect.minX, y: rect.maxY - leadingHeight),
            CGPoint(x: rect.maxX, y: rect.maxY - trailingHeight),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        // The radius can't exceed half the shortest side, or the arcs overrun each other and the
        // shape folds in on itself — a mini bar is 3pt tall at its left edge.
        let radius = min(
            cornerRadius,
            rect.width / 2,
            max(1, min(leadingHeight, trailingHeight) / 2)
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
/// It is a capsule under the bars on the rating screen and inside the finish panel's card, so
/// "what a 5 means" is answered in the same place and the same shape wherever you are rating.
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
/// rating sheet and the recorder's finish panel both show exactly this, which is what makes
/// rating a workout the same act wherever it happens.
struct WorkoutEffortPicker: View {
    @Binding var score: Int?
    var size: WorkoutEffortBars.Size = .rating
    /// What the capsule's ⓘ does: the sheet pushes the description list, the finish panel
    /// presents it. Passing `nil` drops the button.
    var showDescriptions: (() -> Void)? = nil

    /// The rating while a finger is still on it. Writing through on every slot a drag crosses
    /// republishes whatever the binding reaches — in the recorder's finish panel that is the
    /// managed object, and with it the entire panel — which is what used to make the scale feel
    /// laggy. The drag moves this; only the lift writes.
    @State private var draft: Int?

    var body: some View {
        VStack(spacing: 22) {
            WorkoutEffortBars(
                score: draft,
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

    let score: Int?
    var style: Style = .tile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                WorkoutEffortBars(score: score, size: .mini)
                    .frame(width: 58)
            }
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
        var body: some View {
            VStack(spacing: 30) {
                WorkoutEffortPicker(score: $score, showDescriptions: {})
                WorkoutEffortTile(score: score, action: {})
                WorkoutEffortTile(score: nil, action: {})
            }
            .padding()
            .frame(maxHeight: .infinity)
            .background(Color.black)
        }
    }
    return Wrapper()
}
