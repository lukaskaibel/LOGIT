//
//  TemplateWorkoutEditorView+TemplateSuperSetCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 28.05.22.
//

import SwiftUI

extension TemplateWorkoutEditorView {
    
    internal func TemplateSuperSetCell(for templateSuperSet: TemplateSuperSet) -> some View {
        VStack {
            HStack {
                Image(systemName: "1.circle")
                TemplateSetEntryView(repetitions: Binding(get: { templateSuperSet.repetitionsFirstExercise },
                                                          set: { templateSuperSet.repetitionsFirstExercise = $0 }),
                                     weight: Binding(get: { templateSuperSet.weightFirstExercise },
                                                     set: { templateSuperSet.weightFirstExercise = $0 }))
            }
            HStack {
                Image(systemName: "2.circle")
                TemplateSetEntryView(repetitions: Binding(get: { templateSuperSet.repetitionsSecondExercise },
                                                          set: { templateSuperSet.repetitionsSecondExercise = $0 }),
                                     weight: Binding(get: { templateSuperSet.weightSecondExercise },
                                                     set: { templateSuperSet.weightSecondExercise = $0 }))
            }
        }
    }
    
}
