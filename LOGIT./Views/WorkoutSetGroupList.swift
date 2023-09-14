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
    @Binding var sheetType: WorkoutRecorderScreen.SheetType?
    let canReorder: Bool
    
    // MARK: - State
    
    @State var isReordering = false
    
    // MARK: - Body

    var body: some View {
        VStack(spacing: SECTION_SPACING) {
            ReorderableForEach($workout.setGroups, canReorder: canReorder, isReordering: $isReordering, onOrderChanged: { database.refreshObjects() }) { setGroup in
                WorkoutSetGroupCell(
                    setGroup: setGroup,
                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                    sheetType: $sheetType,
                    isReordering: $isReordering,
                    supplementaryText:
                        "\(workout.setGroups.firstIndex(of: setGroup)! + 1) / \(workout.setGroups.count)  ·  \(setGroup.setType.description)"
                )
                .padding(CELL_PADDING)
                .tileStyle()
                .id(setGroup)
            }
        }
        .animation(.interactiveSpring())
    }
}

struct WorkoutSetGroupList_Previews: PreviewProvider {
    static var previews: some View {
        WorkoutSetGroupList(
            workout: Database.preview.getWorkouts().first!,
            focusedIntegerFieldIndex: .constant(nil),
            sheetType: .constant(nil),
            canReorder: false
        )
    }
}
