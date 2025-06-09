//
//  MuscleGroupSelector.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 21.04.22.
//

import SwiftUI

struct MuscleGroupSelector: View {
    @Binding var selectedMuscleGroup: MuscleGroup?
    let muscleGroups: [MuscleGroup]
    let canBeNil: Bool
    let animation: Bool

    init(
        selectedMuscleGroup: Binding<MuscleGroup?>,
        from muscleGroups: [MuscleGroup] = MuscleGroup.allCases,
        canBeNil: Bool = true,
        withAnimation: Bool = false
    ) {
        _selectedMuscleGroup = selectedMuscleGroup
        self.muscleGroups = muscleGroups
        self.canBeNil = canBeNil
        animation = withAnimation
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if canBeNil {
                    Button(NSLocalizedString("all", comment: "")) {
                        if animation {
                            withAnimation {
                                selectedMuscleGroup = nil
                            }
                        } else {
                            selectedMuscleGroup = nil
                        }
                    }
                    .buttonStyle(CapsuleButtonStyle(isSelected: selectedMuscleGroup == nil))
                }
                ForEach(muscleGroups) { muscleGroup in
                    Button(muscleGroup.description) {
                        if animation {
                            withAnimation {
                                selectedMuscleGroup = muscleGroup
                            }
                        } else {
                            selectedMuscleGroup = muscleGroup
                        }
                    }
                    .buttonStyle(
                        CapsuleButtonStyle(
                            color: muscleGroup.color,
                            isSelected: selectedMuscleGroup == muscleGroup
                        )
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

struct MuscleGroupSelector_Previews: PreviewProvider {
    static var previews: some View {
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest))
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest), from: [.chest, .back])
        MuscleGroupSelector(selectedMuscleGroup: .constant(.chest), from: [])
    }
}
