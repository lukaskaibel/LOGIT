//
//  WorkoutSetGroupList.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 29.07.23.
//

import SwiftUI

struct WorkoutSetGroupList: View {

    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - Parameters

    @ObservedObject var workout: Workout
    @Binding var focusedIntegerFieldIndex: IntegerField.Index?
    let canReorder: Bool

    // MARK: - State

    @State var isReordering = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: SECTION_SPACING) {
            ReorderableForEach(
                $workout.setGroups,
                canReorder: canReorder,
                isReordering: $isReordering
            ) { setGroup in
                WorkoutSetGroupCell(
                    setGroup: setGroup,
                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                    isReordering: $isReordering,
                    supplementaryText:
                        "\(workout.setGroups.firstIndex(of: setGroup)! + 1) / \(workout.setGroups.count)  ·  \(setGroup.setType.description)"
                )
                .padding(CELL_PADDING)
                .tileStyle()
                .transition(.scale)
                .id(setGroup)
            }
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        WorkoutSetGroupList(
            workout: database.testWorkout,
            focusedIntegerFieldIndex: .constant(nil),
            canReorder: false
        )
    }
}

struct WorkoutSetGroupList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
    }
}
