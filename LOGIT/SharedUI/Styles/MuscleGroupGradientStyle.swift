//
//  MuscleGroupGradientStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

struct MuscleGroupGradientModifier: ViewModifier {
    let muscleGroups: [MuscleGroup]

    func body(content: Content) -> some View {
        content
            .foregroundStyle(
                .linearGradient(
                    colors: muscleGroups.isEmpty ? [.accentColor] : muscleGroups.map { $0.color },
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            )
    }
}

extension View {
    func muscleGroupGradientStyle(for muscleGroups: [MuscleGroup]) -> some View {
        modifier(MuscleGroupGradientModifier(muscleGroups: muscleGroups))
    }
}

extension Sequence where Element == MuscleGroup {
    /// The muscle-group gradient as a concrete `LinearGradient` value — the muscle colors in order,
    /// falling back to the accent color when there are none. For call sites that need a real
    /// `LinearGradient` rather than a type-erased style (e.g. `ComparisonBar`'s workout-themed fill);
    /// `gradientStyle()` wraps this for `ShapeStyle` call sites.
    func gradient(startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> LinearGradient {
        let colors = map(\.color)
        return LinearGradient(
            colors: colors.isEmpty ? [.accentColor] : colors,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    /// The muscle-group gradient as a `ShapeStyle` value — the value-typed counterpart to the
    /// `muscleGroupGradientStyle` foreground modifier — for tinting a `ProgressIndicatorPill`: the
    /// muscle colors left to right, falling back to the accent color when there are none. A single
    /// `Color` can't carry a multi-muscle workout's gradient, so the pills take an `AnyShapeStyle`.
    func gradientStyle(startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> AnyShapeStyle {
        AnyShapeStyle(gradient(startPoint: startPoint, endPoint: endPoint))
    }
}
