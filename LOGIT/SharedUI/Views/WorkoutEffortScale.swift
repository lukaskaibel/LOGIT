//
//  WorkoutEffortScale.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 23.08.26.
//

import SwiftUI

/// The interactive 1…10 effort picker: ten bars rising left to right, filled up to the current
/// rating. Tap a bar or drag across them — the drag is what makes it feel like a dial rather than
/// ten buttons, and it is why the whole row (not each bar) owns the gesture.
///
/// **The scale is deliberately colourless.** In LOGIT a colour *means a muscle group*, everywhere:
/// the donut, the set-group rails, the balance chart. An effort ramp painted teal-to-rose would
/// spend that vocabulary on something that has nothing to do with muscles, and a 7 would read as
/// "shoulders". So the bars are neutral grey and only the chosen one carries `tint` — the
/// workout's own muscle-group gradient, the same one the Finish button wears.
struct WorkoutEffortScale: View {
    @Binding var score: Int?

    /// The selected bar's fill. The workout's muscle-group gradient at every call site; it falls
    /// back to the accent colour on its own for a workout with no muscle groups yet.
    var tint: AnyShapeStyle

    var barHeight: CGFloat = 92

    /// Set while a finger is down so the haptic only fires when the value actually changes.
    @State private var lastHapticScore: Int?

    private let spacing: CGFloat = 5

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                HStack(spacing: spacing) {
                    ForEach(WorkoutEffort.scoreRange, id: \.self) { value in
                        bar(for: value)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gestureValue in
                            select(atX: gestureValue.location.x, width: geometry.size.width)
                        }
                        .onEnded { _ in lastHapticScore = nil }
                )
            }
            .frame(height: barHeight)
            HStack(spacing: spacing) {
                ForEach(WorkoutEffort.scoreRange, id: \.self) { value in
                    Text("\(value)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(value == score ? Color.label : Color.tertiaryLabel)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("effortScale")
        .accessibilityLabel(NSLocalizedString("effort", comment: ""))
        .accessibilityValue(
            score.map { "\($0)" } ?? NSLocalizedString("notRated", comment: "")
        )
        .accessibilityAdjustableAction { direction in
            let current = score ?? 0
            switch direction {
            case .increment: score = min(current + 1, 10)
            case .decrement: score = max(current - 1, 1)
            default: break
            }
        }
    }

    private func bar(for value: Int) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fill(for: value))
            .frame(maxWidth: .infinity)
            .frame(height: barHeight * heightFraction(for: value), alignment: .bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Three steps, only one of them coloured: the bars past the rating are a faint track, the
    /// ones it reached are a plain grey fill, and the rating itself takes the gradient. Keeping
    /// the reached bars filled preserves the "level" reading that a single lit bar would lose.
    private func fill(for value: Int) -> AnyShapeStyle {
        guard let score else { return AnyShapeStyle(Color.secondaryFill) }
        if value == score {
            return tint
        }
        return AnyShapeStyle(value < score ? Color.label.opacity(0.3) : Color.secondaryFill)
    }

    /// 22 % for a 1 up to the full height for a 10 — the ramp reads as "more" even before the
    /// fill does, which is what carries the magnitude now that colour no longer can.
    private func heightFraction(for value: Int) -> CGFloat {
        0.22 + 0.78 * CGFloat(value - 1) / 9
    }

    private func select(atX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let step = width / CGFloat(WorkoutEffort.scoreRange.count)
        let raw = Int(x / step) + 1
        let clamped = min(max(raw, 1), 10)
        guard clamped != lastHapticScore else { return }
        lastHapticScore = clamped
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            score = clamped
        }
    }
}

/// The read-only echo of the scale, small enough to sit at the trailing edge of a row. Same rule:
/// grey bars, the rating itself in the workout's gradient.
struct WorkoutEffortMiniBars: View {
    let score: Int?
    let tint: AnyShapeStyle

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(WorkoutEffort.scoreRange, id: \.self) { value in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(fill(for: value))
                    .frame(width: 4, height: 20 * (0.22 + 0.78 * CGFloat(value - 1) / 9))
            }
        }
        .frame(height: 20, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private func fill(for value: Int) -> AnyShapeStyle {
        guard let score else { return AnyShapeStyle(Color.secondaryFill) }
        if value == score { return tint }
        return AnyShapeStyle(value < score ? Color.label.opacity(0.3) : Color.secondaryFill)
    }
}

/// "Effort — Hard · 7" plus the mini ramp. The shared row for the detail and editor screens; the
/// caller decides whether tapping it does anything.
struct WorkoutEffortRow: View {
    let score: Int?
    let tint: AnyShapeStyle

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("effort", comment: ""))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.secondaryLabel)
                if let score, let effort = WorkoutEffort(score: score) {
                    HStack(spacing: 5) {
                        Text(effort.name)
                        Text("·")
                            .foregroundStyle(Color.secondaryLabel)
                        Text("\(score)")
                            .monospacedDigit()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                } else {
                    Text(NSLocalizedString("notRated", comment: ""))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.secondaryLabel)
                }
            }
            Spacer(minLength: 0)
            WorkoutEffortMiniBars(score: score, tint: tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("effortRow")
    }
}

#Preview {
    struct Wrapper: View {
        @State private var score: Int? = 7
        private let tint = AnyShapeStyle(
            LinearGradient(
                colors: [MuscleGroup.chest.color, MuscleGroup.shoulders.color],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        var body: some View {
            VStack(spacing: 30) {
                WorkoutEffortScale(score: $score, tint: tint)
                WorkoutEffortRow(score: score, tint: tint)
                WorkoutEffortRow(score: nil, tint: tint)
            }
            .padding()
        }
    }
    return Wrapper()
}
