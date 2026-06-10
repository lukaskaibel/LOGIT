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
    @State private var exerciseForDetailSheet: Exercise?
    /// When the exercise-detail sheet is opened from the metric popover, the metric whose chart
    /// screen it should jump to; nil for the regular name/previous-set entry points.
    @State private var exerciseDetailAutoMetric: ExercisePrimaryMetric?
    @State private var metricInfoSetGroup: WorkoutSetGroup?
    @State private var metricInfoSourceRect: CGRect?
    @State private var scrollToRecentAttempts = false
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
                                    onTapRestDuration: { selectedRestDurationSet = $0 },
                                    onTapPreviousSet: { scrollToRecentAttempts = true; exerciseDetailAutoMetric = nil; exerciseForDetailSheet = $0 },
                                    onTapExerciseName: { scrollToRecentAttempts = false; exerciseDetailAutoMetric = nil; exerciseForDetailSheet = $0 }
                                )
                                // A metric-badge tap routes here instead of presenting from the badge:
                                // the badge sits behind the persistent exercise sheet, so a popover
                                // presented from it would dismiss that sheet. The popover is instead
                                // presented from the sheet's own view controller (below), anchored back
                                // to the badge, so the sheet survives.
                                .environment(\.metricInfoRequest) { setGroup, frame in
                                    metricInfoSetGroup = setGroup
                                    metricInfoSourceRect = frame
                                }
                                .padding(.horizontal)
                                .padding(.top, 90)
                                .padding(.bottom, exerciseSelectionPresentationDetent == .medium ? UIScreen.main.bounds.height * 0.5 : BOTTOM_SHEET_SMALL)
                                .emptyPlaceholder(workout.setGroups) {
                                    Text(NSLocalizedString("addExercisesFromBelow", comment: ""))
                                        .foregroundStyle(Color.secondaryLabel)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .padding(.top, 30)
                                }
                                .onChange(of: focusedIntegerFieldIndex) {
                                    if isKbdTest || ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SCROLLTO") { return }
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
                            if isKbdTest || ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SCROLLTO") { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(1, anchor: .bottom)
                            }
                        }
                        .scrollIndicators(.hidden)
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 100)
                        }
                        .sheet(isPresented: .constant(!isKbdTest && !ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SHEET"))) {
                            NavigationStack {
                                ExerciseSelectionScreen(
                                        selectedExercise: nil,
                                        setExercise: { exercise in
                                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                            withAnimation {
                                                workoutRecorder.addSetGroup(with: exercise)
                                                proxy.scrollTo(1, anchor: .bottom)
                                            }
                                        },
                                        forSecondary: false,
                                        currentWorkoutExercises: workout.exercises,
                                        supersetPrimaryExercise: nil,
                                        presentationDetentSelection: $exerciseSelectionPresentationDetent
                                    )
                                    .toolbar(.hidden, for: .navigationBar)
                                    .sheet(isPresented: $isShowingChronoSheet) {
                                        TimerStopwatchView(chronograph: chronograph)
                                            .presentationDetents([.fraction(0.88)])
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
                                        reorderSetGroupsSheet(for: workout)
                                    }
                                    .sheet(item: $exerciseForDetailSheet) { exercise in
                                        NavigationStack {
                                            ExerciseDetailScreen(
                                                exercise: exercise,
                                                isShowingAsSheet: true,
                                                scrollToRecentAttempts: scrollToRecentAttempts,
                                                autoOpenMetric: exerciseDetailAutoMetric
                                            )
                                        }
                                        .presentationDragIndicator(.visible)
                                    }
                                    // Presents the metric-info popover from the exercise sheet's view
                                    // controller (not the badge's) so the persistent exercise sheet
                                    // isn't torn down. See `metricInfoRequest`.
                                    .background(
                                        MetricInfoPopoverPresenter(
                                            setGroup: metricInfoSetGroup,
                                            anchorRect: metricInfoSourceRect,
                                            onDismiss: {
                                                metricInfoSetGroup = nil
                                                metricInfoSourceRect = nil
                                            },
                                            onOpenDetail: { exercise, metric in
                                                // Close the popover first; presenting the detail
                                                // sheet mid-dismissal would cancel one of the two.
                                                metricInfoSetGroup = nil
                                                metricInfoSourceRect = nil
                                                scrollToRecentAttempts = false
                                                exerciseDetailAutoMetric = metric
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    exerciseForDetailSheet = exercise
                                                }
                                            }
                                        )
                                    )
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
                            .presentationDetents([.height(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
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
                                    } else if shouldShowFloatingTimerCancelButton {
                                        WorkoutRecorderFloatingStopwatchStopButton(
                                            workoutRecorder: workoutRecorder,
                                            action: cancelTimer
                                        )
                                    }
                                }
                                .opacity(toolbarOpacity)
                                .offset(y: -sheetHeight)
                                .padding(.trailing, 15)
                                .offset(y: floatingTimerBottomOffset)
                                .animation(.easeInOut(duration: animationDuration), value: sheetHeight)
                                .animation(.easeInOut(duration: animationDuration), value: floatingTimerBottomOffset)
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
                        if ProcessInfo.processInfo.arguments.contains("-UITEST_MINIMAL") { return }
                        updateProgress()
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: database.context)
                            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
                    ) { _ in
                        if ProcessInfo.processInfo.arguments.contains("-UITEST_MINIMAL") { return }
                        checkForNewSetEntries()
                    }
                }
                if !ProcessInfo.processInfo.arguments.contains("-UITEST_NO_HEADER") {
                    Header
                        .frame(maxHeight: .infinity, alignment: .top)
                        .fullScreenDraggableCoverDragArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                if ProcessInfo.processInfo.arguments.contains("-UITEST_SIMPLE_TOOLBAR") {
                    ToolbarItemGroup(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button {} label: { Image(systemName: "chevron.up").keyboardToolbarButtonStyle() }
                            Button {} label: { Image(systemName: "chevron.down").keyboardToolbarButtonStyle() }
                            Button {} label: { Image(systemName: "keyboard.chevron.compact.down").keyboardToolbarButtonStyle() }
                        }
                    }
                } else {
                    ToolbarItemsKeyboard
                }
            }
        }
        .onAppear {
            // onAppear called twice because of bug
            if !didAppear {
                didAppear = true
                if !ProcessInfo.processInfo.arguments.contains("-UITEST_MINIMAL") {
                    setUpAutoSaveForWorkout()
                }
                exerciseSelectionPresentationDetent = workoutRecorder.workout?.isEmpty ?? true ? .medium : .height(BOTTOM_SHEET_SMALL)
                enteredRepetitionSetIDs = workoutRecorder.workout.map {
                    workoutRecorder.repetitionEnteredSetIDs(in: $0)
                } ?? []

                if preventAutoLock {
                    UIApplication.shared.isIdleTimerDisabled = true
                }

                if isKbdTest {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        focusedIntegerFieldIndex = IntegerField.Index(primary: 0, secondary: 0, tertiary: 0)
                    }
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

    private var isKbdTest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITEST_FOCUS_TITLE")
        #else
        return false
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
            .padding(.bottom)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
                    .edgesIgnoringSafeArea(.top)
            }
        }
    }

    // MARK: - Floating Timer Button

    private var shouldShowFloatingTimerButton: Bool {
        sheetHeight > 0
            && !fullScreenDraggableCoverIsDragging
    }

    private var floatingTimerBottomOffset: CGFloat {
        let base = safeAreaBottomInset - 10
        if exerciseSelectionPresentationDetent == .height(BOTTOM_SHEET_SMALL) {
            return base - 10
        }
        return base
    }

    @ViewBuilder
    private func reorderSetGroupsSheet(for workout: Workout) -> some View {
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

    private var shouldShowFloatingStopwatchStopButton: Bool {
        chronograph.mode == .stopwatch
            && chronograph.status == .running
    }

    private var shouldShowFloatingTimerCancelButton: Bool {
        chronograph.mode == .timer
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

    private func cancelTimer() {
        guard chronograph.mode == .timer else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // If this timer is an auto-rest timer (activeRestTimerSet != nil), we want to keep
        // the elapsed rest time so far when cancelling.
        workoutRecorder.finishRestAndStopChronograph(using: chronograph, persistTrackedValue: true)
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

// MARK: - Metric info popover

/// Presents `MetricInfoPanel` as a real UIKit popover from the **persistent exercise sheet's view
/// controller**, anchored at the badge's frame. A popover presented from the badge itself (root
/// content, behind the sheet) makes UIKit dismiss the exercise sheet to present — presenting from
/// the sheet's own controller nests the popover above it instead, like the recorder's other
/// sheets. SwiftUI's `.popover` can't express this split between the presenting controller and the
/// anchor location, hence the UIKit bridge. Embedded (invisibly) in the exercise sheet's content;
/// presents whenever `setGroup` + `anchorRect` are non-nil. `anchorRect` is in global (window)
/// coordinates; it lies outside the sheet's bounds, which UIKit accepts — the popover just
/// positions next to the rect in window space.
private struct MetricInfoPopoverPresenter: UIViewRepresentable {
    let setGroup: WorkoutSetGroup?
    let anchorRect: CGRect?
    let onDismiss: () -> Void
    /// Called when the panel's value/chart row is tapped: (exercise, metric) — the recorder closes
    /// this popover and opens the exercise-detail sheet at that metric's chart.
    let onOpenDetail: (Exercise, ExercisePrimaryMetric) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.onOpenDetail = onOpenDetail
        if let setGroup, let anchorRect {
            context.coordinator.presentIfNeeded(for: setGroup, anchoredAt: anchorRect, embeddedIn: uiView)
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var onDismiss: () -> Void = {}
        var onOpenDetail: (Exercise, ExercisePrimaryMetric) -> Void = { _, _ in }
        private weak var popover: UIViewController?
        private var isPresenting = false

        func presentIfNeeded(for setGroup: WorkoutSetGroup, anchoredAt globalRect: CGRect, embeddedIn embeddedView: UIView) {
            guard !isPresenting, popover == nil else { return }
            isPresenting = true
            // Deferred: updateUIView runs mid-render, and UIKit presentation during a SwiftUI
            // update is unreliable.
            DispatchQueue.main.async { [weak embeddedView] in
                guard let embeddedView, embeddedView.window != nil,
                      let baseViewController = embeddedView.owningViewController
                else {
                    self.isPresenting = false
                    return
                }
                var presenter = baseViewController
                while let presented = presenter.presentedViewController { presenter = presented }

                let host = UIHostingController(
                    rootView: MetricInfoPanel(setGroup: setGroup, onOpenDetail: { [weak self] metric in
                        guard let exercise = setGroup.exercise else { return }
                        self?.onOpenDetail(exercise, metric)
                    })
                    .padding()
                    .frame(width: 320)
                )
                host.modalPresentationStyle = .popover
                // Clear so the system popover material shows, matching the badge's own SwiftUI
                // popover on other screens.
                host.view.backgroundColor = .clear
                host.sizingOptions = .preferredContentSize
                host.preferredContentSize = host.sizeThatFits(
                    in: CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height)
                )
                host.overrideUserInterfaceStyle = presenter.traitCollection.userInterfaceStyle
                if let popoverController = host.popoverPresentationController {
                    popoverController.sourceView = embeddedView
                    // SwiftUI's global space is the window's space; convert into the embedded
                    // view's local space (the rect ends up above the sheet's bounds — fine).
                    popoverController.sourceRect = embeddedView.convert(globalRect, from: nil)
                    popoverController.permittedArrowDirections = [.up, .down]
                    popoverController.delegate = self
                }
                self.popover = host
                presenter.present(host, animated: true) { self.isPresenting = false }
            }
        }

        func dismissIfNeeded() {
            popover?.dismiss(animated: true)
            popover = nil
            isPresenting = false
        }

        // Keep it a popover on iPhone instead of adapting to a sheet.
        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            popover = nil
            onDismiss()
        }
    }
}

private extension UIView {
    /// The view controller this view belongs to, via the responder chain.
    var owningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let viewController = current as? UIViewController { return viewController }
            responder = current.next
        }
        return nil
    }
}
