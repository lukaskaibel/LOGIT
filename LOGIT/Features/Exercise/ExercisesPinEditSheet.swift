//
//  ExercisesPinEditSheet.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.11.24.
//

import SwiftUI

struct ExercisesPinEditSheet: View {
    @Binding var pinnedTiles: [PinnedExerciseTile]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var database: Database
    
    @State private var editMode: EditMode = .active
    @State private var expandedExerciseIDs: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pinnedTiles.enumerated()), id: \.offset) { index, pinnedTile in
                        if let exercise = database.getExercise(byID: pinnedTile.exerciseID) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name ?? "")
                                    Text(pinnedTile.tileType.title)
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                                Spacer()
                                if let muscleGroup = exercise.muscleGroup {
                                    Text(muscleGroup.description)
                                        .font(.footnote)
                                        .foregroundStyle(Color.secondaryLabel)
                                }
                            }
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } header: {
                    Text(NSLocalizedString("pinned", comment: ""))
                } footer: {
                    Text(NSLocalizedString("dragToReorder", comment: ""))
                }
                
                if !unpinnedExercises.isEmpty {
                    Section {
                        ForEach(unpinnedExercises, id: \.objectID) { exercise in
                            exerciseRow(for: exercise)
                        }
                    } header: {
                        Text(NSLocalizedString("unpinned", comment: ""))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(NSLocalizedString("pinExercises", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var allExercises: [Exercise] {
        database.getExercises(withNameIncluding: "", for: nil)
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
    
    private var unpinnedExercises: [Exercise] {
        allExercises.filter { exercise in
            guard let exerciseID = exercise.id else { return true }
            let pinnedTypesForExercise = pinnedTiles.filter { $0.exerciseID == exerciseID }
            // Show exercise if it has at least one unpinned tile type
            return pinnedTypesForExercise.count < ExerciseTileType.allCases.count
        }
    }
    
    @ViewBuilder
    private func exerciseRow(for exercise: Exercise) -> some View {
        if let exerciseID = exercise.id {
            let isExpanded = expandedExerciseIDs.contains(exerciseID)
            let unpinnedTileTypes = ExerciseTileType.allCases.filter { tileType in
                !pinnedTiles.contains(PinnedExerciseTile(exerciseID: exerciseID, tileType: tileType))
            }
            
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedExerciseIDs.remove(exerciseID)
                        } else {
                            expandedExerciseIDs.insert(exerciseID)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name ?? "")
                                .foregroundStyle(Color.label)
                            if let muscleGroup = exercise.muscleGroup {
                                Text(muscleGroup.description)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondaryLabel)
                            }
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(unpinnedTileTypes, id: \.self) { tileType in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    pinnedTiles.append(PinnedExerciseTile(exerciseID: exerciseID, tileType: tileType))
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(tileType.title)
                                        .foregroundStyle(Color.label)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.leading, 24)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        pinnedTiles.move(fromOffsets: source, toOffset: destination)
    }
    
    private func delete(at offsets: IndexSet) {
        pinnedTiles.remove(atOffsets: offsets)
    }
}

struct ExercisesPinEditSheet_Previews: PreviewProvider {
    static var previews: some View {
        ExercisesPinEditSheet(pinnedTiles: .constant([]))
            .previewEnvironmentObjects()
    }
}
