//
//  BodyMapFigure.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// A body region that can be highlighted on the shared `BodyMapFigure`. Maps onto a `MuscleGroup`
/// (muscle detail) and — as a fast-follow for the measurement screens — onto a
/// `LengthMeasurementEntryType`.
enum BodyRegion {
    case chest, back, shoulders, abs, arms, legs, cardio

    init(_ muscleGroup: MuscleGroup) {
        switch muscleGroup {
        case .chest: self = .chest
        case .back: self = .back
        case .shoulders: self = .shoulders
        case .abdominals: self = .abs
        case .biceps, .triceps: self = .arms
        case .legs: self = .legs
        case .cardio: self = .cardio
        }
    }

    init(_ length: LengthMeasurementEntryType) {
        switch length {
        case .neck, .shoulders: self = .shoulders
        case .chest: self = .chest
        case .bicepsLeft, .bicepsRight, .forearmLeft, .forearmRight: self = .arms
        case .waist, .hips: self = .abs
        case .thighLeft, .thighRight, .calfLeft, .calfRight: self = .legs
        }
    }
}

/// The one reusable silhouette — an open-stance pictogram (head, torso, angled arms, parted legs)
/// hand-ported from `figure-lab.html`'s 100×200 coordinate space to SwiftUI `Path`s, scaled to fit.
/// The base draws muted grey; the highlighted region overlays in the supplied colour (cardio fills a
/// heart over the chest). Decorative on the muscle-detail header; an `accessibilityLabel` for the
/// measurement screens to come.
struct BodyMapFigure: View {
    let highlighted: BodyRegion?
    var color: Color = .accentColor
    /// The un-highlighted silhouette colour — overridden on the muscle-detail header, where a dark
    /// silhouette reads on the light muscle gradient.
    var baseColor: Color = Color(red: 0.227, green: 0.227, blue: 0.235) // #3a3a3c
    var accessibilityLabel: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width / 100, geometry.size.height / 200)
            ZStack(alignment: .topLeading) {
                base(scale: s)
                highlight(scale: s)
            }
            .frame(width: 100 * s, height: 200 * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel ?? "")
    }

    // MARK: - Base

    private func base(scale s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            segment((45, 114), (37, 185), width: 16, scale: s, color: baseColor)
            segment((55, 114), (63, 185), width: 16, scale: s, color: baseColor)
            segment((34, 61), (23, 106), width: 13, scale: s, color: baseColor)
            segment((66, 61), (77, 106), width: 13, scale: s, color: baseColor)
            torso(scale: s).fill(baseColor)
            ellipse(cx: 50, cy: 24, r: 16, scale: s).fill(baseColor)
        }
    }

    // MARK: - Highlight

    @ViewBuilder
    private func highlight(scale s: CGFloat) -> some View {
        switch highlighted {
        case .chest:
            roundedRect(37, 55, 26, 20, r: 10, scale: s).fill(color)
        case .back:
            roundedRect(37, 55, 26, 35, r: 12, scale: s).fill(color)
        case .shoulders:
            roundedRect(35, 51, 30, 11, r: 5.5, scale: s).fill(color)
        case .abs:
            roundedRect(40, 79, 20, 18, r: 8, scale: s).fill(color)
        case .arms:
            ZStack(alignment: .topLeading) {
                segment((31.5, 71), (28.5, 84), width: 9, scale: s, color: color)
                segment((68.5, 71), (71.5, 84), width: 9, scale: s, color: color)
            }
        case .legs:
            ZStack(alignment: .topLeading) {
                segment((44.4, 120), (37.5, 181), width: 12, scale: s, color: color)
                segment((55.6, 120), (62.5, 181), width: 12, scale: s, color: color)
            }
        case .cardio:
            Image(systemName: "heart.fill")
                .font(.system(size: 22 * s))
                .foregroundStyle(color)
                .position(x: 50 * s, y: 66 * s)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Shape builders (100×200 space)

    private func segment(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), width: CGFloat, scale s: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: a.0 * s, y: a.1 * s))
            path.addLine(to: CGPoint(x: b.0 * s, y: b.1 * s))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width * s, lineCap: .round))
    }

    private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat, scale s: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerSize: CGSize(width: r * s, height: r * s))
    }

    private func ellipse(cx: CGFloat, cy: CGFloat, r: CGFloat, scale s: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
    }

    private func torso(scale s: CGFloat) -> Path {
        Path { path in
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            path.move(to: p(30, 64))
            path.addQuadCurve(to: p(46, 47), control: p(30, 49))
            path.addLine(to: p(54, 47))
            path.addQuadCurve(to: p(70, 64), control: p(70, 49))
            path.addLine(to: p(67, 103))
            path.addQuadCurve(to: p(50, 114), control: p(66, 114))
            path.addQuadCurve(to: p(33, 103), control: p(34, 114))
            path.closeSubpath()
        }
    }
}

#Preview {
    HStack(spacing: 14) {
        BodyMapFigure(highlighted: nil)
        BodyMapFigure(highlighted: .chest, color: MuscleGroup.chest.color)
        BodyMapFigure(highlighted: .legs, color: MuscleGroup.legs.color)
        BodyMapFigure(highlighted: .arms, color: MuscleGroup.biceps.color)
        BodyMapFigure(highlighted: .cardio, color: MuscleGroup.cardio.color)
    }
    .frame(height: 150)
    .padding()
}
