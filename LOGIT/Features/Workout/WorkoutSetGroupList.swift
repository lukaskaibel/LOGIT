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
    var reduceShadow: Bool = false

    // MARK: - State

    @State var isReordering = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ReorderableForEach(
                $workout.setGroups,
                canReorder: canReorder,
                isReordering: $isReordering
            ) { setGroup in
                VStack(spacing: 0) {
                    WorkoutSetGroupCell(
                        setGroup: setGroup,
                        focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                        isReordering: $isReordering,
                        supplementaryText: nil
                    )
                    .shadow(color: .black.opacity(reduceShadow ? 0.5 : 1.0), radius: 5)
                    .zIndex(1)
                    if workout.setGroups.last != setGroup {
                        Rectangle()
                            .foregroundStyle(.secondary)
                            .frame(width: 3, height: SECTION_SPACING)
                            .zIndex(0)
                    }
                }
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
            canReorder: true
        )
    }
}

struct WorkoutSetGroupList_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            PreviewWrapperView()
                .padding()
        }
        .previewEnvironmentObjects()
    }
}
