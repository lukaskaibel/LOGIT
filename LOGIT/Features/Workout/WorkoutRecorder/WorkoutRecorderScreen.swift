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

    @AppStorage("autoTimerEnabled") private var autoTimerEnabled: Bool = false
    @AppStorage("autoStopwatchEnabled") private var autoStopwatchEnabled: Bool = false
    @AppStorage("lastTimerDuration") private var lastTimerDuration: Int = 30

    @State var isShowingChronoSheet = false
    @State private var didAppear = false
    @State private var progress: Float = 0
    @State private var cancellable: AnyCancellable?

    @State private var isShowingFinishConfirmation = false
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isShowingDetailsSheet = false
    @State private var isShowingExerciseSelectionSheet = false
    @State private var isShowingReorderSheet = false
    @State private var selectedRestDurationSet: WorkoutSet?
    @State private var sheetHeight: CGFloat = 0
    @State private var mediumSheetHeight: CGFloat = 0
    @State private var animationDuration: CGFloat = 0
    @State private var toolbarOpacity: CGFloat = 1
    @State private var safeAreaBottomInset: CGFloat = 0

    @State var focusedIntegerFieldIndex: IntegerField.Index?

    @State private var enteredRepetitionSetIDs: Set<NSManagedObjectID> = []

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
                                    canReorder: true,
                                    showDetailAsSheet: true,
                                    showPendingRestInTertiary: true,
                                    onTapRestDuration: { workoutSet in
                                        selectedRestDurationSet = workoutSet
                                    },
                                    activeRestTimerSet: workoutRecorder.activeRestTimerSet,
                                    isChronographActive: chronograph.status == .running || chronograph.status == .paused,
                                    chronograph: chronograph,
                                    chronographMode: chronograph.mode
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
                                VStack(spacing: 0) {
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
                                    .toolbar(.hidden, for: .navigationBar)
                                    .sheet(isPresented: $isShowingChronoSheet) {
                                        TimerStopwatchView(chronograph: chronograph)
                                            .presentationDetents([.fraction(0.76)])
                                            .presentationDragIndicator(.visible)
                                    }
                                    .sheet(item: $selectedRestDurationSet) { workoutSet in
                                        RestDurationEditorSheet(workoutSet: workoutSet)
                                            .presentationDetents([.fraction(0.65)])
                                            .padding()
                                            .frame(maxHeight: .infinity, alignment: .top)
                                    }
                                    .sheet(isPresented: $isShowingDetailsSheet) {
                                        if let workout = workoutRecorder.workout {
                                            WorkoutDetailSheet(workout: workout, progress: progress)
                                                .padding()
                                                .presentationDetents([.fraction(0.4)])
                                        }
                                    }
                                    .sheet(isPresented: $isShowingFinishConfirmation) {
                                        if let workout = workoutRecorder.workout {
                                            FinishConfirmationSheet(workout: workout, onEndWorkout: {
                                                finishWorkout(shouldSave: true)
                                            })
                                            .padding([.top, .horizontal])
                                            .presentationDetents([.fraction(0.4)])
                                        }
                                    }
                                    .sheet(isPresented: $isShowingReorderSheet) {
                                        NavigationStack {
                                            List {
                                                ForEach(workout.setGroups) { setGroup in
                                                    HStack {
                                                        VStack(alignment: .leading) {
                                                            Text(setGroup.exercise?.displayName ?? "")
                                                            if (setGroup.sets.first as? SuperSet) != nil,
                                                               let secondaryExercise = setGroup.secondaryExercise {
                                                                HStack {
                                                                    Image(systemName: "arrow.turn.down.right")
                                                                    Text(secondaryExercise.displayName)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                .onDelete {
                                                    workout.setGroups.remove(atOffsets: $0)
                                                    workout.setGroups.forEach { $0.objectWillChange.send() }
                                                }
                                                .onMove { source, destination in
                                                    workout.setGroups.move(fromOffsets: source, toOffset: destination)
                                                    workout.setGroups.forEach { $0.objectWillChange.send() }
                                                }
                                            }
                                            .environment(\.editMode, .constant(.active))
                                            .navigationTitle(NSLocalizedString("reorderExercises", comment: ""))
                                            .navigationBarTitleDisplayMode(.inline)
                                            .toolbar {
                                                ToolbarItem(placement: .topBarTrailing) {
                                                    Button {
                                                        isShowingReorderSheet = false
                                                    } label: {
                                                        Text(NSLocalizedString("done", comment: ""))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    if exerciseSelectionPresentationDetent == .fraction(BOTTOM_SHEET_SMALL) {
                                        HStack {
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
                                            Button {
                                                isShowingReorderSheet = true
                                            } label: {
                                                Image(systemName: "arrow.up.arrow.down")
                                            }
                                        }
                                        .tint(Color.label)
                                        .font(.title2)
                                        .padding(.horizontal, 30)
                                        .padding(.bottom, 5)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onGeometryChange(for: CGFloat.self) {
                                max($0.size.height, 0)
                            } action: { oldValue, newValue in
                                sheetHeight = newValue

                                if exerciseSelectionPresentationDetent == .medium {
                                    mediumSheetHeight = newValue
                                }

                                if mediumSheetHeight > 0 {
                                    let fadeStartHeight = mediumSheetHeight + 140
                                    let progress = max(min((newValue - fadeStartHeight) / 72, 1), 0)
                                    toolbarOpacity = 1 - progress
                                } else {
                                    toolbarOpacity = 1
                                }

                                let diff = abs(newValue - oldValue)
                                let duration = max(min(diff / 180, 0.3), 0)
                                animationDuration = duration
                            }
                            .opacity(fullScreenDraggableCoverIsDragging ? 0 : 1)
                            .animation(.easeOut(duration: 0.2), value: fullScreenDraggableCoverIsDragging)
                            .presentationDetents([.fraction(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                            .presentationBackgroundInteraction(.enabled)
                            .presentationDragIndicator(fullScreenDraggableCoverIsDragging ? .hidden : .visible)
                            .ignoresSafeArea()
                            .interactiveDismissDisabled()
                            .onChange(of: fullScreenDraggableCoverIsDragging) {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if shouldShowFloatingTimerButton {
                                HStack {
                                    WorkoutRecorderFloatingTimerButton(
                                        chronograph: chronograph,
                                        workoutRecorder: workoutRecorder,
                                        action: { isShowingChronoSheet = true }
                                    )
                                    if shouldShowFloatingStopwatchStopButton {
                                        WorkoutRecorderFloatingStopwatchStopButton(
                                            workoutRecorder: workoutRecorder,
                                            action: stopStopwatch
                                        )
                                    }
                                }
                                .opacity(toolbarOpacity)
                                .offset(y: -sheetHeight)
                                .padding(.trailing, 15)
                                .offset(y: safeAreaBottomInset - 10)
                                .animation(.easeInOut(duration: animationDuration), value: sheetHeight)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) {
                            $0.safeAreaInsets.bottom
                        } action: { newValue in
                            safeAreaBottomInset = newValue
                        }
                    }
                    .onAppear {
                        updateProgress()
                    }
                    .onReceive(workoutRecorder.workout?.objectWillChange ?? ObservableObjectPublisher()) {
                        updateProgress()
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: database.context)
                            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
                    ) { _ in
                        checkForNewSetEntries()
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
                enteredRepetitionSetIDs = workoutRecorder.workout.map {
                    workoutRecorder.repetitionEnteredSetIDs(in: $0)
                } ?? []

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
                            .animation(.interactiveSpring, value: workout.sets)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let workoutStartTime = workoutRecorder.workout?.date {
                            StopwatchView(startTime: workoutStartTime)
                                .foregroundStyle(.secondary)
                                .font(.footnote.weight(.bold).monospacedDigit())
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
                            finishWorkout(shouldSave: false)
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

    // MARK: - Floating Timer Button

    private var shouldShowFloatingTimerButton: Bool {
        sheetHeight > 0
            && !fullScreenDraggableCoverIsDragging
    }

    private var shouldShowFloatingStopwatchStopButton: Bool {
        chronograph.mode == .stopwatch
            && chronograph.status == .running
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

    private func checkForNewSetEntries() {
        guard let workout = workoutRecorder.workout else { return }

        let autoRestTrigger = workoutRecorder.autoRestTriggerSet(
            in: workout,
            previousRepetitionEntrySetIDs: enteredRepetitionSetIDs,
            preferredSet: selectedWorkoutSet
        )
        enteredRepetitionSetIDs = autoRestTrigger.repetitionEntrySetIDs

        guard let enteredSet = autoRestTrigger.triggerSet else { return }
        startRestTimerForSet(enteredSet)
    }

    private func startRestTimerForSet(_ completedSet: WorkoutSet) {
        if chronograph.status == .running,
           let previousTimerSet = workoutRecorder.activeRestTimerSet,
           previousTimerSet.objectID != completedSet.objectID
        {
            if chronograph.mode == .stopwatch {
                let elapsed = chronograph.elapsedSeconds
                if elapsed > 0 {
                    workoutRecorder.recordRestDuration(elapsed, for: previousTimerSet)
                }
            }
            chronograph.cancel()
            chronograph.onTimerFired = nil
            workoutRecorder.activeRestTimerSet = nil
        }

        guard workoutRecorder.activeRestTimerSet?.objectID != completedSet.objectID else { return }
        guard chronograph.status != .running else { return }

        guard let autoRestBehavior = workoutRecorder.autoRestBehavior(
            forSet: completedSet,
            usesStopwatch: chronograph.mode == .stopwatch,
            autoTimerEnabled: autoTimerEnabled,
            autoStopwatchEnabled: autoStopwatchEnabled,
            timerDuration: lastTimerDuration
        ) else {
            return
        }

        workoutRecorder.activeRestTimerSet = completedSet
        chronograph.cancel()

        switch autoRestBehavior {
        case let .timer(restSeconds):
            chronograph.mode = .timer
            chronograph.setSeconds(Double(restSeconds) + 0.99)
            chronograph.start()
            chronograph.onTimerFired = { [weak chronograph, weak workoutRecorder] in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let currentSet = workoutRecorder?.activeRestTimerSet,
                   currentSet.restDurationSeconds == 0 {
                    let recordedDuration = chronograph.map {
                        max(0, Int($0.initialTimerSeconds.rounded(.down)))
                    } ?? restSeconds
                    workoutRecorder?.recordRestDuration(recordedDuration, for: currentSet)
                }
                workoutRecorder?.activeRestTimerSet = nil
            }

        case .stopwatch:
            chronograph.mode = .stopwatch
            chronograph.setSeconds(0)
            chronograph.onTimerFired = nil
            chronograph.start()
        }
    }

    private func stopStopwatch() {
        guard chronograph.mode == .stopwatch else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        workoutRecorder.endStopwatch(using: chronograph)
    }

    private func finishWorkout(shouldSave: Bool) {
        workoutRecorder.finishRestAndStopChronograph(
            using: chronograph,
            persistTrackedValue: shouldSave
        )

        if shouldSave {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            workoutRecorder.saveWorkout()
            dismissWorkoutRecorder()
            goHome()
        } else {
            withAnimation {
                workoutRecorder.discardWorkout()
                dismissWorkoutRecorder()
            }
        }
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
