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

/// Scrollable room past the last set group, so the bottom of the list can be pulled clear of
/// the exercise tray instead of coming to rest right on its edge.
private let RECORDER_LIST_SCROLL_SLACK: CGFloat = 120

/// Breathing room above the header's Minimize / Finish row, separating the actions from the
/// summary above them. Part of the panel's first stop, so it also spaces the buttons off the
/// title while the summary is still folded away.
private let RECORDER_HEADER_ACTIONS_SPACING: CGFloat = 14

/// How far a downward pull has to travel before it hands the recorder over to the dismissal
/// driver. Engaging is not a free look: it tears the exercise tray down (UIKit forwards the
/// recorder's `dismiss` to a presented child, so the tray has to go first) and that teardown
/// commits the minimize. So the pull has to be a deliberate drag — a swipe that just flings
/// the list back to its top must never minimize the workout. Up to here the list simply
/// rubber-bands, which is the feedback that something is being pulled.
private let RECORDER_DISMISS_ENGAGEMENT_DISTANCE: CGFloat = 200

/// Holds the set list's live scroll offset outside SwiftUI's state graph: it changes on every
/// scroll frame and nothing in the body reads it directly, so writing it must not invalidate
/// the recorder (see `RecorderSheetGeometry` for the same reasoning about the tray's height).
final class RecorderScrollTracker {
    var offset: CGFloat = 0
}

struct WorkoutRecorderScreen: View {
    // MARK: - AppStorage

    @AppStorage("preventAutoLock") var preventAutoLock: Bool = true
    /// Carried over from the finish confirmation sheet the finish panel replaces.
    @AppStorage("wasPromptedToRateApp") var wasPromptedToRateApp: Bool = false

    // MARK: - Environment

    @Environment(\.goHome) var goHome
    @Environment(\.workoutRecorderIsDragging) var workoutRecorderIsDragging
    @Environment(\.workoutRecorderIsSettled) var workoutRecorderIsSettled
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.dismissWorkoutRecorder) var dismissWorkoutRecorder
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview

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

    /// The top sheet: the compact row, the panel hanging from it, and finishing. See
    /// `RecorderTopSheetModel`. The screen body reads only its measured geometry and
    /// `isFinishing`; the reveal itself is observed by the sheet's own small views, so folding it
    /// never re-renders the recorder.
    @State private var topSheet = RecorderTopSheetModel()
    /// The records this session set, for the finish panel's highlight line. Computed once when the
    /// panel opens rather than per render: the walk over every exercise's history is real work and
    /// the recorder must never do it on a redraw.
    @State private var finishReport: WorkoutProgressReport?
    /// The finish bar's height, so the finish content can scroll clear of it.
    @State private var finishBarHeight: CGFloat = 0
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
    /// Translation at which a drag on an already-extended header handed over to the
    /// recorder's dismissal (non-nil while that hand-over is in flight).
    @State private var headerDismissBaseline: CGFloat?

    @FocusState var isFocusingTitleTextfield: Bool
    /// The workout note's focus. While it is up the set list stops scrolling, and the sheet ignores
    /// the scroll, so the panel stays open under the keyboard instead of folding mid-sentence.
    @FocusState private var isNoteFieldFocused: Bool

    /// The list's live scroll offset. A plain box rather than `@State`: it changes on every scroll
    /// frame and nothing in the body reads it.
    @State private var scrollTracker = RecorderScrollTracker()
    /// The set list's viewport height. Constant while the sheet moves — the sheet floats over the
    /// list — so the minimum content height built on it is constant too.
    @State private var listViewportHeight: CGFloat = 0
    /// Moves the list when the sheet opens or closes in the large-title zone at the top of it.
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    /// One spring for every open, close and snap of the sheet while recording.
    private var sheetAnimation: Animation { .spring(response: 0.4, dampingFraction: 0.86) }
    /// Finishing travels most of the screen, so it gets a little longer to do it in.
    private var finishAnimation: Animation { .spring(response: 0.5, dampingFraction: 0.9) }

    private var isHeaderHidden: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITEST_NO_HEADER")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if let workout = workoutRecorder.workout {
                    recorderList(for: workout)
                }
                // Over the list, not above it in the layout: the sheet's height never touches the
                // list's viewport, which is the whole reason scrolling and folding stay in step.
                if !isHeaderHidden {
                    topSheetView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                topSheet.containerDidMeasure(height)
            }
            // Ambient muscle-group wash at the top of the screen — the same ColorfulX
            // treatment as the workout detail; it replaces the header's material slab.
            .background(
                VStack {
                    ColorfulView(
                        color: workoutRecorder.workout?.muscleGroups.map { $0.color } ?? [],
                        speed: .constant(0)
                    )
                    // While finishing there is no list below the header to end the wash against,
                    // so the 300pt band would cut a hard horizon across an otherwise empty screen.
                    // It spans the whole screen instead — but with a steeper mask, so it still
                    // spends its colour in the top third and leaves the panel on black. Simply
                    // stretching the two-stop gradient tinted the entire screen olive.
                    .mask(
                        LinearGradient(
                            stops: topSheet.isFinishing
                                ? [
                                    .init(color: .black.opacity(0.6), location: 0),
                                    .init(color: .black.opacity(0.16), location: 0.26),
                                    .init(color: .clear, location: 0.58),
                                ]
                                : [
                                    .init(color: .black.opacity(0.6), location: 0),
                                    .init(color: .clear, location: 1),
                                ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: topSheet.isFinishing ? (UIScreen.current?.bounds.height ?? 900) : 300)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(.all)
            )
            // Pure black base: the recorder is presented modally, so the default
            // NavigationStack/ScrollView `systemBackground` is its elevated grey.
            .background(Color.black.ignoresSafeArea())
            // Focusing the note opens the sheet all the way: the note lives above the actions, so
            // the first stop would put the field the finger just tapped behind the edge.
            .onChange(of: isNoteFieldFocused) {
                guard isNoteFieldFocused, !topSheet.isFinishing else { return }
                // A number field never clears the binding when it loses focus (the field taking
                // over is the one that rewrites it), so a text field stealing the keyboard would
                // otherwise leave Next in the toolbar, pointing at a set nobody is typing in.
                focusedIntegerFieldIndex = nil
                settleSheet(to: topSheet.openStop)
            }
            .onChange(of: isFocusingTitleTextfield) {
                if isFocusingTitleTextfield { focusedIntegerFieldIndex = nil }
            }
            .onChange(of: workoutRecorderIsDragging) {
                if workoutRecorderIsDragging {
                    dismissKeyboard()
                } else {
                    // Safety net: whenever the drag settles (dismiss committed or
                    // snapped back), re-enable scrolling and forget the hand-over
                    // baselines even if the gesture's own onEnded didn't fire (e.g.
                    // the scroll pan won the arbitration).
                    listDragActive = false
                    headerDismissBaseline = nil
                    topSheet.dragStart = nil
                    topSheet.isDragging = false
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                KeyboardToolbarItem(onRowBottom: { sheetGeometry.keyboardRowBottomY = $0 }) {
                    keyboardToolbarContent
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
                // The sheet's first reveal comes from the opening scroll: a fresh (or template)
                // start has nothing to scroll and opens at the actions, while a resumed workout
                // opens scrolled to its last set and is therefore closed.

                if preventAutoLock {
                    UIApplication.shared.isIdleTimerDisabled = true
                }

                if isKbdTest {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        if let firstSetID = workoutRecorder.workout?.sets.first?.id {
                            focusedIntegerFieldIndex = IntegerField.Index(setID: firstSetID, secondary: 0, tertiary: 0)
                        }
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

    // MARK: - Set list

    /// Room above the first set group: the closed sheet, its actions stop, and the gap. At the top
    /// of the list the actions are out and the first group rests just below them; scrolling folds
    /// the sheet and moves the rows by the same distance, so that gap never changes.
    private var listTopInset: CGFloat {
        guard !isHeaderHidden else { return 24 }
        return topSheet.closedHeight + topSheet.actionsHeight + RECORDER_SHEET_LIST_GAP
    }

    private func recorderList(for workout: Workout) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
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
                        .padding(.bottom, listBottomClearance)
                        .emptyPlaceholder(workout.setGroups) {
                            Text(NSLocalizedString("addExercisesFromBelow", comment: ""))
                                .foregroundStyle(Color.secondaryLabel)
                                .font(.body)
                                .fontWeight(.medium)
                                .padding(.top, 30)
                        }
                        // Constant: the sheet floats over the list, so nothing here tracks it.
                        // Outside the placeholder, which replaces the content wholesale.
                        .padding(.top, listTopInset)
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
                    // Room to pull the list past the tray. Deliberately OUTSIDE the
                    // anchored content, so opening the recorder (which scrolls to
                    // the bottom of `1`) still lands the last set just above the
                    // sheet — this is only slack the user can scroll into.
                    Color.clear.frame(height: RECORDER_LIST_SCROLL_SLACK)
                }
                // Enough travel for the actions stop to fold away even when a single short set
                // group wouldn't fill the screen — scrolling past them is what closing the sheet
                // at the top of the list is.
                .frame(minHeight: minScrollContentHeight, alignment: .top)
            }
            .scrollPosition($scrollPosition)
            .onAppear {
                if isKbdTest || ProcessInfo.processInfo.arguments.contains("-UITEST_NO_SCROLLTO") { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(1, anchor: .bottom)
                }
            }
            .scrollIndicators(.hidden)
            // Rows dissolve along the sheet's bottom edge as they scroll under it. The mask follows
            // the edge by itself, so the rows never re-lay out while the sheet moves.
            .mask {
                RecorderListFadeMask(model: topSheet)
            }
            // One geometry observer, two jobs: `scrollIsAtTop` gates the list's drag-to-dismiss,
            // and the scroll folds the sheet (see `RecorderTopSheetModel.scrollDidChange`).
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                scrollTracker.offset = newOffset
                let isAtTop = newOffset <= 2
                if scrollIsAtTop != isAtTop { scrollIsAtTop = isAtTop }
                // Lock-step with the finger: never let an animated scroll (the opening scroll to the
                // last set, a focus scroll) turn the fold into a trailing spring.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    topSheet.scrollDidChange(
                        to: newOffset,
                        isFrozen: isNoteFieldFocused || topSheet.isFinishing
                    )
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height
            } action: { _, height in
                if abs(height - listViewportHeight) > 8 { listViewportHeight = height }
            }
            // Freeze the list while a dismiss-drag is in flight so it can't rubber-band against
            // the screen the driver is translating, while the note is being written, and while
            // the finish panel owns the screen.
            .scrollDisabled(listDragActive || isNoteFieldFocused || topSheet.isFinishing)
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
            // The tray only presents once the recorder's morph has landed and
            // hides while the card is being dragged: a presented child sheet
            // would swallow the recorder's own interactive dismissal (UIKit
            // forwards `dismiss` to the presented child). It also steps aside for
            // the finish panel, which runs to the bottom of the screen.
            .sheet(isPresented: Binding(
                get: {
                    workoutRecorderIsSettled
                        && !workoutRecorderIsDragging
                        && !topSheet.isFinishing
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
            // The floating controls' reference edge, measured outside their offset (see
            // `RecorderSheetGeometry.containerBottomY`).
            .overlay(alignment: .bottomTrailing) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY }
                        action: { sheetGeometry.containerBottomY = $0 }
            }
            .overlay(alignment: .bottomTrailing) {
                FloatingChronoControlsOverlay(
                    chronograph: chronograph,
                    workoutRecorder: workoutRecorder,
                    sheetGeometry: sheetGeometry,
                    isAtSmallDetent: exerciseSelectionPresentationDetent == .height(BOTTOM_SHEET_SMALL),
                    onOpenChronoSheet: { isShowingChronoSheet = true },
                    onPauseChronograph: pauseChronograph,
                    onResumeChronograph: resumeChronograph,
                    onStopChronograph: stopChronograph
                )
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.safeAreaInsets.bottom
            } action: { newValue in
                sheetGeometry.safeAreaBottomInset = newValue
            }
            // Run the list to the physical bottom edge, under the tray sheet. The
            // tray's fixed detent (with background interaction) contributes a bottom
            // safe-area inset to the presenting content; ignoring it must wrap the
            // WHOLE scroll stack — applied further in, the outer wrappers (mask,
            // sheet anchor, overlay) still respect the inset and the rows get
            // clipped ~100pt above the screen edge, leaving a black band.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        // The list recedes while the finish panel travels down over it, and stays out of reach
        // (and out of VoiceOver) until Continue brings it back. It stays in the tree so its
        // scroll position — and the sheet's state measured against it — survive the round trip.
        .opacity(topSheet.isFinishing ? 0 : 1)
        .scaleEffect(topSheet.isFinishing ? 0.97 : 1, anchor: .top)
        // The travelling edge wipes the rows away (the list's fade mask follows it), so they must
        // stay visible long enough to be wiped; coming back they are there at once.
        .animation(
            topSheet.isFinishing ? .easeIn(duration: 0.3).delay(0.18) : .easeOut(duration: 0.2),
            value: topSheet.isFinishing
        )
        .allowsHitTesting(!topSheet.isFinishing)
        .accessibilityHidden(topSheet.isFinishing)
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

    private var isKbdTest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITEST_FOCUS_TITLE")
        #else
        return false
        #endif
    }

    // MARK: - Top sheet

    private var topSheetView: some View {
        VStack(spacing: 0) {
            headerCompactRow
                .padding(.horizontal)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    let closed = height + RECORDER_SHEET_CLOSED_CHROME
                    if abs(closed - topSheet.closedHeight) > 0.5 { topSheet.closedHeight = closed }
                }
            if let workout = workoutRecorder.workout {
                RecorderTopSheetPanel(model: topSheet) {
                    VStack(spacing: 13) {
                        RecorderHeaderStatTiles(workout: workout)
                        RecorderHeaderNoteSection(workout: workout, isNoteFieldFocused: $isNoteFieldFocused)
                    }
                } actions: {
                    headerActions(for: workout)
                } finishContent: {
                    finishContent(for: workout)
                } finishBar: {
                    finishActionBar(for: workout)
                }
            }
            // The grab handle sits on the sheet's bottom edge — the seam the panel unfolds from.
            // It keeps its place while finishing (invisible), so the sheet's closed height never
            // changes.
            Capsule()
                .fill(Color.secondaryLabel.opacity(0.5))
                .frame(width: 36, height: 5)
                .opacity(topSheet.isFinishing || exerciseSelectionPresentationDetent == .large ? 0 : 1)
                // Finishing: ride the edge down, and only then go — it is what shows the header is
                // the thing growing.
                .animation(
                    topSheet.isFinishing ? .easeOut(duration: 0.18).delay(0.32) : .easeIn(duration: 0.18),
                    value: topSheet.isFinishing
                )
                .padding(.top, 12)
                .contentShape(Rectangle())
                .onTapGesture { toggleSheet() }
        }
        .padding(.bottom, 10)
        // The whole sheet is one surface: taps between its controls must not fall through to the
        // rows it covers, and a drag anywhere on it moves its edge.
        .contentShape(Rectangle())
        .simultaneousGesture(sheetDragGesture)
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
                    if let workout = workoutRecorder.workout {
                        RecorderSetCountText(workout: workout)
                    }
                }
                .foregroundStyle(.secondary)
                .font(.footnote.weight(.bold).monospacedDigit())
                // The caption is a tap target for folding/unfolding; the title below it keeps
                // its own tap to focus the text field for renaming.
                .contentShape(Rectangle())
                .onTapGesture { toggleSheet() }
                RecorderTopSheetTitleField(
                    model: topSheet,
                    text: workoutName,
                    isFocused: $isFocusingTitleTextfield
                )
            }
            Spacer()
            if let workout = workoutRecorder.workout {
                WorkoutMuscleGroupChart(workout: workout)
                    .animation(.interactiveSpring, value: workout.sets)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSheet() }
            }
        }
        // While finishing, the title row is a handle: pulling it up closes the finish panel.
        .contentShape(Rectangle())
        .gesture(finishDragGesture, isEnabled: topSheet.isFinishing)
    }

    /// Minimize and Finish (Cancel, while nothing is logged). The app's shared secondary/tertiary
    /// button styles, so they match the Add Set capsule and read as the standard action hierarchy.
    private func headerActions(for workout: Workout) -> some View {
        HStack(spacing: 8) {
            Button {
                dismissWorkoutRecorder()
            } label: {
                Label(NSLocalizedString("minimize", comment: ""), systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(TertiaryButtonStyle())
            // Nothing logged yet means there is no session to finish — the action just
            // throws the empty workout away, so it says Cancel rather than promising a
            // finished workout (and skips the finish panel).
            let hasEntries = workout.hasEntries
            Button {
                guard hasEntries else {
                    finishWorkout(shouldSave: false)
                    return
                }
                beginFinishing()
            } label: {
                Label(
                    NSLocalizedString(hasEntries ? "finish" : "cancel", comment: ""),
                    systemImage: hasEntries ? "flag.checkered" : "xmark"
                )
            }
            // Carries the workout's own muscle-group gradient, like the wash behind the
            // panel and the exercise cards below it — an empty workout has no muscle groups,
            // so the gradient falls back to the accent colour on its own.
            .buttonStyle(
                SecondaryButtonStyle(
                    tint: workout.sets.muscleGroupGradientStyle(
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
        }
        // Room above the actions so they read as their own group rather than one more row of the
        // summary. Part of the measured first stop, which is what keeps the buttons off the title.
        .padding(.top, RECORDER_HEADER_ACTIONS_SPACING)
    }

    // MARK: - Sheet gestures

    /// A finger on the sheet moves its edge 1:1, wherever the list is; release snaps to the nearest
    /// stop, or the next one in the direction of a fling. Pulling down on a sheet that is already
    /// all the way out while the list rests at its top has nothing left to open, so past the
    /// engagement distance that pull drags the whole recorder down instead. Measured globally:
    /// once the dismissal has the screen, the header moves with it.
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                // Finishing has its own handles (the title row and the bar), and minimising behind
                // a half-finished workout would be a trap.
                guard !topSheet.isFinishing else { return }
                let translation = value.translation.height
                if topSheet.dragStart == nil {
                    topSheet.dragStart = .init(
                        reveal: topSheet.reveal,
                        scrollOffset: scrollTracker.offset,
                        wasFullyOpen: topSheet.reveal >= topSheet.openStop - 1
                    )
                    topSheet.isDragging = true
                }
                guard let start = topSheet.dragStart else { return }
                if headerDismissBaseline == nil,
                   translation >= RECORDER_DISMISS_ENGAGEMENT_DISTANCE,
                   start.scrollOffset <= 2,
                   start.wasFullyOpen
                {
                    headerDismissBaseline = translation
                    withAnimation(sheetAnimation) { topSheet.reveal = topSheet.openStop }
                }
                if let baseline = headerDismissBaseline {
                    recorderDragDriver.dragChanged(
                        translation: CGSize(width: 0, height: translation - baseline)
                    )
                    return
                }
                topSheet.reveal = RecorderTopSheetModel.rubberBand(
                    start.reveal + translation,
                    upper: topSheet.openStop
                )
            }
            .onEnded { value in
                guard !topSheet.isFinishing, let start = topSheet.dragStart else { return }
                topSheet.dragStart = nil
                if let baseline = headerDismissBaseline {
                    headerDismissBaseline = nil
                    topSheet.isDragging = false
                    recorderDragDriver.dragEnded(
                        translation: CGSize(width: 0, height: value.translation.height - baseline),
                        velocity: CGSize(width: 0, height: value.velocity.height)
                    )
                    return
                }
                let released = min(max(start.reveal + value.translation.height, 0), topSheet.openStop)
                settleSheet(to: topSheet.stop(nearestTo: released, velocity: value.velocity.height))
            }
    }

    /// While finishing: pull the title row up to close the finish panel (Continue), the inverse of the
    /// edge travelling down. Deliberately only the title row — an upward swipe near the bottom of the
    /// screen is how the finish content is scrolled, so the bar must never read it as Continue.
    private var finishDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard topSheet.isFinishing else { return }
                topSheet.isDragging = true
                topSheet.reveal = RecorderTopSheetModel.rubberBand(
                    topSheet.fullReveal + value.translation.height,
                    upper: topSheet.fullReveal
                )
            }
            .onEnded { value in
                guard topSheet.isFinishing else { return }
                if value.translation.height < -80 || value.velocity.height < -800 {
                    endFinishing()
                } else {
                    // Inside the animation: the panel switches from the dragged reveal to the live
                    // full reveal the moment the drag ends, and that switch has to be animated too.
                    withAnimation(finishAnimation) {
                        topSheet.isDragging = false
                        topSheet.reveal = topSheet.fullReveal
                    }
                }
            }
    }

    /// Brings the sheet to rest at `target`.
    ///
    /// In the large-title zone at the top of the list the list moves with it: closing scrolls the
    /// rows up under the closed sheet, opening scrolls them back to the top, so the gap between the
    /// sheet and the first set group ends where it always is. Deeper in the list the sheet simply
    /// opens over the rows and closes off them.
    private func settleSheet(to target: CGFloat) {
        let moveList = topSheet.movesList(whenSettlingTo: target)
        let isClosing = target <= 0.5
        topSheet.isDragging = false
        if isClosing { topSheet.isClosing = true }
        withAnimation(sheetAnimation, completionCriteria: .logicallyComplete) {
            topSheet.reveal = target
            if moveList {
                scrollPosition.scrollTo(y: isClosing ? topSheet.compactStop : 0)
            }
        } completion: {
            if topSheet.reveal <= 0.5 { topSheet.isClosing = false }
        }
    }

    /// Tapping the caption, the handle or the donut toggles the actions stop. Reaching the summary
    /// above them is deliberately a drag: it is the "further" in "pull down further".
    private func toggleSheet() {
        guard !topSheet.isFinishing else { return }
        settleSheet(to: topSheet.reveal > topSheet.compactStop * 0.5 ? 0 : topSheet.compactStop)
    }

    // MARK: - Finishing

    /// Runs the sheet to the bottom of the screen. The tray leaves through its own presentation
    /// binding — it is a bottom sheet over the lower half of the screen, so the panel could not
    /// reach the floor underneath it.
    private func beginFinishing() {
        dismissKeyboard()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // Nothing is seeded: the panel opens on the unrated scale, exactly as Apple's effort
        // screen does. A pre-filled 5 would be a rating nobody gave, and it would be exported to
        // Health as one.
        topSheet.revealBeforeFinishing = max(topSheet.reveal, topSheet.compactStop)
        topSheet.isReturningFromFinish = false
        topSheet.isDragging = false
        withAnimation(finishAnimation) {
            topSheet.isFinishing = true
            topSheet.reveal = topSheet.fullReveal
        }
    }

    /// Back to the workout at the stop Finish was tapped from, with the tray coming back up —
    /// changing your mind costs one tap, not a re-open.
    private func endFinishing() {
        dismissKeyboard()
        topSheet.isReturningFromFinish = true
        topSheet.isDragging = false
        withAnimation(finishAnimation, completionCriteria: .logicallyComplete) {
            topSheet.isFinishing = false
            topSheet.reveal = topSheet.revealBeforeFinishing
        } completion: {
            topSheet.isReturningFromFinish = false
            finishReport = nil
        }
    }

    /// The finish panel's scrolling body: how long, what you did, how it felt, what to change. It
    /// scrolls under the pinned bar, so a long note never pushes End Workout out of reach.
    private func finishContent(for workout: Workout) -> some View {
        ScrollView {
            RecorderFinishPanelContent(
                workout: workout,
                records: finishReport?.exerciseRecords ?? [],
                isNoteFieldFocused: $isNoteFieldFocused
            )
            .padding(.horizontal)
            .padding(.top, 10)
        }
        .contentMargins(.bottom, finishBarHeight + 8, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Records are computed off the back of the travel, not into it. `compute` walks every
        // exercise's whole history on the view context's queue; running it inline stutters the
        // panel's expansion, so it waits for the spring to land and the line fades in after.
        .task {
            guard finishReport == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, topSheet.isFinishing else { return }
            let report = WorkoutProgressReport.compute(for: workout, database: database)
            withAnimation(.snappy(duration: 0.3)) { finishReport = report }
        }
    }

    /// End Workout and Continue Workout, pinned to the sheet's bottom edge over a scrim, so both
    /// stay reachable however long the finish content grows. End Workout is the one real action,
    /// full width; staying is a quiet line under it. The incomplete-set warning lives here rather
    /// than in the scroll because it describes what End Workout is about to throw away.
    private func finishActionBar(for workout: Workout) -> some View {
        let incompleteCount = workout.sets.filter { !$0.hasEntry }.count
        return VStack(spacing: 2) {
            if incompleteCount > 0 {
                Label(
                    String.localizedStringWithFormat(
                        NSLocalizedString("setsIncompleteWillNotBeSaved", comment: ""),
                        incompleteCount
                    ),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
            Button {
                endWorkoutFromFinishPanel()
            } label: {
                Text(NSLocalizedString("endWorkout", comment: ""))
            }
            .buttonStyle(
                SecondaryButtonStyle(
                    tint: workout.sets.muscleGroupGradientStyle(
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .accessibilityIdentifier("finishPanelEndWorkout")
            Button {
                endFinishing()
            } label: {
                Text(NSLocalizedString("continueWorkout", comment: ""))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("finishPanelContinue")
        }
        .padding(.horizontal)
        .padding(.top, 30)
        // The scrim: content scrolling under the bar dissolves over the top 30pt and is fully covered
        // before the bar's own text starts, so the warning never reads on top of the note.
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
                Color.black
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if abs(height - finishBarHeight) > 1 { finishBarHeight = height }
        }
    }

    /// Saves and leaves, carrying over the review prompt the old confirmation sheet owned.
    private func endWorkoutFromFinishPanel() {
        let request = NSFetchRequest<NSNumber>(entityName: "Workout")
        request.resultType = .countResultType
        request.predicate = WorkoutPredicateFactory.getWorkouts()
        let previousWorkoutCount = (try? database.context.count(for: request)) ?? 0

        finishWorkout(shouldSave: true)

        if !wasPromptedToRateApp && previousWorkoutCount > 1 {
            requestReview()
            wasPromptedToRateApp = true
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

    // MARK: - Scroll metrics

    /// Clearance under the last set group so it isn't hidden behind the exercise tray. The
    /// breathing room past it lives in `RECORDER_LIST_SCROLL_SLACK`, outside the anchored
    /// content, so the recorder still opens with the last set resting on the tray's edge.
    private var listBottomClearance: CGFloat {
        exerciseSelectionPresentationDetent == .medium
            ? (UIScreen.current?.bounds.height ?? 0) * 0.5
            : BOTTOM_SHEET_SMALL
    }

    /// Enough content for the actions stop to be scrolled away: the viewport plus that stop, so the
    /// maximum offset always covers it — even for a workout with a single short set group. Built
    /// on the viewport, which the floating sheet never changes, so it is a constant.
    private var minScrollContentHeight: CGFloat {
        guard !isHeaderHidden, listViewportHeight > 0, topSheet.actionsHeight > 0 else { return 0 }
        return listViewportHeight + topSheet.actionsHeight
    }

    // MARK: - List drag-to-dismiss

    /// Latches a dismiss-drag only once the list is resting at its top and the pull has
    /// carried a deliberate `RECORDER_DISMISS_ENGAGEMENT_DISTANCE` downward, then drives the
    /// shared driver with the translation measured from the moment it latched (so the screen
    /// picks up under the finger instead of jumping).
    private func handleListDragChanged(_ value: DragGesture.Value) {
        if !listDragActive {
            guard scrollIsAtTop,
                  value.translation.height >= RECORDER_DISMISS_ENGAGEMENT_DISTANCE,
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
        // This set's own rest is already on the clock.
        guard workoutRecorder.activeRestTimerSet?.objectID != completedSet.objectID else { return }

        // Read at call time instead of via `@AppStorage`: these settings are only consumed
        // here, and an `@AppStorage` subscription re-rendered the whole recorder tree on every
        // write (the timer sheet writes `lastTimerDuration` on each preset/adjustment tap).
        let defaults = UserDefaults.standard
        let lastTimerDuration = defaults.object(forKey: "lastTimerDuration") == nil
            ? 30
            : defaults.integer(forKey: "lastTimerDuration")

        // Decided before anything on the clock is touched: with auto rest off, a timer the
        // athlete started by hand has to keep running.
        guard let autoRestBehavior = workoutRecorder.autoRestBehavior(
            forSet: completedSet,
            usesStopwatch: chronograph.mode == .stopwatch,
            autoRestEnabled: AutoRestSettings.isEnabled(in: defaults),
            timerDuration: lastTimerDuration
        ) else {
            return
        }

        // Now it gives way: a rest for the previous set is written down first, a chronograph
        // started by hand simply stops. Either way the new rest starts — it never used to
        // when something was already running, which looked like the feature misfiring.
        workoutRecorder.endRest(
            using: chronograph,
            reason: .superseded,
            recordingMode: AutoRestSettings.recordingMode(in: defaults)
        )

        workoutRecorder.activeRestTimerSet = completedSet

        switch autoRestBehavior {
        case let .timer(restSeconds):
            chronograph.mode = .timer
            chronograph.setSeconds(Double(restSeconds) + 0.99)
            chronograph.start()
            chronograph.onTimerFired = { [weak chronograph, weak workoutRecorder] in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                guard let chronograph, let workoutRecorder else { return }
                workoutRecorder.endRest(using: chronograph, reason: .timerCompleted)
            }

        case .stopwatch:
            chronograph.mode = .stopwatch
            chronograph.setSeconds(0)
            chronograph.onTimerFired = nil
            chronograph.start()
        }
    }

    /// Holds the rest rather than ending it: `activeRestTimerSet` stays, so resuming continues
    /// the same set's rest and nothing is recorded until it is stopped.
    private func pauseChronograph() {
        guard chronograph.status == .running else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chronograph.stop()
    }

    private func resumeChronograph() {
        guard chronograph.status == .paused, chronographCanResume else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chronograph.start()
    }

    /// A paused timer with nothing left on the clock has nothing to resume — `start()` would
    /// fire it on the first tick.
    private var chronographCanResume: Bool {
        !(chronograph.mode == .timer && Int(chronograph.seconds) == 0)
    }

    /// Ends the rest in either mode, running or paused, through the same funnel as every other
    /// exit. Heavier than pause/resume: this one is final.
    private func stopChronograph() {
        guard chronograph.status != .idle else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        workoutRecorder.endRest(
            using: chronograph,
            reason: .stopped,
            recordingMode: AutoRestSettings.recordingMode()
        )
    }

    private func finishWorkout(shouldSave: Bool) {
        workoutRecorder.endRest(
            using: chronograph,
            reason: shouldSave ? .stopped : .workoutDiscarded,
            recordingMode: AutoRestSettings.recordingMode()
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
        return workoutRecorder.workout?.sets.first { $0.id == focusedIndex.setID }
    }

    /// Where the keyboard's Next button goes from the focused field — see `SetFieldNavigation`.
    func nextIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout, let focusedIndex = focusedIntegerFieldIndex
        else { return nil }
        return SetFieldNavigation.index(after: focusedIndex, in: workout.sets)
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

// MARK: - Header pieces that observe the workout

// Anything in the sheet that walks the workout's sets (a Core Data relationship traversal per set)
// lives in its own workout-observing view: the recorder screen observes the recorder, not the
// managed object, and these bodies must refresh on an edit without the screen re-rendering.

/// The compact row's set count.
private struct RecorderSetCountText: View {
    @ObservedObject var workout: Workout

    var body: some View {
        Text("\(workout.numberOfSets) \(NSLocalizedString("sets", comment: ""))")
    }
}

/// The note as it appears on the *recording* header. Its own view only so it can observe the
/// workout: the recall half of the card has to appear and collapse as the note is written, and
/// the recorder screen itself observes the recorder, not the managed object.
private struct RecorderHeaderNoteSection: View {
    @ObservedObject var workout: Workout
    var isNoteFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        WorkoutNoteField(workout: workout, isFocused: isNoteFieldFocused)
    }
}

/// The finish panel's scrolling body.
///
/// Its own view purely so it can `@ObservedObject` the workout: the recorder screen observes the
/// *recorder*, not the managed object, so a rating tapped into the scale would move the bars (the
/// scale owns that state) while the verdict beside it silently kept saying "not rated".
private struct RecorderFinishPanelContent: View {
    @ObservedObject var workout: Workout
    let records: [WorkoutProgressReport.ExerciseRecords]
    var isNoteFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: SECTION_SPACING) {
            RecorderHeaderStatTiles(workout: workout)

            // With the facts, above the rating: what you just did, and the best of it.
            PersonalRecordsHighlight(workout: workout, records: records)
                .transition(.opacity.combined(with: .move(edge: .top)))

            VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                Text(NSLocalizedString("rateYourEffort", comment: ""))
                    .sectionHeaderStyle2()
                // The rating happens in place here rather than behind a tap: finishing *is* the
                // moment the question is asked. Same bars, same capsule, same description list
                // as the sheet the editor and the detail screen open.
                WorkoutEffortRatingCard(
                    score: Binding(
                        get: { workout.effortScore },
                        set: { workout.effortScore = $0 }
                    ),
                    // Top to bottom, not leading to trailing: the marker is a narrow, tall
                    // capsule, and a horizontal sweep squeezes the whole spectrum into ~25pt.
                    tint: workout.sets.muscleGroupGradientStyle(startPoint: .top, endPoint: .bottom),
                    muscleGroups: workout.muscleGroups
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                Text(NSLocalizedString("note", comment: ""))
                    .sectionHeaderStyle2()
                WorkoutNoteField(
                    workout: workout,
                    isFocused: isNoteFieldFocused,
                    prompt: NSLocalizedString("workoutNotePrompt", comment: ""),
                    lineLimit: 4...12
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Everything the session contained, for a last look before it is written. Read-only:
            // changing a set is what Continue is for.
            VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
                Text(NSLocalizedString("exercises", comment: ""))
                    .sectionHeaderStyle2()
                RecorderFinishExerciseList(workout: workout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Reassurance, not a warning — it scrolls. Its counterpart (sets that will be thrown
            // away) rides the sticky bar below, where it cannot be scrolled past.
            if workout.allSetsHaveEntries {
                Label(
                    NSLocalizedString("allSetsCompleted", comment: ""),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

}

/// The panel's Volume and Repetitions tiles. They appear only once the workout has a logged
/// value — an empty (fresh / template) start shows just the panel's two buttons, so it stays
/// small. Each tile is pared down to the metric name over its value, rendered exactly as the
/// workout detail screen does (`.large` `UnitView`, label-colored number, gray unit): no "This
/// Workout" subtitle, trend pill or run-bar chart, which made the tiles too tall for a header.
private struct RecorderHeaderStatTiles: View {
    @ObservedObject var workout: Workout

    var body: some View {
        if workout.hasEntries {
            HStack(alignment: .top, spacing: 8) {
                tile(.volume)
                tile(.repetitions)
            }
        }
    }

    private func tile(_ metric: WorkoutStatMetric) -> some View {
        let raw = metric.rawValue(of: workout)
        return VStack(alignment: .leading, spacing: 2) {
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            UnitView(
                value: metric.formattedValue(fromRaw: raw),
                unit: metric.unit,
                configuration: .large,
                unitColor: .secondaryLabel
            )
            .foregroundStyle(Color.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CELL_PADDING)
        // Translucent rather than the opaque `tileStyle()`: the tiles float over the header's muscle
        // wash and pick up its colour, but without Liquid Glass's specular rim, which made them the
        // loudest thing on the header.
        .translucentTileStyle()
    }
}

/// One row per set group: the exercise (both, for a superset), its muscle group in colour, and how
/// many of its sets were logged. The finish panel's last section, so the whole session can be
/// checked against memory before End Workout writes it.
private struct RecorderFinishExerciseList: View {
    @ObservedObject var workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(workout.setGroups.enumerated()), id: \.element.objectID) { index, setGroup in
                if index > 0 {
                    Divider().overlay(Color.fill)
                }
                row(for: setGroup)
            }
        }
        .padding(.horizontal, CELL_PADDING)
        .padding(.vertical, 4)
        .translucentTileStyle()
        .accessibilityIdentifier("finishPanelExercises")
    }

    private func row(for setGroup: WorkoutSetGroup) -> some View {
        let exercises = [setGroup.exercise, setGroup.secondaryExercise].compactMap { $0 }
        let logged = setGroup.sets.filter { $0.hasEntry }.count
        let total = setGroup.sets.count
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(exercises.map { $0.displayName }.joined(separator: " + "))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                    .lineLimit(1)
                Text(
                    Set(exercises.compactMap { $0.muscleGroup })
                        .sorted { $0.rawValue < $1.rawValue }
                        .map { $0.description }
                        .joined(separator: " · ")
                )
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(
                    exercises.compactMap { $0.muscleGroup }
                        .weightedSpectrumGradientStyle()
                )
            }
            Spacer(minLength: 0)
            // "3 / 4 sets" only when something is missing; a complete group just says "4 sets".
            Text(
                (logged < total ? "\(logged) / \(total)" : "\(total)")
                    + " " + NSLocalizedString("sets", comment: "").lowercased()
            )
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(logged < total ? Color.secondaryLabel : Color.label)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sheet geometry + floating chrono controls

/// Live geometry of the persistent exercise sheet. Written from the recorder's
/// `onGeometryChange` callbacks and observed ONLY by `FloatingChronoControlsOverlay` — the sheet
/// height changes on every frame of a detent or keyboard animation, and when these values were
/// `@State` on the screen each frame re-rendered the entire recorder tree.
final class RecorderSheetGeometry: ObservableObject {
    @Published var sheetHeight: CGFloat = 0
    /// Where the keyboard accessory's capsules end, when one is on screen — the line the floating
    /// timer lines itself up with. Published here rather than held on the screen so the accessory's
    /// per-frame measurements re-render only the overlay that reads them.
    @Published var keyboardRowBottomY: CGFloat?
    /// The bottom edge of the area the floating controls hang off, in the same space. Measured by a
    /// probe *outside* their offset: a reader inside it would report the offset position and the
    /// offset derived from that would chase its own tail.
    @Published var containerBottomY: CGFloat = 0
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

/// The floating timer/stopwatch button (with its pause/play and stop companions) and the placement math
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
    let onPauseChronograph: () -> Void
    let onResumeChronograph: () -> Void
    let onStopChronograph: () -> Void

    /// Whether a keyboard is on screen. What the slide is keyed on — and what keeps the controls
    /// visible while it happens, since the tray's measured height spikes and re-settles as a
    /// keyboard animates over it, which used to fade them out mid-flight.
    @State private var isKeyboardVisible = false

    /// Measured, not assumed: the controls are a plain circle while idle and a wide pill while a
    /// rest counts down, and the slide has to land on the leading edge either way.
    @State private var controlsWidth: CGFloat = 0

    /// Leading inset while the keyboard is up — the same margin the accessory row's capsules keep
    /// on the other side, so the two read as one row.
    private static let keyboardLeadingInset: CGFloat = 16
    /// The overlay's resting inset from the trailing edge.
    private static let trailingInset: CGFloat = 15

    var body: some View {
        controls
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { controlsWidth = $0 }
            // Never conditionally removed: a view that leaves the hierarchy cannot animate back in,
            // and the guards this replaces (a zero sheet height, a mid-flight opacity fade) all
            // fire exactly while the keyboard is moving.
            .opacity(opacity)
            .padding(.trailing, Self.trailingInset)
            .offset(x: horizontalOffset, y: verticalOffset)
            .animation(
                .easeInOut(duration: sheetGeometry.animationDuration),
                value: sheetGeometry.sheetHeight
            )
            .animation(.easeInOut(duration: sheetGeometry.animationDuration), value: bottomOffset)
            // These two say plainly what is happening; `willChangeFrame`'s end frame does not —
            // after a dismissal it still reported 82 points of the screen covered, which left the
            // controls parked on the left. Both notifications carry the curve and duration UIKit is
            // about to use, and making the change inside that transaction is what has the controls
            // travel *with* the keyboard rather than merely at the same time as it.
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            ) { notification in
                withAnimation(.keyboard(from: notification)) { isKeyboardVisible = true }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            ) { notification in
                withAnimation(.keyboard(from: notification)) { isKeyboardVisible = false }
            }
    }

    private var controls: some View {
        HStack {
            WorkoutRecorderFloatingTimerButton(
                chronograph: chronograph,
                workoutRecorder: workoutRecorder,
                action: onOpenChronoSheet
            )
            // Running: pause. Paused: play, and only then stop beside it. The same in both
            // modes, and one button across pause/play so its glyph morphs in place.
            if chronograph.status != .idle {
                let isRunning = chronograph.status == .running
                WorkoutRecorderFloatingChronoTransportButton(
                    workoutRecorder: workoutRecorder,
                    systemImage: isRunning ? "pause.fill" : "play.fill",
                    accessibilityLabel: NSLocalizedString(isRunning ? "pause" : "continue", comment: ""),
                    isEnabled: isRunning || canResume,
                    action: isRunning ? onPauseChronograph : onResumeChronograph
                )
                .accessibilityIdentifier("recorderFloatingChronoPlayPauseButton")
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            if chronograph.status == .paused {
                WorkoutRecorderFloatingChronoTransportButton(
                    workoutRecorder: workoutRecorder,
                    systemImage: "stop.fill",
                    accessibilityLabel: NSLocalizedString("stop", comment: ""),
                    action: onStopChronograph
                )
                .accessibilityIdentifier("recorderFloatingChronoStopButton")
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        // Declarative, so a status flip from anywhere — the sheet, an auto rest starting, the
        // timer running out — animates the pair, not only a tap here.
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: chronograph.status)
    }

    /// A paused timer with nothing left on the clock has nothing to resume.
    private var canResume: Bool {
        !(chronograph.mode == .timer && Int(chronograph.seconds) == 0)
    }

    /// Hidden while the recorder is being dragged, and before the tray has been measured — but
    /// never while a keyboard is on screen: the tray's measured height swings wildly as one opens
    /// over it, and `toolbarOpacity`'s fade would take the controls away exactly mid-slide.
    private var opacity: CGFloat {
        if workoutRecorderIsDragging { return 0 }
        if isKeyboardVisible { return 1 }
        return sheetGeometry.sheetHeight > 0 ? sheetGeometry.toolbarOpacity : 0
    }

    /// How far left of its resting place the controls sit. Zero with no keyboard; with one, exactly
    /// enough to put their leading edge on `keyboardLeadingInset`.
    ///
    /// Derived from the measured width rather than stored, so a timer that starts counting while
    /// parked on the left widens to the right instead of drifting: the trailing anchoring moves the
    /// controls left by the same amount this offset gives back.
    private var horizontalOffset: CGFloat {
        guard isKeyboardVisible,
              controlsWidth > 0,
              let screenWidth = UIScreen.current?.bounds.width
        else { return 0 }
        let travel = screenWidth - Self.trailingInset - controlsWidth - Self.keyboardLeadingInset
        return -max(0, travel)
    }

    /// Riding the top of the tray with no keyboard; sitting *in* the accessory row when there is
    /// one, by lining this control's bottom edge up with the row's own.
    ///
    /// Both edges are measured, neither derived: the keyboard's reported frame begins a capsule's
    /// height above the row (a gap that is the system's, not ours, to define), and this overlay's
    /// container is the list area above the tray rather than the screen. Two measurements in one
    /// coordinate space subtract cleanly; two assumptions would not.
    private var verticalOffset: CGFloat {
        if isKeyboardVisible, let rowBottom = sheetGeometry.keyboardRowBottomY {
            return rowBottom - sheetGeometry.containerBottomY
        }
        return -sheetGeometry.sheetHeight + bottomOffset
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
