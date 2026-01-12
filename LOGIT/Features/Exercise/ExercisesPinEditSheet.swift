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
    @State private var searchText: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(pinnedTiles.enumerated()), id: \.offset) { index, pinnedTile in
                        if let exercise = database.getExercise(byID: pinnedTile.exerciseID) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.displayName)
                                Text(pinnedTile.tileType.title)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondaryLabel)
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
                        ForEach(filteredUnpinnedExercises, id: \.objectID) { exercise in
                            exerciseRow(for: exercise)
                        }
                    } header: {
                        Text(NSLocalizedString("unpinned", comment: ""))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .searchable(text: $searchText, prompt: NSLocalizedString("searchExercises", comment: ""))
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
            .sorted { $0.displayName < $1.displayName }
    }
    
    private var unpinnedExercises: [Exercise] {
        allExercises.filter { exercise in
            guard let exerciseID = exercise.id else { return true }
            let pinnedTypesForExercise = pinnedTiles.filter { $0.exerciseID == exerciseID }
            // Show exercise if it has at least one unpinned tile type
            return pinnedTypesForExercise.count < ExerciseTileType.allCases.count
        }
    }
    
    private var filteredUnpinnedExercises: [Exercise] {
        if searchText.isEmpty {
            return unpinnedExercises
        }
        return FuzzySearchService.shared.searchExercises(searchText, in: unpinnedExercises)
    }
    
    @ViewBuilder
    private func exerciseRow(for exercise: Exercise) -> some View {
        if let exerciseID = exercise.id {
            let unpinnedTileTypes = ExerciseTileType.allCases.filter { tileType in
                !pinnedTiles.contains(PinnedExerciseTile(exerciseID: exerciseID, tileType: tileType))
            }
            
            Menu {
                Section(exercise.displayName) {
                    ForEach(unpinnedTileTypes, id: \.self) { tileType in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                pinnedTiles.append(PinnedExerciseTile(exerciseID: exerciseID, tileType: tileType))
                            }
                        } label: {
                            Label(tileType.title, systemImage: "pin")
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                    Text(exercise.displayName)
                        .foregroundStyle(Color.label)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
