//
//  SetGroupThread.swift
//  LOGIT
//
//  The "thread": the connecting line that runs down a workout's (or template's) set-group
//  list, plus the bulge sockets it plugs into and the rails it forks into across a superset's
//  horizontally paged exercises.
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
    /// Height of the band above (and below) a superset's pages where the fork/merge rails
    /// and their drops into the bulges are drawn.
    static let railZoneHeight: CGFloat = 16
    /// Horizontal inset of a snapped superset page: pages are this much narrower than the
    /// column on each side, so the first page still sits flush with the list's leading edge
    /// while the neighbour peeks. Keeps every page center inside the fixed trunk's x, so the
    /// trunk always meets the rail's straight middle.
    static let pageInset: CGFloat = 24
    static let pageSpacing: CGFloat = 12

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

// MARK: - Superset rails

extension View {
    /// Wraps a superset's paged content in the thread's fork (above) and merge (below) rails,
    /// reserving their bands as padding. Applied to the scroll CONTENT, so the rails move with
    /// the pages while the list's trunk stays fixed — that's what keeps the T-junction square
    /// at every scroll position. A rail is omitted when nothing feeds it: no group before the
    /// superset means no fork, none after means no merge.
    func supersetThreadRails(pageCount: Int, showsFork: Bool, showsMerge: Bool) -> some View {
        padding(.top, showsFork ? SetGroupThread.railZoneHeight : 0)
            .padding(.bottom, showsMerge ? SetGroupThread.railZoneHeight : 0)
            .overlay(alignment: .top) {
                if showsFork {
                    supersetRail(pageCount: pageCount, flipped: false)
                }
            }
            .overlay(alignment: .bottom) {
                if showsMerge {
                    supersetRail(pageCount: pageCount, flipped: true)
                }
            }
    }

    private func supersetRail(pageCount: Int, flipped: Bool) -> some View {
        SupersetRailShape(
            pageCount: pageCount,
            pageSpacing: SetGroupThread.pageSpacing,
            flipped: flipped
        )
        .stroke(style: StrokeStyle(lineWidth: SetGroupThread.lineWidth, lineCap: .round))
        .foregroundStyle(Color.threadLine)
        .frame(height: SetGroupThread.railZoneHeight)
    }
}

/// The thread's horizontal rail across a superset's pages, drawn in the band above (or,
/// flipped, below) them and scrolling with them: rounded elbows turn down into the first and
/// last page's center, straight drops serve any pages in between. Page centers are derived
/// from the band's own width, so the shape needs no measured geometry.
struct SupersetRailShape: Shape {
    let pageCount: Int
    let pageSpacing: CGFloat
    var flipped: Bool = false
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard pageCount > 0 else { return path }
        let pageWidth = (rect.width - CGFloat(pageCount - 1) * pageSpacing) / CGFloat(pageCount)
        let centers = (0 ..< pageCount).map { pageWidth / 2 + CGFloat($0) * (pageWidth + pageSpacing) }
        let railY: CGFloat = SetGroupThread.lineWidth / 2
        // Verticals overshoot the band by a couple of points into the neighboring fill (bulge
        // below, card above once flipped) so no join can open an antialiasing hairline.
        let overshoot = rect.height + SetGroupThread.jointOverlap
        guard let first = centers.first, let last = centers.last, pageCount > 1 else {
            path.move(to: CGPoint(x: centers[0], y: 0))
            path.addLine(to: CGPoint(x: centers[0], y: overshoot))
            return flipped ? path.flippedVertically(height: rect.height) : path
        }
        path.move(to: CGPoint(x: first, y: overshoot))
        path.addLine(to: CGPoint(x: first, y: railY + cornerRadius))
        path.addArc(
            center: CGPoint(x: first + cornerRadius, y: railY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.addLine(to: CGPoint(x: last - cornerRadius, y: railY))
        path.addArc(
            center: CGPoint(x: last - cornerRadius, y: railY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: last, y: overshoot))
        for center in centers.dropFirst().dropLast() {
            path.move(to: CGPoint(x: center, y: railY))
            path.addLine(to: CGPoint(x: center, y: overshoot))
        }
        return flipped ? path.flippedVertically(height: rect.height) : path
    }
}

private extension Path {
    func flippedVertically(height: CGFloat) -> Path {
        applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height))
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
