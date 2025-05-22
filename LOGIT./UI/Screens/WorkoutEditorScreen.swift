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
    
    @State private var cancellable: AnyCancellable?
    @FocusState private var focusedTextField: TextFieldType?
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isRenamingWorkout = false
    @State private var focusedIntegerFieldIndex: IntegerField.Index?
    @State private var isEditingStartEndDate = false

    
    // MARK: - Parameters
    
    @StateObject var workout: Workout
    let isAddingNewWorkout: Bool
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            if isRenamingWorkout {
                HStack {
                    TextField(
                        Workout.getStandardName(for: workout.date ?? .now),
                        text: workoutName
                    )
                    .focused($focusedTextField, equals: .workoutName)
                    .onChange(of: focusedTextField) {
                        if focusedTextField != .workoutName {
                            withAnimation {
                                isRenamingWorkout = false
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .fontWeight(.bold)
                    .onSubmit {
                        focusedTextField = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isRenamingWorkout = false
                        }
                        workout.name = workout.name?.isEmpty ?? true ? Workout.getStandardName(for: workout.date ?? .now) : workout.name
                    }
                    .submitLabel(.done)
                    if !(workout.name?.isEmpty ?? true) {
                        Button {
                            workout.name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.secondaryLabel)
                                .font(.body)
                        }
                    }
                }
                .padding(10)
                .background(Color.secondaryBackground)
                .cornerRadius(10)
                .padding(10)
            }
            ScrollViewReader { scrollable in
                ScrollView {
                    VStack(spacing: SECTION_SPACING) {
                        VStack(spacing: CELL_SPACING) {
                            WorkoutSetGroupList(
                                workout: workout,
                                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                                canReorder: true,
                                reduceShadow: true
                            )
                            .padding(.bottom, UIScreen.main.bounds.height * (exerciseSelectionPresentationDetent == .medium ? 0.5 : BOTTOM_SHEET_SMALL))
                            .id(1)
                            .emptyPlaceholder(workout.setGroups) {
                                Text(NSLocalizedString("addExercisesFromBelow", comment: ""))
                                    .foregroundStyle(Color.secondaryLabel)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .padding(.top, 30)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                .sheet(isPresented: .constant(true)) {
                    NavigationView {
                        ExerciseSelectionScreen(
                            selectedExercise: nil,
                            setExercise: { exercise in
                                database.newWorkoutSetGroup(
                                    createFirstSetAutomatically: true,
                                    exercise: exercise,
                                    workout: workout
                                )
                            },
                            forSecondary: false,
                            presentationDetentSelection: $exerciseSelectionPresentationDetent
                        )
                        .padding(.top)
                        .toolbar {
                            if exerciseSelectionPresentationDetent == .fraction(BOTTOM_SHEET_SMALL) {
                                ToolbarItemGroup(placement: .bottomBar) {
                                    Spacer()
                                    Button {
                                        database.undo()
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .disabled(!database.canUndo)
                                    Spacer()
                                    Button {
                                        database.redo()
                                    } label: {
                                        Image(systemName: "arrow.uturn.forward")
                                    }
                                    .disabled(!database.canRedo)
                                    Spacer()
                                }
                            }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                    }
                    .presentationDetents([.fraction(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                    .detentableBottomSheetStyle()
                    .sheet(isPresented: $isEditingStartEndDate) {
                        VStack(spacing: 30) {
                            HStack {
                                Text(NSLocalizedString("editTime", comment: ""))
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                                Button {
                                    isEditingStartEndDate = false
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.body.weight(.bold))
                                        .foregroundColor(Color.secondaryLabel)
                                        .padding(8)
                                        .background(Color.fill)
                                        .clipShape(Circle())
                                }
                            }
                            VStack(spacing: 15) {
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
                                HStack {
                                    Label(NSLocalizedString("duration", comment: ""), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                    Spacer()
                                    Text(workoutDurationString)
                                        .padding(.trailing)
                                }
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding()
                        .presentationDetents([.fraction(0.35)])
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isRenamingWorkout)
            .interactiveDismissDisabled(true)
            .presentationBackground(Color.background)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedTextField = .workoutName
                            }
                            isRenamingWorkout = true
                            exerciseSelectionPresentationDetent = .fraction(BOTTOM_SHEET_SMALL)
                        } label: {
                            Label(NSLocalizedString("rename", comment: ""), systemImage: "pencil")
                        }
                        Button {
                            isEditingStartEndDate = true
                        } label: {
                            Label(NSLocalizedString("editDateTime", comment: ""), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    } label: {
                        HStack {
                            VStack {
                                Text(workout.name ?? "")
                                    .foregroundStyle(Color.label)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(workout.date?.formatted(.dateTime.day().month().year()) ?? "")
                                    Text("•")
                                    Text(workoutDurationString)
                                }
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                            }
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                        }
                    }
                }
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
                if focusedTextField != .workoutName {
                    ToolbarItemGroup(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button {
                                focusedIntegerFieldIndex = nil
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                            }
                        }
                    }
                }
            }
            .onAppear {
                if workout.date == nil {
                    workout.date = .now
                    workout.endDate = .now.addingTimeInterval(1000)
                }
                refreshOnChange()
                exerciseSelectionPresentationDetent = workout.isEmpty ? .medium : .fraction(BOTTOM_SHEET_SMALL)
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
        Rectangle()
            .sheet(isPresented: .constant(true)) {
                NavigationView {
                    WorkoutEditorScreen(workout: database.testWorkout, isAddingNewWorkout: true)
                }
                .presentationBackground(Color.black)
            }
    }
}

#Preview {
    PreviewWrapperView()
        .previewEnvironmentObjects()
}
