//
//  ExerciseCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.10.22.
//

import SwiftUI

struct ExerciseCell: View {
    
    // MARK: - Environment
    
    @EnvironmentObject var database: Database
    
    // MARK: - Parameters
    
    @StateObject var exercise: Exercise
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(exercise.name ?? "")
                .font(.body.weight(.bold))
                .foregroundColor(.primary)
            Text(exercise.muscleGroup?.description ?? "")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(exercise.muscleGroup?.color.gradient ?? Color.primary.gradient)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        ScrollView {
            ExerciseCell(exercise: database.getExercises().first!)
                .padding(CELL_PADDING)
                .tileStyle()
        }
    }
}

struct ExerciseCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
