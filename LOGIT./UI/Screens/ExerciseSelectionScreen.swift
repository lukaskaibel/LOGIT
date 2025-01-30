//
//  ExerciseSelectionScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.12.21.
//

import CoreData
import SwiftUI

struct ExerciseSelectionScreen: View {

    enum SheetType: Identifiable {
        case addExercise
        case exerciseDetail(exercise: Exercise)
        var id: Int {
            switch self {
            case .addExercise: return 0
            case .exerciseDetail: return 1
            }
        }
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss

    // MARK: - State

    @State private var searchedText: String = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var sheetType: SheetType?
    @State private var isShowingNoExercisesTip = false

    // MARK: - Binding

    let selectedExercise: Exercise?
    let setExercise: (Exercise) -> Void
    let forSecondary: Bool

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Exercise.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: ExercisePredicateFactory.getExercises(
                nameIncluding: searchedText,
                withMuscleGroup: selectedMuscleGroup
            )
        ) { exercises in
            let groupedExercises = Dictionary(grouping: exercises, by: {
                $0.name?.prefix(1) ?? ""
            }).sorted { $0.key < $1.key }
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isShowingNoExercisesTip {
                        TipView(
                            title: NSLocalizedString("noExercisesTip", comment: ""),
                            description: NSLocalizedString("noExercisesTipDescription", comment: ""),
                            buttonAction: .init(
                                title: NSLocalizedString("createExercise", comment: ""),
                                action: { sheetType = .addExercise }
                            ),
                            isShown: $isShowingNoExercisesTip
                        )
                        .padding(CELL_PADDING)
                        .tileStyle()
                        .padding(.horizontal)
                    }
                    ForEach(groupedExercises, id:\.0) { key, exercises in
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(key)
                                .textCase(.uppercase)
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                ForEach(exercises) { exercise in
                                    HStack {
                                        ExerciseCell(exercise: exercise)
                                        Spacer()
                                        if exercise == selectedExercise {
                                            Image(systemName: "checkmark")
                                                .fontWeight(.semibold)
                                                .foregroundColor(exercise.muscleGroup?.color)
                                        }
                                        Button {
                                            sheetType = .exerciseDetail(exercise: exercise)
                                        } label: {
                                            Image(systemName: "info.circle")
                                                .font(.title3)
                                        }
                                        .buttonStyle(TileButtonStyle())
                                        .foregroundColor(exercise.muscleGroup?.color)
                                    }
                                    .padding(CELL_PADDING)
                                    .tileStyle()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        setExercise(exercise)
                                        dismiss()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .emptyPlaceholder(groupedExercises) {
                        Text(NSLocalizedString("noExercises", comment: ""))
                    }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .edgesIgnoringSafeArea(.bottom)
            .navigationTitle(
                NSLocalizedString("choose\(forSecondary ? "Secondary" : "")Exercise", comment: "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isShowingNoExercisesTip = exercises.isEmpty
            }
            .searchable(
                text: $searchedText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("searchExercises", comment: "")
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: {
                            sheetType = .addExercise
                        },
                        label: {
                            Image(systemName: "plus")
                        }
                    )
                }
            }
            .sheet(item: $sheetType) { type in
                switch type {
                case .addExercise:
                    ExerciseEditScreen(
                        onEditFinished: {
                            setExercise($0)
                            dismiss()
                        },
                        initialMuscleGroup: selectedMuscleGroup ?? .chest
                    )
                case let .exerciseDetail(exercise):
                    NavigationStack {
                        ExerciseDetailScreen(exercise: exercise)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(NSLocalizedString("dismiss", comment: "")) {
                                        sheetType = nil
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

}

struct ExerciseSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExerciseSelectionScreen(
                selectedExercise: nil,
                setExercise: { _ in },
                forSecondary: false
            )
        }
        .previewEnvironmentObjects()
    }
}
