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
