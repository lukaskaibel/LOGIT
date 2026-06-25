//
//  MuscleGroupGradientStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 30.07.23.
//

import SwiftUI

extension Sequence where Element == MuscleGroup {
    /// A gradient that reflects *how often* each muscle group occurs in the sequence — pass one
    /// element per set and the colours are weighted by set count, so a muscle group trained in
    /// more sets claims a proportionally wider, more prominent share of the gradient. The distinct
    /// colours are ordered around the spectrum (by hue) and each is anchored at the midpoint of its
    /// share, so neighbouring colours blend smoothly into one another instead of clashing. Falls
    /// back to the accent colour when the sequence is empty.
    ///
    /// This is the single source of muscle-group gradients in the app. Call sites that have the
    /// sets entered should prefer `Sequence<WorkoutSet>.muscleGroupGradient(...)`, which feeds this
    /// one muscle group per set so the set weighting takes effect.
    func weightedSpectrumGradient(
        startPoint: UnitPoint = .leading,
        endPoint: UnitPoint = .trailing
    ) -> LinearGradient {
        // Tally how often each muscle group occurs — with one element per set this is the number
        // of sets training each muscle group.
        var counts: [MuscleGroup: Int] = [:]
        for muscleGroup in self {
            counts[muscleGroup, default: 0] += 1
        }
        guard !counts.isEmpty else {
            return LinearGradient(colors: [.accentColor], startPoint: startPoint, endPoint: endPoint)
        }
        // Order the distinct colours around the spectrum (by hue, breaking ties deterministically)
        // so adjacent bands transition smoothly rather than jumping between unrelated hues.
        let ordered = counts.keys.sorted {
            $0.spectrumHue != $1.spectrumHue ? $0.spectrumHue < $1.spectrumHue : $0.rawValue < $1.rawValue
        }
        // Give each colour a share of the 0...1 range proportional to its tally, anchored at the
        // midpoint of that share — a heavier muscle group sits over, and dominates the blend across,
        // a wider stretch of the gradient.
        let total = Double(counts.values.reduce(0, +))
        var stops: [Gradient.Stop] = []
        var cumulative = 0.0
        for muscleGroup in ordered {
            let share = Double(counts[muscleGroup] ?? 0) / total
            stops.append(Gradient.Stop(color: muscleGroup.color, location: cumulative + share / 2))
            cumulative += share
        }
        return LinearGradient(stops: stops, startPoint: startPoint, endPoint: endPoint)
    }

    /// `weightedSpectrumGradient(...)` as a type-erased `ShapeStyle`, for the `AnyShapeStyle` call
    /// sites (e.g. tinting a `ProgressIndicatorPill`).
    func weightedSpectrumGradientStyle(
        startPoint: UnitPoint = .leading,
        endPoint: UnitPoint = .trailing
    ) -> AnyShapeStyle {
        AnyShapeStyle(weightedSpectrumGradient(startPoint: startPoint, endPoint: endPoint))
    }
}

extension Sequence where Element == WorkoutSet {
    /// The muscle-group gradient for the sets entered, weighted by how many sets train each muscle
    /// group — a muscle worked across more sets claims a larger, more prominent share — with the
    /// colours ordered around the spectrum so they transition smoothly into one another. Each set
    /// contributes its muscle group(s); super sets contribute both. Falls back to the accent colour
    /// when none of the sets have a muscle group. Built on
    /// `Sequence<MuscleGroup>.weightedSpectrumGradient(...)`, which does the actual work.
    func muscleGroupGradient(
        startPoint: UnitPoint = .leading,
        endPoint: UnitPoint = .trailing
    ) -> LinearGradient {
        flatMap { $0.setGroup?.muscleGroups ?? [] }
            .weightedSpectrumGradient(startPoint: startPoint, endPoint: endPoint)
    }

    /// `muscleGroupGradient(...)` as a type-erased `ShapeStyle`, for the `AnyShapeStyle` call sites.
    func muscleGroupGradientStyle(
        startPoint: UnitPoint = .leading,
        endPoint: UnitPoint = .trailing
    ) -> AnyShapeStyle {
        AnyShapeStyle(muscleGroupGradient(startPoint: startPoint, endPoint: endPoint))
    }
}

private extension MuscleGroup {
    /// The hue (0...1) of the muscle group's colour, used to order colours around the spectrum so a
    /// multi-colour gradient transitions smoothly. Derived from `color` itself, so the ordering
    /// stays correct if the palette is ever retuned.
    var spectrumHue: Double {
        var hue: CGFloat = 0
        UIColor(color).getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
        return Double(hue)
    }
}
