//
//  WorkoutEditorScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 27.02.24.
//

import Combine
import SwiftUI

struct WorkoutEditorScreen: View {
    
    enum TextFieldType: Hashable {
        case workoutName, workoutSetEntry(index: IntegerField.Index)
    }
    
    // MARK: - Environment
    
    @EnvironmentObject var database: Database
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    
    @State private var sheetType: WorkoutSetGroupList.SheetType? = nil
    @State private var cancellable: AnyCancellable?
    @FocusState private var focusedTextField: TextFieldType?
    
    // MARK: - Parameters
    
    @StateObject var workout: Workout
    let isAddingNewWorkout: Bool
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollable in
                ScrollView {
                    VStack(spacing: SECTION_SPACING) {
                        TextField(
                            Workout.getStandardName(for: workout.date ?? .now),
                            text: workoutName,
                            axis: .vertical
                        )
                        .font(.largeTitle.weight(.bold))
                        .focused($focusedTextField, equals: .workoutName)
                        .onChange(of: workout.name) { newValue in
                            if newValue?.last == "\n" {
                                workout.name?.removeLast()
                                focusedTextField = nil
                            }
                        }
                        .submitLabel(.done)
                        .lineLimit(2)
                        VStack {
                            DatePicker(
                                NSLocalizedString("start", comment: ""),
                                selection: workoutStart,
                                in: ...workoutEnd.wrappedValue,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            DatePicker(
                                NSLocalizedString("end", comment: ""),
                                selection: workoutEnd,
                                in: workoutStart.wrappedValue...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            Divider()
                                .padding(.vertical, 10)
                            HStack {
                                Text(NSLocalizedString("duration", comment: ""))
                                Spacer()
                                Text(workoutDurationString)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(CELL_PADDING)
                        .tileStyle()
                        VStack(spacing: SECTION_HEADER_SPACING) {
                            Text(NSLocalizedString("exercises", comment: ""))
                                .sectionHeaderStyle2()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: CELL_SPACING) {
                                WorkoutSetGroupList(
                                    workout: workout,
                                    focusedIntegerFieldIndex: focusedIntegerFieldIndex,
                                    sheetType: $sheetType,
                                    canReorder: true
                                )
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        HStack {
                                            Spacer()
                                            Button {
                                                focusedTextField = nil
                                            } label: {
                                                Image(systemName: "keyboard.chevron.compact.down")
                                            }
                                        }
                                    }
                                }
                                Button {
                                    sheetType = .exerciseSelection(
                                        exercise: nil,
                                        setExercise: { exercise in
                                            database.newWorkoutSetGroup(
                                                createFirstSetAutomatically: true,
                                                exercise: exercise,
                                                workout: workout
                                            )
                                            withAnimation {
                                                scrollable.scrollTo(1, anchor: .bottom)
                                            }
                                        },
                                        forSecondary: false
                                    )
                                } label: {
                                    Label(
                                        NSLocalizedString("addExercise", comment: ""),
                                        systemImage: "plus.circle.fill"
                                    )
                                }
                                .buttonStyle(BigButtonStyle())
                                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
                                .padding(.top, 30)
                                .id(1)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
            }
            .navigationTitle(NSLocalizedString(isAddingNewWorkout ? "addWorkout" : "editWorkout", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        if workout.name?.isEmpty ?? true || workout.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" == "", let date = workout.date {
                            workout.name = Workout.getStandardName(for: date)
                        }
                        database.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!canSaveWorkout)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        database.discardUnsavedChanges()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Text(
                        "\(workout.setGroups.count) \(NSLocalizedString("exercise\(workout.setGroups.count == 1 ? "" : "s")", comment: ""))"
                    )
                    .font(.caption)
                }
            }
            .sheet(item: $sheetType) { type in
                NavigationStack {
                    switch type {
                    case let .exerciseDetail(exercise):
                        ExerciseDetailScreen(exercise: exercise)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(NSLocalizedString("dismiss", comment: "")) {
                                        sheetType = nil
                                    }
                                }
                            }
                            .tag("detail")
                    case let .exerciseSelection(exercise, setExercise, forSecondary):
                        ExerciseSelectionScreen(
                            selectedExercise: exercise,
                            setExercise: setExercise,
                            forSecondary: forSecondary
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                                    sheetType = nil
                                }
                            }
                        }
                        .tag("selection")
                    }
                }
            }
            .onAppear {
                if workout.date == nil {
                    workout.date = .now
                    workout.endDate = .now.addingTimeInterval(1000)
                }
                refreshOnChange()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var workoutName: Binding<String> {
        Binding(get: { workout.name ?? "" }, set: { workout.name = $0 })
    }
    
    private var workoutStart: Binding<Date> {
        Binding(get: { workout.date ?? .now }, set: { workout.date = $0 })
    }
    
    private var workoutEnd: Binding<Date> {
        Binding(get: { workout.endDate ?? .now }, set: { workout.endDate = $0 })
    }
    
    private var workoutDurationString: String {
        guard let start = workout.date, let end = workout.endDate else { return "0:00" }
        let hours = Calendar.current.dateComponents([.hour], from: start, to: end).hour ?? 0
        let minutes =
            (Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0) % 60
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }
    
    private var canSaveWorkout: Bool {
        workout.date != nil && workout.endDate != nil && !workout.setGroups.isEmpty
    }
    
    private var focusedIntegerFieldIndex: Binding<IntegerField.Index?> {
        Binding(get: {
            switch focusedTextField {
            case .workoutName: return nil
            case let .workoutSetEntry(index): return index
            default: return nil
            }
        }, set: {
            focusedTextField = $0 == nil ? nil : .workoutSetEntry(index: $0!)
        })
    }
    
    // MARK: - Autosave
    
    private func refreshOnChange() {
        cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: database.context)
            .sink { _ in
                self.workout.objectWillChange.send()
            }
    }
    
}


// MARK: - Preview

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        NavigationView {
            WorkoutEditorScreen(workout: database.testWorkout, isAddingNewWorkout: true)
        }
    }
}

#Preview {
    PreviewWrapperView()
        .previewEnvironmentObjects()
}
