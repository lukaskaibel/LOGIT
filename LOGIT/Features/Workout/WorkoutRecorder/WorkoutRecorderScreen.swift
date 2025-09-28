//
//  WorkoutRecorderScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 24.02.22.
//

import Charts
import Combine
import CoreData
import SwiftUI
import UIKit

struct WorkoutRecorderScreen: View {
    // MARK: - AppStorage

    @AppStorage("preventAutoLock") var preventAutoLock: Bool = true

    // MARK: - Environment

    @Environment(\.goHome) var goHome
    @Environment(\.fullScreenDraggableCoverTopInset) var fullScreenDraggableCoverTopInset
    @Environment(\.fullScreenDraggableCoverIsDragging) var fullScreenDraggableCoverIsDragging
    @Environment(\.undoManager) var undoManager
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.dismissWorkoutRecorder) var dismissWorkoutRecorder

    @EnvironmentObject private var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var chronograph: Chronograph

    // MARK: - State

    @State var isShowingChronoSheet = false
    @State private var didAppear = false
    @State private var progress: Float = 0
    @State private var cancellable: AnyCancellable?

    @State private var isShowingFinishConfirmation = false
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isShowingDetailsSheet = false
    @State private var isShowingExerciseSelectionSheet = false

    @State var focusedIntegerFieldIndex: IntegerField.Index?

    @FocusState var isFocusingTitleTextfield: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                if let workout = workoutRecorder.workout {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack {
                                WorkoutSetGroupList(
                                    workout: workout,
                                    focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                                    canReorder: true
                                )
                                .padding(.horizontal)
                                .padding(.top, 90)
                                .padding(.bottom, UIScreen.main.bounds.height * (exerciseSelectionPresentationDetent == .medium ? 0.5 : BOTTOM_SHEET_SMALL))
                                .emptyPlaceholder(workout.setGroups) {
                                    Text(NSLocalizedString("addExercisesFromBelow", comment: ""))
                                        .foregroundStyle(Color.secondaryLabel)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .padding(.top, 30)
                                }
                                .onChange(of: focusedIntegerFieldIndex) {
                                    if let id = focusedIntegerFieldIndex {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            proxy.scrollTo(id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            .fullScreenDraggableCoverTopInset()
                            .id(1)
                        }
                        .onAppear {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(1, anchor: .bottom)
                            }
                        }
                        .scrollIndicators(.hidden)
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 100)
                        }
                        .sheet(isPresented: .constant(true)) {
                            NavigationView {
                                ExerciseSelectionScreen(
                                    selectedExercise: nil,
                                    setExercise: { exercise in
                                        withAnimation {
                                            workoutRecorder.addSetGroup(with: exercise)
                                            proxy.scrollTo(1, anchor: .bottom)
                                        }
                                    },
                                    forSecondary: false,
                                    presentationDetentSelection: $exerciseSelectionPresentationDetent
                                )
                                .padding(.top)
                                .toolbar {
                                    if exerciseSelectionPresentationDetent == .fraction(BOTTOM_SHEET_SMALL) {
                                        ToolbarItemGroup(placement: .bottomBar) {
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
                                            // TODO: Think about info button. Maybe not needed. Maybe something else ?
//                                            Button {
//                                                isShowingDetailsSheet = true
//                                            } label: {
//                                                Image(systemName: "info.circle")
//                                            }
                                            Spacer()
                                            Spacer()
                                            Button {
                                                isShowingChronoSheet = true
                                            } label: {
                                                Image(systemName: chronograph.mode == .timer ? "timer" : "stopwatch")
                                            }
                                        }
                                    }
                                }
                                .toolbar(.hidden, for: .navigationBar)
                                .sheet(isPresented: $isShowingChronoSheet) {
                                    TimerStopwatchView(chronograph: chronograph)
                                        .presentationDetents([.fraction(0.4)])
                                        .presentationCornerRadius(30)
                                        .padding()
                                        .frame(maxHeight: .infinity, alignment: .top)
                                }
                                .sheet(isPresented: $isShowingDetailsSheet) {
                                    if let workout = workoutRecorder.workout {
                                        WorkoutDetailSheet(workout: workout, progress: progress)
                                            .padding()
                                            .presentationDetents([.fraction(0.4)])
                                            .presentationCornerRadius(30)
                                    }
                                }
                                .sheet(isPresented: $isShowingFinishConfirmation) {
                                    if let workout = workoutRecorder.workout {
                                        FinishConfirmationSheet(workout: workout, onEndWorkout: {
                                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                                            workoutRecorder.saveWorkout()
                                            dismissWorkoutRecorder()
                                            goHome()
                                        })
                                        .padding([.top, .horizontal])
                                        .presentationDetents([.fraction(0.4)])
                                    }
                                }
                            }
                            .opacity(fullScreenDraggableCoverIsDragging ? 0 : 1)
                            .animation(.easeOut(duration: 0.2), value: fullScreenDraggableCoverIsDragging)
                            .presentationDetents([.fraction(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                            .presentationBackgroundInteraction(.enabled)
                            .presentationDragIndicator(fullScreenDraggableCoverIsDragging ? .hidden : .visible)
                            .presentationBackground(fullScreenDraggableCoverIsDragging ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.thickMaterial))
                            .presentationCornerRadius(30)
                            .interactiveDismissDisabled()
                            .onChange(of: fullScreenDraggableCoverIsDragging) {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                    .onAppear {
                        updateProgress()
                    }
                    .onReceive(workoutRecorder.workout?.objectWillChange ?? ObservableObjectPublisher()) {
                        updateProgress()
                    }
                }
                Header
                    .frame(maxHeight: .infinity, alignment: .top)
                    .fullScreenDraggableCoverDragArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemsKeyboard
            }
        }
        .onAppear {
            // onAppear called twice because of bug
            if !didAppear {
                didAppear = true
                setUpAutoSaveForWorkout()
                exerciseSelectionPresentationDetent = workoutRecorder.workout?.isEmpty ?? true ? .medium : .fraction(BOTTOM_SHEET_SMALL)

                if preventAutoLock {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .scrollDismissesKeyboard(.interactively)
        #if targetEnvironment(simulator)
            .statusBarHidden(true)
        #endif
    }

    private var Header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Rectangle()
                    .frame(width: 40, height: 5)
                    .clipShape(Capsule())
                    .opacity(exerciseSelectionPresentationDetent == .large ? 0 : 1)
                HStack {
                    if let workout = workoutRecorder.workout {
                        WorkoutMuscleGroupChart(workout: workout)
                            .transition(.move(edge: .leading))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 10) {
                            if let workoutStartTime = workoutRecorder.workout?.date {
                                StopwatchView(startTime: workoutStartTime)
                                    .foregroundStyle(.secondary)
                                    .font(.footnote.weight(.bold).monospacedDigit())
                            }
                            if chronograph.status != .idle {
                                ChronographView(chronograph: chronograph) { seconds in
                                    HStack {
                                        Divider()
                                            .frame(height: 12)
                                        HStack {
                                            Image(systemName: chronograph.mode == .timer ? "timer" : "stopwatch")
                                            Text("\(Int(seconds) / 60 / 10 % 6)\(Int(seconds) / 60 % 10):\(Int(seconds) % 60 / 10)\(Int(seconds) % 60 % 10)")
                                        }
                                        .foregroundColor(chronograph.status == .running ? .accentColor : .secondaryLabel)
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                    }
                                }
                            }
                        }
                        TextField(
                            "",
                            text: workoutName,
                            prompt: Text(Workout.getStandardName(for: Date())).foregroundStyle(Color.label)
                        )
                        .submitLabel(.done)
                        .focused($isFocusingTitleTextfield)
                        .lineLimit(1)
                        .foregroundColor(.label)
                        .font(.body.weight(.bold))
                    }
                    Spacer()
                    Button {
                        guard workoutRecorder.workout?.hasEntries ?? false else {
                            withAnimation {
                                workoutRecorder.discardWorkout()
                                dismissWorkoutRecorder()
                            }
                            return
                        }
                        isShowingFinishConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.bold))
                            .foregroundColor(Color.accentColor)
                            .padding(8)
                            .background(Color.accentColor.secondaryTranslucentBackground)
                            .clipShape(Circle())
                    }
                }
            }
            .fullScreenDraggableCoverTopInset()
            .padding(.horizontal)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            Divider()
        }
    }

    // MARK: - Supporting Methods / Computed Properties

    private var workoutName: Binding<String> {
        Binding(get: { workoutRecorder.workout?.name ?? "" }, set: { workoutRecorder.workout?.name = $0 })
    }

    private func updateProgress() {
        guard let workout = workoutRecorder.workout else {
            progress = 0
            return
        }
        let totalSets = workout.sets.count
        let completedSets = workout.sets.filter { $0.hasEntry }.count
        progress = totalSets > 0 ? Float(completedSets) / Float(totalSets) : 0
    }

    private var progressInWorkout: Float {
        guard let workout = workoutRecorder.workout, workout.setGroups.count > 0 else { return 0 }
        return Float((workout.sets.filter { $0.hasEntry }).count) / Float(workout.sets.count)
    }

    func indexInSetGroup(for workoutSet: WorkoutSet) -> Int? {
        guard let workout = workoutRecorder.workout else { return nil }
        for setGroup in workout.setGroups {
            if let index = setGroup.index(of: workoutSet) {
                return index
            }
        }
        return nil
    }

    var selectedWorkoutSet: WorkoutSet? {
        guard let focusedIndex = focusedIntegerFieldIndex else { return nil }
        return workoutRecorder.workout?.sets.value(at: focusedIndex.primary)
    }

    func nextIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout else { return nil }
        guard let focusedIndex = focusedIntegerFieldIndex,
              let focusedWorkoutSet = workout.sets.value(at: focusedIndex.primary)
        else { return nil }
        if let _ = focusedWorkoutSet as? StandardSet {
            guard focusedIndex.primary + 1 < workout.sets.count else { return nil }
            return IntegerField.Index(
                primary: focusedIndex.primary + 1,
                secondary: 0,
                tertiary: focusedIndex.tertiary
            )
        } else if let _ = focusedWorkoutSet as? SuperSet {
            guard focusedIndex.secondary == 1 else {
                return IntegerField.Index(
                    primary: focusedIndex.primary,
                    secondary: 1,
                    tertiary: focusedIndex.tertiary
                )
            }
            guard focusedIndex.primary + 1 < workout.sets.count else { return nil }
            return IntegerField.Index(
                primary: focusedIndex.primary + 1,
                secondary: 0,
                tertiary: focusedIndex.tertiary
            )
        } else if let dropSet = focusedWorkoutSet as? DropSet {
            if focusedIndex.secondary + 1 < dropSet.numberOfDrops {
                return IntegerField.Index(
                    primary: focusedIndex.primary,
                    secondary: focusedIndex.secondary + 1,
                    tertiary: focusedIndex.tertiary
                )
            }
            guard focusedIndex.primary + 1 < workout.sets.count else { return nil }
            return IntegerField.Index(
                primary: focusedIndex.primary + 1,
                secondary: 0,
                tertiary: focusedIndex.tertiary
            )
        }
        return nil
    }

    func previousIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout else { return nil }
        guard let focusedIndex = focusedIntegerFieldIndex else { return nil }
        guard focusedIndex.secondary == 0 else {
            return IntegerField.Index(
                primary: focusedIndex.primary,
                secondary: focusedIndex.secondary - 1,
                tertiary: focusedIndex.tertiary
            )
        }
        guard focusedIndex.primary > 0 else { return nil }
        let previousSet = workout.sets.value(at: focusedIndex.primary - 1)
        if let _ = previousSet as? StandardSet {
            return IntegerField.Index(
                primary: focusedIndex.primary - 1,
                secondary: focusedIndex.secondary,
                tertiary: focusedIndex.tertiary
            )
        } else if let _ = previousSet as? SuperSet {
            return IntegerField.Index(
                primary: focusedIndex.primary - 1,
                secondary: 1,
                tertiary: focusedIndex.tertiary
            )
        } else if let dropSet = previousSet as? DropSet {
            return IntegerField.Index(
                primary: focusedIndex.primary - 1,
                secondary: dropSet.numberOfDrops - 1,
                tertiary: focusedIndex.tertiary
            )
        }
        return nil
    }

    // MARK: - Autosave

    private func setUpAutoSaveForWorkout() {
        cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: database.context)
            .sink { _ in
                self.workoutRecorder.workout?.objectWillChange.send()
                self.database.save()
            }
    }
}

struct WorkoutMuscleGroupChart: View {
    @ObservedObject var workout: Workout
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    var body: some View {
        let sets = workout.sets   // Assuming this is an ordered relationship
        if !sets.isEmpty {
            Chart {
                ForEach(muscleGroupService.getMuscleGroupOccurances(in: sets), id: \.0) { occ in
                    SectorMark(
                        angle: .value("Value", occ.1),
                        innerRadius: .ratio(0.65),
                        angularInset: 1
                    )
                    .foregroundStyle(occ.0.color.gradient)
                }
            }
            .frame(width: 40, height: 40)
        }
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    var body: some View {
        WorkoutRecorderScreen()
            .onAppear {
                workoutRecorder.startWorkout(from: database.testTemplate)
            }
    }
}

struct WorkoutRecorderView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
