//
//  MuscleBalanceBar.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The shared "balance vs target" diverging bar (`balance-row-lab.html` variant 1): a centred white
/// tick marks the target, and a capsule in the muscle's own colour grows left (under target) or right
/// (over target) by how far the actual share sits from it — never amber/red, since muscle hues are
/// identity, not warning. The target percent is printed above the tick; the signed deviation sits to
/// the right. Shared by the Summary Muscle Balance tile, the Muscle Groups overview list, and the
/// muscle-detail target-share tile.
struct MuscleBalanceBar: View {
    let entry: MuscleBalanceEntry
    /// Leading muscle name + colour dot — on in the lists, off where a row already names the group.
    var showsName: Bool = false
    /// Trailing signed deviation label.
    var showsDelta: Bool = true

    /// A deviation of this many percentage points fills half the track; beyond it the capsule is
    /// clamped to the half-track. 10pt → half.
    private static let half: Double = 10

    private var color: Color { entry.muscleGroup.color }
    private var deviation: Int { entry.deviation }
    private var fillFraction: Double { min(Double(abs(deviation)) / Self.half, 1) * 0.5 }

    var body: some View {
        HStack(spacing: 10) {
            if showsName {
                name
            }
            VStack(spacing: 5) {
                Text("\(entry.targetPercent)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                bar
            }
            if showsDelta {
                delta
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var name: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(entry.muscleGroup.description)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
                Capsule()
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
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(width: 32, alignment: .trailing)
    }

    private var deltaText: String {
        if deviation == 0 { return "±0" }
        return deviation > 0 ? "+\(deviation)" : "−\(abs(deviation))"
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
        MuscleBalanceBar(
            entry: MuscleBalanceEntry(muscleGroup: .chest, setCount: 47, actualPercent: 24, targetPercent: 16),
            showsName: true
        )
        MuscleBalanceBar(
            entry: MuscleBalanceEntry(muscleGroup: .legs, setCount: 18, actualPercent: 9, targetPercent: 20),
            showsName: true
        )
        MuscleBalanceBar(
            entry: MuscleBalanceEntry(muscleGroup: .back, setCount: 30, actualPercent: 18, targetPercent: 18),
            showsName: true
        )
    }
    .padding()
}
