//
//  SetGroupThread.swift
//  LOGIT
//
//  The "thread": the connecting line that runs down a workout's (or template's) set-group
//  list, plus the bulge sockets it plugs into. A superset is one card like any other group —
//  its exercises page horizontally *inside* that card — so the thread never forks.
//
//  Shared by the workout recorder/detail and the template editor/detail so both stay one
//  visual system — see AGENT.md, "Templates mirror workouts". Anything defined here is the
//  vocabulary; each feature only supplies its own content.
//

import SwiftUI

// MARK: - Metrics

/// One home for the thread's geometry so the workout and template sides can never drift.
enum SetGroupThread {
    /// Stroke width of every thread segment (trunk, rails).
    static let lineWidth: CGFloat = 3
    /// Trunk length between consecutive set groups — deliberately tighter than
    /// `SECTION_SPACING`; the bulge's protrusion adds its own visual air on top.
    static let trunkHeight: CGFloat = 12
    /// How far a segment draws past its own bounds into the neighbouring fill. Joins are
    /// sealed by overlap, never by exact edge-kissing — antialiasing opens hairlines there.
    static let jointOverlap: CGFloat = 2
    /// Horizontal inset of a snapped superset lane, per side: lanes are this much narrower
    /// than the card they page inside, so the neighbouring lane peeks and the group always
    /// shows there is more to swipe to. The first lane still sits flush with the card's
    /// leading edge, the last (clamped at the scroll bound) flush with the trailing one.
    static let laneInset: CGFloat = 24
    static let laneSpacing: CGFloat = 12

    /// Width of one superset lane inside a card of `containerWidth`.
    static func laneWidth(in containerWidth: CGFloat) -> CGFloat {
        max(containerWidth - laneInset * 2, 100)
    }

    /// "2 of 5" — a group's place in its workout/template, shown in the bulge socket.
    static func indexLabel(index: Int?, count: Int) -> String? {
        guard let index, count > 0 else { return nil }
        return String.localizedStringWithFormat(
            NSLocalizedString("groupIndexOfTotal", comment: ""), index + 1, count
        )
    }
}

// MARK: - Trunk

/// The thread segment between two set groups. Draws `jointOverlap` past its layout height at
/// both ends — into the cell above and the bulge below — so no join can show a seam.
struct SetGroupTrunk: View {
    var height: CGFloat = SetGroupThread.trunkHeight

    var body: some View {
        Rectangle()
            .foregroundStyle(Color.threadLine)
            .frame(
                width: SetGroupThread.lineWidth,
                height: height + SetGroupThread.jointOverlap * 2
            )
            .frame(height: height)
    }
}

extension View {
    /// Runs the trunk behind a between-groups element (a rest capsule), so the line passes
    /// under it rather than stopping at it.
    func onSetGroupTrunk(height: CGFloat = SetGroupThread.trunkHeight) -> some View {
        padding(.vertical, height / 2)
            .background(
                Rectangle()
                    .foregroundStyle(Color.threadLine)
                    .frame(width: SetGroupThread.lineWidth)
                    .padding(.vertical, -SetGroupThread.jointOverlap)
            )
    }
}

// MARK: - Index bulge

/// The socket on top of every set-group card: a low rounded bump growing out of the card's
/// top edge that carries the group's "2 of 5" position and receives the thread. The bump is
/// deliberately lower than the label — most of the label sits inside the card, only its top
/// peeks into the bump — and its fill continues below the card edge so the card's inner top
/// highlight can't draw a seam under it. Mounted with `bulgeSocket(label:)`, which draws it
/// OVER the card.
struct SetGroupIndexBulge: View {
    let label: String

    /// Height of the bump above the card's top edge.
    static let protrusion: CGFloat = 8
    /// How far the bump's fill continues below the card edge.
    static let underlap: CGFloat = 8
    /// Horizontal run of each S-curved shoulder.
    static let shoulderRun: CGFloat = 12
    /// How tightly the shoulder S hugs its endpoints: 0.5 is a plain slope, towards 1 the
    /// curve stays flat at both ends and turns in the middle. 0.75 is the chosen gentle S.
    static let shoulderTension: CGFloat = 0.75
    /// Horizontal padding between the label and the shoulders.
    static let labelPadding: CGFloat = 8

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Self.labelPadding)
            // Push the label down so it straddles the card edge — most of it sits inside
            // the card, only its top peeks into the bump.
            .offset(y: 3)
            .frame(height: Self.protrusion + Self.underlap)
            .background {
                SetGroupBulgeShape(
                    shoulderRun: Self.shoulderRun,
                    shoulderTension: Self.shoulderTension,
                    underlap: Self.underlap
                )
                .fill(Color.secondaryBackground)
                // The shoulders flare beyond the label's bounds on both sides.
                .padding(.horizontal, -Self.shoulderRun)
            }
    }
}

extension View {
    /// Mounts the index bulge on top of a set-group card: drawn over the card (so the label's
    /// lower half and the underlap sit on the card's fill), extending above it by the bump's
    /// protrusion, which is reserved as layout space.
    @ViewBuilder
    func bulgeSocket(label: String?) -> some View {
        if let label {
            overlay(alignment: .top) {
                SetGroupIndexBulge(label: label)
                    .alignmentGuide(.top) { $0[.top] + SetGroupIndexBulge.protrusion }
            }
            .padding(.top, SetGroupIndexBulge.protrusion)
        } else {
            self
        }
    }
}

/// The bulge's outline: a smooth hill. Each side is one S-curve with horizontal tangents at
/// both ends, so the concave blend into the card's edge and the convex top shoulder are both
/// generously rounded — no straight walls, no sharp corners anywhere. Below the card edge the
/// fill continues `underlap` points as a plain rectangle. The rect includes the shoulders and
/// the underlap.
struct SetGroupBulgeShape: Shape {
    var shoulderRun: CGFloat = 12
    var shoulderTension: CGFloat = 0.75
    var underlap: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edge = rect.maxY - underlap
        let top = rect.minY
        path.move(to: CGPoint(x: rect.minX, y: edge))
        // Left shoulder: card edge up to the flat top in one S.
        path.addCurve(
            to: CGPoint(x: rect.minX + shoulderRun, y: top),
            control1: CGPoint(x: rect.minX + shoulderRun * shoulderTension, y: edge),
            control2: CGPoint(x: rect.minX + shoulderRun * (1 - shoulderTension), y: top)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulderRun, y: top))
        // Right shoulder, mirrored.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: edge),
            control1: CGPoint(x: rect.maxX - shoulderRun * (1 - shoulderTension), y: top),
            control2: CGPoint(x: rect.maxX - shoulderRun * shoulderTension, y: edge)
        )
        // Continue below the card edge so the bump covers the card's inner top highlight.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Superset lane indicator

/// Which lane of a superset card is on screen: one dot per exercise, the current one filled in
/// its own muscle colour. It sits between the lanes and the card's action bar — and that bar
/// belongs to the GROUP, so once you've swiped, these dots and the lane's own header are what
/// say which exercise the fields above are for.
struct SupersetLaneIndicator: View {
    /// One colour per lane, in lane order.
    let colors: [Color]
    let selectedIndex: Int

    static let dotSize: CGFloat = 6

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .foregroundStyle(
                        index == selectedIndex
                            ? AnyShapeStyle(color.gradient)
                            : AnyShapeStyle(Color.tertiaryLabel)
                    )
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .animation(.snappy, value: selectedIndex)
        // The lane's own exercise header already announces which exercise is on screen; a
        // second, wordless announcement of the same thing only adds noise in VoiceOver.
        .accessibilityHidden(true)
    }
}

// MARK: - List row

extension View {
    /// How a set-group row (cell + the trunk below it) joins the list: the row is composited
    /// before its shadow so the shadow follows the row's union silhouette. Shadowing the raw
    /// subtree shadows every primitive individually, and the cards' black shadows then black
    /// out the thin thread wherever a line meets a card, a bulge or a rail — reading as gaps
    /// in the line. Earlier rows draw above later ones so a trunk's tip enters the next
    /// cell's bulge OVER that row's shadow instead of being eaten by it.
    func setGroupRowStyle(index: Int, count: Int, reduceShadow: Bool = false) -> some View {
        compositingGroup()
            .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
            .zIndex(Double(count - index))
    }
}
