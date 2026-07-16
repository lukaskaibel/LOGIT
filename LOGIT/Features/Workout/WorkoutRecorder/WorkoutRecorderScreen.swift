//
//  WorkoutRecorderScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 24.02.22.
//

import Charts
import ColorfulX
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

    /// Whether the header is unfolded into its live stats panel (progress, session stats,
    /// minimize/finish). Expanded while the workout has no logged entries — a brand-new or
    /// template start shows the panel (and the finish/minimize actions) before the first
    /// value lands — and folds away on the first entry.
    @State private var isHeaderExpanded = false
    /// Comparison baseline for the header's trend pills, computed once on appear — previous runs
    /// of this workout (or recent workouts), exactly the workout detail's basis. The current
    /// workout's values are read live; only the historical baseline is frozen.
    @State private var headerRunHistory: WorkoutRunHistory?
    /// Natural (fully-revealed) height of the expanded stats panel, measured live so the drag
    /// can interpolate against it — the panel is always in the tree (clipped to the current
    /// reveal) so its height is known before the first drag.
    @State private var headerPanelHeight: CGFloat = 0
    /// Non-nil while a finger is dragging the header: the live vertical translation, added to the
    /// resting reveal so the panel tracks the finger 1:1 (a real drag, not a threshold swipe).
    @State private var headerDragTranslation: CGFloat?

    /// One spring for every path that folds or unfolds the header (tap, drag settle, auto).
    private var headerExpansionAnimation: Animation { .spring(response: 0.4, dampingFraction: 0.85) }

    /// How much of the panel is currently shown: its resting height (0 collapsed, full expanded)
    /// plus the live drag, clamped to the panel's natural height.
    private var headerPanelRevealHeight: CGFloat {
        let base = isHeaderExpanded ? headerPanelHeight : 0
        guard let translation = headerDragTranslation else { return base }
        return min(max(base + translation, 0), headerPanelHeight)
    }

    private func toggleHeaderExpansion() {
        withAnimation(headerExpansionAnimation) { isHeaderExpanded.toggle() }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The header lives IN FLOW above the list (not overlaid): rows scroll
                // out under it through a soft fade, so it needs no background slab, and
                // its height changes push the list like a large navigation title.
                if !ProcessInfo.processInfo.arguments.contains("-UITEST_NO_HEADER") {
                    Header
                }
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
                                    onTapMetricBadge: { setGroup, frame in
                                        metricInfoSetGroup = setGroup
                                        metricInfoSourceRect = frame
                                    }
                                )
                                .padding(.horizontal)
                                // Clear the fade band along the viewport's top edge so rows
                                // resting at the top aren't half-dissolved.
                                .padding(.top, 24)
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
                        // Rows dissolve to transparent along the viewport's top edge as they
                        // scroll out under the header — a soft fade instead of an abrupt clip
                        // (the in-flow header has no background to hide them behind).
                        .mask(
                            VStack(spacing: 0) {
                                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 28)
                                Color.black
                            }
                        )
                        // One geometry observer, two jobs: `scrollIsAtTop` gates the list's
                        // drag-to-dismiss, and the header behaves like a large navigation
                        // title — unfolds when the list rests at the very top, folds as soon
                        // as the user scrolls down into the content. A drag on the header
                        // itself can still unfold it anywhere (see the Header's gesture).
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top
                        } action: { oldOffset, newOffset in
                            scrollIsAtTop = newOffset <= 2
                            // Never fight an active header drag; its own settle wins.
                            guard headerDragTranslation == nil else { return }
                            if newOffset <= 2 {
                                if !isHeaderExpanded {
                                    withAnimation(headerExpansionAnimation) { isHeaderExpanded = true }
                                }
                            } else if newOffset > oldOffset + 0.5, isHeaderExpanded {
                                // Any genuine downward scroll folds the panel (the 0.5pt
                                // guard only filters float noise — slow scrolls move less
                                // than a few points per frame).
                                withAnimation(headerExpansionAnimation) { isHeaderExpanded = false }
                            }
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
                                            anchorRect: metricInfoSourceRect,
                                            purchaseManager: purchaseManager,
                                            networkMonitor: networkMonitor,
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
            }
            // Ambient muscle-group wash at the top of the screen — the same ColorfulX
            // treatment as the workout detail; it replaces the header's material slab.
            .background(
                VStack {
                    ColorfulView(
                        color: workoutRecorder.workout?.muscleGroups.map { $0.color } ?? [],
                        speed: .constant(0)
                    )
                    .mask(
                        LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 300)
                    Spacer()
                }
                .ignoresSafeArea(.all)
            )
            // Pure black base: the recorder is presented modally, so the default
            // NavigationStack/ScrollView `systemBackground` is its elevated grey.
            .background(Color.black.ignoresSafeArea())
            // Dragging the card (from the set list at the top) resigns any active text field,
            // exactly like the old draggable cover did before handing the view to the drag.
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
                // Start unfolded until the first value is logged: a fresh (or template) start
                // leads with the session panel, a resumed mid-workout recorder stays compact.
                isHeaderExpanded = !(workoutRecorder.workout?.hasEntries ?? false)
                headerRunHistory = workoutRecorder.workout.map {
                    WorkoutRunHistory.compute(for: $0, database: database)
                }

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
            VStack(spacing: 0) {
                headerCompactRow
                // Present only while open or being dragged, so the panel's Finish / Minimize
                // actions leave the accessibility tree (and XCUITest) the moment it folds —
                // .accessibilityHidden on an always-present panel does not reliably hide the
                // buttons. It measures itself the first time it appears and the height is cached
                // in State, so every later drag already knows how far to open; it's clipped to
                // the live reveal so the drag tracks the finger, and the frame animates on settle.
                if let workout = workoutRecorder.workout, isHeaderExpanded || headerDragTranslation != nil {
                    headerExpandedPanel(for: workout)
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onChange(of: geometry.size.height, initial: true) { _, height in
                                        if height > 0 { headerPanelHeight = height }
                                    }
                            }
                        )
                        .frame(height: headerPanelRevealHeight, alignment: .top)
                        .clipped()
                        .opacity(headerPanelHeight > 0 ? min(headerPanelRevealHeight / headerPanelHeight, 1) : 1)
                        .allowsHitTesting(isHeaderExpanded && headerDragTranslation == nil)
                }
                // The grab handle sits at the header's BOTTOM edge — the seam the panel unfolds
                // from — and reads as "pull here": drag the header (or tap the handle / caption)
                // to fold and unfold. Minimizing the recorder is the panel's own button.
                Capsule()
                    .fill(Color.secondaryLabel.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .opacity(exerciseSelectionPresentationDetent == .large ? 0 : 1)
                    .padding(.top, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleHeaderExpansion() }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        // No background slab anymore: the header sits in flow above the list (which
        // fades out before reaching it) over the ambient muscle-group wash. The shape
        // keeps the whole header area draggable despite the transparent gaps.
        .contentShape(Rectangle())
        // A finger on the header drags the panel open/closed 1:1 (simultaneous, so the title
        // field and the caption's own tap still work); release snaps to whichever side the
        // current reveal and the fling velocity favour.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    headerDragTranslation = value.translation.height
                }
                .onEnded { value in
                    let base = isHeaderExpanded ? headerPanelHeight : 0
                    let revealed = min(max(base + value.translation.height, 0), headerPanelHeight)
                    let fraction = headerPanelHeight > 0 ? revealed / headerPanelHeight : 0
                    let expand: Bool
                    if value.velocity.height > 400 {
                        expand = true
                    } else if value.velocity.height < -400 {
                        expand = false
                    } else {
                        expand = fraction >= 0.5
                    }
                    withAnimation(headerExpansionAnimation) {
                        isHeaderExpanded = expand
                        headerDragTranslation = nil
                    }
                }
        )
    }

    /// The always-visible header row, laid out like a `WorkoutCell`: elapsed time and set count
    /// over the editable title, with the muscle-group donut on the trailing edge.
    private var headerCompactRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let workoutStartTime = workoutRecorder.workout?.date {
                        StopwatchView(startTime: workoutStartTime)
                    }
                    Text("·")
                    Text("\(workoutRecorder.workout?.numberOfSets ?? 0) \(NSLocalizedString("sets", comment: ""))")
                }
                .foregroundStyle(.secondary)
                .font(.footnote.weight(.bold).monospacedDigit())
                // The caption is a tap target for folding/unfolding; the title below it keeps
                // its own tap to focus the text field for renaming.
                .contentShape(Rectangle())
                .onTapGesture { toggleHeaderExpansion() }
                TextField(
                    "",
                    text: workoutName,
                    prompt: Text(Workout.getStandardName(for: Date())).foregroundStyle(Color.label)
                )
                .submitLabel(.done)
                .focused($isFocusingTitleTextfield)
                .lineLimit(1)
                .foregroundColor(.label)
                // Grows into a large-title once the panel is open.
                .font((isHeaderExpanded ? Font.title2 : Font.body).weight(.bold))
            }
            Spacer()
            if let workout = workoutRecorder.workout {
                WorkoutMuscleGroupChart(workout: workout)
                    .animation(.interactiveSpring, value: workout.sets)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleHeaderExpansion() }
            }
        }
    }

    /// The unfolded half of the header: the workout detail's Volume and Repetitions stat tiles
    /// above the Minimize and Finish actions. The tiles appear only once the workout has a
    /// logged value — an empty (fresh / template) start shows just the two buttons, so the panel
    /// stays small. Everything accent-colored wears the workout's muscle-group gradient.
    private func headerExpandedPanel(for workout: Workout) -> some View {
        let gradient = workout.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
        return VStack(spacing: 8) {
            if workout.hasEntries {
                HStack(alignment: .top, spacing: 8) {
                    workoutStatTile(.volume, for: workout)
                    workoutStatTile(.repetitions, for: workout)
                }
            }
            HStack(spacing: 8) {
                Button {
                    dismissWorkoutRecorder()
                } label: {
                    Label(NSLocalizedString("minimize", comment: ""), systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.fill)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                Button {
                    guard workout.hasEntries else {
                        finishWorkout(shouldSave: false)
                        return
                    }
                    isShowingFinishConfirmation = true
                } label: {
                    Label(NSLocalizedString("finishWorkout", comment: ""), systemImage: "flag.checkered")
                        .font(.body.weight(.bold))
                        .foregroundStyle(gradient)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            workout.sets.muscleGroupGradient(startPoint: .bottomLeading, endPoint: .topTrailing)
                                .opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }

    /// A Volume / Repetitions tile identical to the workout detail screen's stat grid: the shared
    /// `WorkoutStatTile` (value, vs-previous trend pill, run-bar history) in the workout's
    /// muscle-group gradient. Display-only here — not wrapped in the detail screen's open button.
    private func workoutStatTile(_ metric: WorkoutStatMetric, for workout: Workout) -> some View {
        let sets = workout.sets
        return WorkoutStatTile(
            metric: metric,
            workout: workout,
            history: headerRunHistory ?? WorkoutRunHistory(basis: .recentWorkouts, runs: [workout]),
            accent: sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing),
            barStyle: sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top),
            accentColor: muscleGroupService.getMuscleGroupOccurances(in: workout).first?.0.color ?? .accentColor
        )
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
                    rootView: MetricInfoPanel(setGroup: setGroup, onOpenDetail: { [weak self] metric in
                        guard let exercise = setGroup.exercise else { return }
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
