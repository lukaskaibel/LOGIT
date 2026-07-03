//
//  MuscleBalanceBar.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The shared "balance vs target" diverging bar: a centred white tick marks the target, and a fill in
/// the muscle's own colour grows out of it — left when under target, right when over — by how far the
/// actual share sits from it. The fill is flat on the side that touches the tick and rounded only at
/// its outer end, so it visibly grows out of the target. The target percent sits above the tick; the
/// signed deviation to the right. Never amber/red — muscle hues are identity, not warning. Shared by
/// the Summary Muscle Balance tile, the Muscle Groups overview sections, and the single-muscle
/// detail's target-share tile.
struct MuscleBalanceBar: View {
    let entry: MuscleBalanceEntry
    /// Leading muscle name in its colour — on in the lists, off where a row already names the group.
    var showsName: Bool = false
    /// Trailing signed deviation label.
    var showsDelta: Bool = true

    /// A deviation of this many percentage points fills half the track; beyond it the fill clamps.
    private static let half: Double = 10

    private var color: Color { entry.muscleGroup.color }
    private var deviation: Int { entry.deviation }
    private var fillFraction: Double { min(Double(abs(deviation)) / Self.half, 1) * 0.5 }

    var body: some View {
        HStack(spacing: 10) {
            if showsName { name }
            VStack(spacing: 5) {
                Text("\(entry.targetPercent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                bar
            }
            if showsDelta { delta }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var name: some View {
        Text(entry.muscleGroup.description)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 78, alignment: .leading)
    }

    private var bar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fillWidth = width * fillFraction
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 2)
                // Flat against the tick, rounded only at the outer end — the fill grows out of the
                // target rather than floating beside it.
                UnevenRoundedRectangle(
                    topLeadingRadius: deviation < 0 ? 4 : 0,
                    bottomLeadingRadius: deviation < 0 ? 4 : 0,
                    bottomTrailingRadius: deviation > 0 ? 4 : 0,
                    topTrailingRadius: deviation > 0 ? 4 : 0
                )
                .fill(color)
                .frame(width: fillWidth, height: 9)
                .offset(x: deviation >= 0 ? fillWidth / 2 : -fillWidth / 2)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: 15)
            }
            .frame(width: width, height: 15)
        }
        .frame(height: 15)
    }

    private var delta: some View {
        Text(deltaText)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .frame(width: 44, alignment: .trailing)
    }

    private var deltaText: String {
        if deviation == 0 { return "±0%" }
        return deviation > 0 ? "+\(deviation)%" : "−\(abs(deviation))%"
    }

    private var accessibilityLabel: Text {
        Text(
            String(
                format: NSLocalizedString("muscleBalanceBarA11y", comment: ""),
                entry.muscleGroup.description,
                entry.actualPercent,
                entry.targetPercent
            )
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        MuscleBalanceBar(entry: MuscleBalanceEntry(muscleGroup: .legs, setCount: 17, actualPercent: 13, targetPercent: 20), showsName: true)
        MuscleBalanceBar(entry: MuscleBalanceEntry(muscleGroup: .chest, setCount: 30, actualPercent: 23, targetPercent: 16), showsName: true)
        MuscleBalanceBar(entry: MuscleBalanceEntry(muscleGroup: .back, setCount: 24, actualPercent: 18, targetPercent: 18), showsName: true)
    }
    .padding()
    .preferredColorScheme(.dark)
}
