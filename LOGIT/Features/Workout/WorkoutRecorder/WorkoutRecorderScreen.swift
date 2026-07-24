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
    @Environment(\.workoutRecorderIsDragging) var workoutRecorderIsDragging
    @Environment(\.workoutRecorderIsSettled) var workoutRecorderIsSettled
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.dismissWorkoutRecorder) var dismissWorkoutRecorder
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject private var database: Database
    @EnvironmentObject var workoutRecorder: WorkoutRecorder
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    /// Re-injected into the metric-info popover's `UIHostingController` (environment objects don't
    /// cross the UIKit bridge): the panel's Pro gate reads `purchaseManager`, and the upgrade
    /// screen it can present needs both.
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.workoutRecorderDragDriver) private var recorderDragDriver

    // MARK: - Parameters

    /// Deliberately a plain reference, not an `@EnvironmentObject`: the chronograph publishes on
    /// every start/stop/adjustment, and observing it here re-rendered the whole recorder tree each
    /// time. The screen only drives it imperatively; the views that *display* it
    /// (`FloatingChronoControlsOverlay`, `TimerStopwatchView`, `RestTimerBetweenSetsView`)
    /// observe it themselves.
    let chronograph: Chronograph

    // MARK: - State

    @State var isShowingChronoSheet = false
    @State private var didAppear = false
    @State private var progress: Float = 0
    @State private var cancellables: [AnyCancellable] = []

    @State private var isShowingFinishConfirmation = false
    @State private var exerciseSelectionPresentationDetent: PresentationDetent = .medium
    @State private var isShowingDetailsSheet = false
    @State private var isShowingExerciseSelectionSheet = false
    @State var isShowingReorderSheet = false
    @State private var selectedRestDurationSet: WorkoutSet?
    @State private var exerciseForDetailSheet: Exercise?
    /// When the exercise-detail sheet is opened from the metric popover, the metric whose chart
    /// screen it should jump to; nil for the regular name/previous-set entry points.
    @State private var exerciseDetailAutoMetric: ExercisePrimaryMetric?
    @State private var metricInfoSetGroup: WorkoutSetGroup?
    /// The tapped badge's subject exercise — each superset page has its own badge.
    @State private var metricInfoExercise: Exercise?
    @State private var metricInfoSourceRect: CGRect?
    @State private var scrollToRecentAttempts = false
    /// Plain `@State` holding a reference type on purpose: the screen must keep the instance
    /// alive WITHOUT subscribing to it (`@StateObject` would). The persistent sheet's height
    /// changes on every frame of a detent or keyboard animation; only the floating chrono
    /// overlay consumes it, so only that child observes it.
    @State private var sheetGeometry = RecorderSheetGeometry()

    @State var focusedIntegerFieldIndex: IntegerField.Index?

    @State private var enteredRepetitionSetIDs: Set<NSManagedObjectID> = []

    // Full-screen drag-to-dismiss from the set list: only engages once the list is
    // scrolled to the very top, then hands the drag to the same driver as the header.
    @State private var scrollIsAtTop = false
    @State private var listDragActive = false
    @State private var listDragBaseline: CGFloat = 0

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
                                    // Deferred for the same Menu-dismissal / sheet-on-sheet
                                    // entanglement the workout editor documents on its
                                    // onReorderSetGroups.
                                    onReorderSetGroups: {
                                        DispatchQueue.main.async {
                                            isShowingReorderSheet = true
                                        }
                                    },
                                    onTapPreviousSet: { scrollToRecentAttempts = true; exerciseDetailAutoMetric = nil; exerciseForDetailSheet = $0 },
                                    onTapExerciseName: { scrollToRecentAttempts = false; exerciseDetailAutoMetric = nil; exerciseForDetailSheet = $0 },
                                    // A metric-badge tap routes here instead of presenting from the
                                    // badge: the badge sits behind the persistent exercise sheet, so a
                                    // popover presented from it would dismiss that sheet. The popover
                                    // is instead presented from the sheet's own view controller
                                    // (below), anchored back to the badge, so the sheet survives.
                                    onTapMetricBadge: { setGroup, exercise, frame in
                                        metricInfoSetGroup = setGroup
                                        metricInfoExercise = exercise
                                        metricInfoSourceRect = frame
                                    }
                                )
                                .padding(.horizontal)
                                .padding(.top, 90)
                                .padding(.bottom, exerciseSelectionPresentationDetent == .medium ? (UIScreen.current?.bounds.height ?? 0) * 0.5 : BOTTOM_SHEET_SMALL)
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
                            .id(1)
                        }
                        .onAppear {
                            if isKbdTest || ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SCROLLTO") { return }
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(1, anchor: .bottom)
                            }
                        }
                        .scrollIndicators(.hidden)
                        // Track whether the list is scrolled to the very top; only then
                        // does a downward drag on the list dismiss the recorder.
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y <= -geometry.contentInsets.top + 2
                        } action: { _, atTop in
                            scrollIsAtTop = atTop
                        }
                        // Freeze the list while a dismiss-drag is in flight so it can't
                        // rubber-band against the screen the driver is translating.
                        .scrollDisabled(listDragActive)
                        // The whole set list is a drag handle once at the top: dragging
                        // down from there drives the same interactive dismissal as the
                        // header. Simultaneous so taps, scrolling and context menus keep
                        // working; the gate below only latches on a downward drag at top.
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                                .onChanged { value in
                                    handleListDragChanged(value)
                                }
                                .onEnded { value in
                                    handleListDragEnded(value)
                                }
                        )
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 100)
                        }
                        // The tray only presents once the recorder's morph has landed and
                        // hides while the card is being dragged: a presented child sheet
                        // would swallow the recorder's own interactive dismissal (UIKit
                        // forwards `dismiss` to the presented child).
                        .sheet(isPresented: Binding(
                            get: {
                                workoutRecorderIsSettled
                                    && !workoutRecorderIsDragging
                                    && !isKbdTest
                                    && !ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SHEET")
                            },
                            set: { _ in }  // interactive dismissal is disabled below
                        )) {
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
                                            exercise: metricInfoExercise,
                                            anchorRect: metricInfoSourceRect,
                                            purchaseManager: purchaseManager,
                                            networkMonitor: networkMonitor,
                                            onDismiss: {
                                                metricInfoSetGroup = nil
                                                metricInfoExercise = nil
                                                metricInfoSourceRect = nil
                                            },
                                            onOpenDetail: { exercise, metric in
                                                // Close the popover first; presenting the detail
                                                // sheet mid-dismissal would cancel one of the two.
                                                metricInfoSetGroup = nil
                                                metricInfoExercise = nil
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
                                sheetGeometry.update(
                                    sheetHeight: newValue,
                                    previousHeight: oldValue,
                                    isAtMediumDetent: exerciseSelectionPresentationDetent == .medium
                                )
                            }
                            .presentationDetents([.height(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                            .presentationBackgroundInteraction(.enabled)
                            .presentationDragIndicator(.visible)
                            .ignoresSafeArea()
                            .interactiveDismissDisabled()
                        }
                        .overlay(alignment: .bottomTrailing) {
                            FloatingChronoControlsOverlay(
                                chronograph: chronograph,
                                workoutRecorder: workoutRecorder,
                                sheetGeometry: sheetGeometry,
                                isAtSmallDetent: exerciseSelectionPresentationDetent == .height(BOTTOM_SHEET_SMALL),
                                onOpenChronoSheet: { isShowingChronoSheet = true },
                                onStopStopwatch: stopStopwatch,
                                onCancelTimer: cancelTimer
                            )
                        }
                        .onGeometryChange(for: CGFloat.self) {
                            $0.safeAreaInsets.bottom
                        } action: { newValue in
                            sheetGeometry.safeAreaBottomInset = newValue
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
                        // The header is the recorder's drag handle, exactly like the
                        // old draggable cover. The gesture lives inside the presented
                        // content because the tray sheet's background-interaction
                        // passthrough never delivers touches to the root-level pan
                        // recognizer Transmission installs.
                        .simultaneousGesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    recorderDragDriver.dragChanged(translation: value.translation)
                                }
                                .onEnded { value in
                                    recorderDragDriver.dragEnded(
                                        translation: value.translation,
                                        velocity: value.velocity
                                    )
                                }
                        )
                }
            }
            // Pure black base: the recorder is presented modally, so the default
            // NavigationStack/ScrollView `systemBackground` is its elevated grey.
            .background(Color.black.ignoresSafeArea())
            // Dragging the card resigns any active text field, exactly like the old
            // draggable cover did before handing the view to the drag.
            .onChange(of: workoutRecorderIsDragging) {
                if workoutRecorderIsDragging {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } else {
                    // Safety net: whenever the drag settles (dismiss committed or
                    // snapped back), re-enable scrolling even if the gesture's own
                    // onEnded didn't fire (e.g. the scroll pan won the arbitration).
                    listDragActive = false
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
            // Flush anything the debounced autosave hasn't written yet.
            database.save()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Backgrounding must not race the debounced autosave — persist
            // pending edits while the process is still guaranteed to run.
            if newPhase != .active {
                database.save()
            }
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
                    .accessibilityIdentifier("recorderCloseButton")
                }
            }
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

    // MARK: - List drag-to-dismiss

    /// Latches a dismiss-drag only when it begins at the top of the list and heads
    /// downward, then drives the shared driver with the translation measured from the
    /// moment it latched (so there's no jump if the finger crossed the top mid-scroll).
    private func handleListDragChanged(_ value: DragGesture.Value) {
        if !listDragActive {
            guard scrollIsAtTop,
                  value.translation.height > 0,
                  value.translation.height > abs(value.translation.width)
            else { return }
            listDragActive = true
            listDragBaseline = value.translation.height
        }
        recorderDragDriver.dragChanged(
            translation: CGSize(width: 0, height: value.translation.height - listDragBaseline)
        )
    }

    private func handleListDragEnded(_ value: DragGesture.Value) {
        guard listDragActive else { return }
        listDragActive = false
        recorderDragDriver.dragEnded(
            translation: CGSize(width: 0, height: value.translation.height - listDragBaseline),
            velocity: CGSize(width: 0, height: value.velocity.height)
        )
    }

    // MARK: - Supporting Methods / Computed Properties

    private var workoutName: Binding<String> {
        Binding(get: { workoutRecorder.workout?.name ?? "" }, set: { workoutRecorder.workout?.name = $0 })
    }

    private func updateProgress() {
        let newProgress: Float
        if let workout = workoutRecorder.workout {
            let sets = workout.sets
            let completedSets = sets.filter { $0.hasEntry }.count
            newProgress = sets.isEmpty ? 0 : Float(completedSets) / Float(sets.count)
        } else {
            newProgress = 0
        }
        // Writing an unchanged @State still invalidates the screen body —
        // and most keystrokes don't move the completed-sets ratio.
        if progress != newProgress {
            progress = newProgress
        }
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

        // Read at call time instead of via `@AppStorage`: these settings are only consumed
        // here, and an `@AppStorage` subscription re-rendered the whole recorder tree on every
        // write (the timer sheet writes `lastTimerDuration` on each preset/adjustment tap).
        let defaults = UserDefaults.standard
        let lastTimerDuration = defaults.object(forKey: "lastTimerDuration") == nil
            ? 30
            : defaults.integer(forKey: "lastTimerDuration")

        guard let autoRestBehavior = workoutRecorder.autoRestBehavior(
            forSet: completedSet,
            usesStopwatch: chronograph.mode == .stopwatch,
            autoTimerEnabled: defaults.bool(forKey: "autoTimerEnabled"),
            autoStopwatchEnabled: defaults.bool(forKey: "autoStopwatchEnabled"),
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
        // Advance entry by entry within the set (drops, super set sides), then set by set.
        if focusedIndex.secondary + 1 < focusedWorkoutSet.entryValues.count {
            return clampedIndex(
                primary: focusedIndex.primary,
                secondary: focusedIndex.secondary + 1,
                tertiary: focusedIndex.tertiary,
                in: workout
            )
        }
        guard focusedIndex.primary + 1 < workout.sets.count else { return nil }
        return clampedIndex(
            primary: focusedIndex.primary + 1,
            secondary: 0,
            tertiary: focusedIndex.tertiary,
            in: workout
        )
    }

    func previousIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout else { return nil }
        guard let focusedIndex = focusedIntegerFieldIndex else { return nil }
        guard focusedIndex.secondary == 0 else {
            return clampedIndex(
                primary: focusedIndex.primary,
                secondary: focusedIndex.secondary - 1,
                tertiary: focusedIndex.tertiary,
                in: workout
            )
        }
        guard focusedIndex.primary > 0,
              let previousSet = workout.sets.value(at: focusedIndex.primary - 1)
        else { return nil }
        return clampedIndex(
            primary: focusedIndex.primary - 1,
            secondary: max(0, previousSet.entryValues.count - 1),
            tertiary: focusedIndex.tertiary,
            in: workout
        )
    }

    /// Builds a focus index whose field column is clamped to the target entry's fields —
    /// moving from a two-field reps+weight row onto a single-field reps-only row lands on
    /// that row's last field instead of dropping focus.
    private func clampedIndex(
        primary: Int, secondary: Int, tertiary: Int, in workout: Workout
    ) -> IntegerField.Index {
        let targetType = workout.sets.value(at: primary)?
            .entryValues.value(at: secondary)?.type ?? .repsAndWeight
        return IntegerField.Index(
            primary: primary,
            secondary: secondary,
            tertiary: min(tertiary, targetType.inputFieldCount - 1)
        )
    }

    // MARK: - Autosave

    /// Typing into a set field mutates only that set, so this pipeline does two
    /// things the set-level observation can't: refresh workout-level views and
    /// persist the edit. Both used to run on *every* context change — one
    /// keystroke = one full re-render of every set group cell (with the metric
    /// badges re-scanning the exercise's whole history) plus one synchronous
    /// store commit with a CloudKit export cycle — which made the recorder
    /// visibly stutter while typing. Batching them keeps typing smooth without
    /// changing what ends up on screen or on disk.
    private func setUpAutoSaveForWorkout() {
        let contextDidChange = NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: database.context
        )
        cancellables = [
            // Workout-level observers (progress, muscle chart, metric badges)
            // re-render at most a few times per second; the edited cell itself
            // updates instantly through its own @ObservedObject set.
            contextDidChange
                .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
                .sink { _ in
                    self.workoutRecorder.workout?.objectWillChange.send()
                },
            // Persist at typing pauses. The debounce only defers the save, it
            // never skips it: finishing/discarding saves explicitly, and the
            // scene-phase/disappear hooks in `body` flush pending changes
            // whenever the recorder leaves the screen.
            contextDidChange
                .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
                .sink { _ in
                    self.database.save()
                },
        ]
    }
}

// MARK: - Sheet geometry + floating chrono controls

/// Live geometry of the persistent exercise sheet. Written from the recorder's
/// `onGeometryChange` callbacks and observed ONLY by `FloatingChronoControlsOverlay` — the sheet
/// height changes on every frame of a detent or keyboard animation, and when these values were
/// `@State` on the screen each frame re-rendered the entire recorder tree.
final class RecorderSheetGeometry: ObservableObject {
    @Published var sheetHeight: CGFloat = 0
    @Published var toolbarOpacity: CGFloat = 1
    @Published var animationDuration: CGFloat = 0
    @Published var safeAreaBottomInset: CGFloat = 0
    private var mediumSheetHeight: CGFloat = 0

    func update(sheetHeight newHeight: CGFloat, previousHeight: CGFloat, isAtMediumDetent: Bool) {
        sheetHeight = newHeight

        if isAtMediumDetent {
            mediumSheetHeight = newHeight
        }

        if mediumSheetHeight > 0 {
            let fadeStartHeight = mediumSheetHeight + 140
            let progress = max(min((newHeight - fadeStartHeight) / 72, 1), 0)
            toolbarOpacity = 1 - progress
        } else {
            toolbarOpacity = 1
        }

        let diff = abs(newHeight - previousHeight)
        animationDuration = max(min(diff / 180, 0.3), 0)
    }
}

/// The floating timer/stopwatch button (with its stop/cancel companion) and the placement math
/// that tracks the persistent sheet. Isolated from the recorder screen so the chronograph's
/// frequent publishes and the per-frame sheet-geometry updates re-render only this small
/// overlay, never the whole recorder tree.
private struct FloatingChronoControlsOverlay: View {
    @Environment(\.workoutRecorderIsDragging) private var workoutRecorderIsDragging

    @ObservedObject var chronograph: Chronograph
    @ObservedObject var workoutRecorder: WorkoutRecorder
    @ObservedObject var sheetGeometry: RecorderSheetGeometry
    let isAtSmallDetent: Bool
    let onOpenChronoSheet: () -> Void
    let onStopStopwatch: () -> Void
    let onCancelTimer: () -> Void

    var body: some View {
        if sheetGeometry.sheetHeight > 0 && !workoutRecorderIsDragging {
            HStack {
                WorkoutRecorderFloatingTimerButton(
                    chronograph: chronograph,
                    workoutRecorder: workoutRecorder,
                    action: onOpenChronoSheet
                )
                if chronograph.mode == .stopwatch, chronograph.status == .running {
                    WorkoutRecorderFloatingStopwatchStopButton(
                        workoutRecorder: workoutRecorder,
                        action: onStopStopwatch
                    )
                } else if chronograph.mode == .timer, chronograph.status == .running {
                    WorkoutRecorderFloatingStopwatchStopButton(
                        workoutRecorder: workoutRecorder,
                        action: onCancelTimer
                    )
                }
            }
            .opacity(sheetGeometry.toolbarOpacity)
            .offset(y: -sheetGeometry.sheetHeight)
            .padding(.trailing, 15)
            .offset(y: bottomOffset)
            .animation(.easeInOut(duration: sheetGeometry.animationDuration), value: sheetGeometry.sheetHeight)
            .animation(.easeInOut(duration: sheetGeometry.animationDuration), value: bottomOffset)
        }
    }

    private var bottomOffset: CGFloat {
        let base = sheetGeometry.safeAreaBottomInset - 10
        return isAtSmallDetent ? base - 10 : base
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
    @EnvironmentObject private var chronograph: Chronograph

    var body: some View {
        WorkoutRecorderScreen(chronograph: chronograph)
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
    /// The tapped badge's subject exercise (a superset page's own); nil falls back to the
    /// group's primary exercise inside the panel.
    let exercise: Exercise?
    let anchorRect: CGRect?
    /// Injected into the panel's hosting controller — environment objects don't cross the UIKit
    /// bridge, and the panel's Pro gate (and the upgrade screen it presents) needs them.
    let purchaseManager: PurchaseManager
    let networkMonitor: NetworkMonitor
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
            context.coordinator.presentIfNeeded(
                for: setGroup,
                exercise: exercise,
                anchoredAt: anchorRect,
                embeddedIn: uiView,
                purchaseManager: purchaseManager,
                networkMonitor: networkMonitor
            )
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

        func presentIfNeeded(
            for setGroup: WorkoutSetGroup,
            exercise: Exercise?,
            anchoredAt globalRect: CGRect,
            embeddedIn embeddedView: UIView,
            purchaseManager: PurchaseManager,
            networkMonitor: NetworkMonitor
        ) {
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
                    rootView: MetricInfoPanel(setGroup: setGroup, exercise: exercise, onOpenDetail: { [weak self] metric in
                        guard let exercise = exercise ?? setGroup.exercise else { return }
                        self?.onOpenDetail(exercise, metric)
                    })
                    .padding()
                    .frame(width: 320)
                    .environmentObject(purchaseManager)
                    .environmentObject(networkMonitor)
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
