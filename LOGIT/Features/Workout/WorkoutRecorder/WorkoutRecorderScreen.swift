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
    /// Translation at which a drag on an already-extended header handed over to the
    /// recorder's dismissal (non-nil while that hand-over is in flight).
    @State private var headerDismissBaseline: CGFloat?

    @FocusState var isFocusingTitleTextfield: Bool

    /// The workout title's font size, folded vs. unfolded — Dynamic-Type-scaled and interpolated
    /// through `AnimatableTitleFont` so the title grows/shrinks smoothly instead of snapping.
    @ScaledMetric(relativeTo: .body) private var collapsedTitleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .title2) private var expandedTitleSize: CGFloat = 22
    /// Natural (fully-revealed) height of the stats panel, measured the first time it is laid
    /// out and cached, so the fold always knows what it is working against.
    @State private var headerPanelHeight: CGFloat = 0
    /// How far the list is scrolled past the panel, 0…`headerPanelHeight` — the scroll offset,
    /// clamped. This is what the scroll content compensates for, and it never takes a drag or a
    /// pull-open into account: the content has to stay put when the header changes because of
    /// *scrolling*, and it should be pushed when the header changes because of a *finger*.
    @State private var headerScrollFold: CGFloat = 0
    /// How much of the panel is folded away, measured from `headerFoldOrigin`. Written with no
    /// animation, so the panel contracts in lock-step with the finger, and it behaves the same
    /// wherever the list happens to be.
    @State private var headerOriginFold: CGFloat = 0
    /// The offset the panel counts as fully open at — the top of the list, until it is pulled
    /// open somewhere inside the content, and back to the top as soon as the scroll has folded
    /// it away again. Only a finger ever moves it, so nothing can drift.
    @State private var headerFoldOrigin: CGFloat = 0
    /// Non-nil while a finger is dragging the header: the live vertical translation, added to
    /// the fold so the panel tracks the finger 1:1 (a real drag, not a threshold swipe).
    @State private var headerDragTranslation: CGFloat?
    /// The list's live scroll offset. A plain box rather than `@State`: it changes on every
    /// scroll frame, and only the derived fold — which stops changing once the panel is fully
    /// folded — should invalidate the screen.
    @State private var scrollTracker = RecorderScrollTracker()
    /// Scroll offset when a drag on the header began — only a pull that starts at the top of
    /// the list, where the panel has nothing left to unfold, may hand over to the dismissal.
    @State private var headerDragStartOffset: CGFloat?
    /// The scroll viewport's height with the panel fully folded away. Constant while the panel
    /// contracts (the viewport grows exactly as much as the panel shrinks), so the minimum
    /// content height built on it doesn't chase the fold.
    @State private var foldedViewportHeight: CGFloat = 0
    /// Drives the programmatic scroll that folds the panel away from the top of the list —
    /// scrolling past the panel is what folding it *is*.
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    /// One spring for every path that folds or unfolds the header.
    private var headerExpansionAnimation: Animation { .spring(response: 0.4, dampingFraction: 0.85) }

    /// How much of the panel is currently shown — everything the fold hasn't taken, plus the
    /// live drag, clamped to the panel's natural height.
    private var headerPanelRevealHeight: CGFloat {
        let base = max(headerPanelHeight - headerOriginFold, 0)
        guard let translation = headerDragTranslation else { return base }
        return min(max(base + translation, 0), headerPanelHeight)
    }

    /// 0 folded … 1 fully unfolded — drives everything that has to move *with* the contraction
    /// (the title size) rather than snap at the ends.
    private var headerRevealFraction: CGFloat {
        guard headerPanelHeight > 0 else { return 1 }
        return min(max(headerPanelRevealHeight / headerPanelHeight, 0), 1)
    }

    private var headerIsFullyRevealed: Bool {
        headerPanelHeight > 0 && headerPanelRevealHeight >= headerPanelHeight - 0.5
    }

    /// Whether the panel is in the view tree at all. Kept out once it is fully folded so its
    /// Finish / Minimize actions leave the accessibility tree (and XCUITest) — but present
    /// while it has never been measured, so the first layout can size it, and while a finger
    /// is pulling it back out of nothing.
    private var headerPanelIsPresent: Bool {
        headerPanelHeight == 0 || headerDragTranslation != nil || headerPanelRevealHeight > 0
    }

    /// Unfolds the panel where the list currently rests: the fold is measured from here on, so
    /// scrolling down from this point contracts it exactly as it does from the top.
    private func openHeaderPanel() {
        headerFoldOrigin = scrollTracker.offset
        headerOriginFold = 0
    }

    /// Folds the panel away by handing the fold back to the list's real scroll position. At the
    /// top of the list there is nothing to hand back — the panel lives there — so folding it
    /// means scrolling past it.
    private func foldHeaderPanel() {
        guard headerFoldOrigin != 0 else {
            if headerPanelHeight > 0 { scrollPosition.scrollTo(y: headerPanelHeight) }
            return
        }
        headerFoldOrigin = 0
        headerOriginFold = min(max(scrollTracker.offset, 0), headerPanelHeight)
    }

    /// Tapping the caption, the handle or the donut folds or unfolds the panel in place.
    private func toggleHeaderExpansion() {
        withAnimation(headerExpansionAnimation) {
            if headerRevealFraction > 0.5 { foldHeaderPanel() } else { openHeaderPanel() }
        }
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
                                    // Clear the fade band along the viewport's top edge so rows
                                    // resting at the top aren't half-dissolved. The fold is
                                    // added back on top: the viewport grows by exactly as much
                                    // as the panel folds away, and without giving that back to
                                    // the content the rows would travel at twice the speed of
                                    // the finger.
                                    .padding(.top, 24 + headerScrollFold)
                                    .padding(.bottom, listBottomClearance)
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
                                // Room to pull the list past the tray. Deliberately OUTSIDE the
                                // anchored content, so opening the recorder (which scrolls to
                                // the bottom of `1`) still lands the last set just above the
                                // sheet — this is only slack the user can scroll into.
                                Color.clear.frame(height: RECORDER_LIST_SCROLL_SLACK)
                            }
                            // Enough travel for the panel to fold away even when a single short
                            // set group wouldn't fill the screen: without it the list has nothing
                            // to scroll and the header can only be rubber-banded against.
                            .frame(minHeight: minScrollContentHeight, alignment: .top)
                        }
                        // Folding and unfolding the panel is a scroll, so the taps and the
                        // header drag drive it through here.
                        .scrollPosition($scrollPosition)
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
                        // drag-to-dismiss, and the scroll drives the fold. The fold is the
                        // offset measured from wherever the panel was last opened, clamped —
                        // no latch and no boolean, so scrolling down contracts the header
                        // identically wherever the list happens to be, whether the panel got
                        // there by resting at the top or by being pulled open mid-list.
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.contentOffset.y + geometry.contentInsets.top
                        } action: { _, newOffset in
                            scrollTracker.offset = newOffset
                            let isAtTop = newOffset <= 2
                            if scrollIsAtTop != isAtTop { scrollIsAtTop = isAtTop }
                            if isAtTop, headerFoldOrigin != 0 { headerFoldOrigin = 0 }
                            let scrollFold = min(max(newOffset, 0), headerPanelHeight)
                            // Sub-point deltas are float noise, and once the panel is fully
                            // folded these values stop changing — so scrolling on through the
                            // list doesn't re-render the screen at all.
                            if abs(scrollFold - headerScrollFold) > 0.5 { headerScrollFold = scrollFold }
                            // A finger on the header owns the reveal while it is down.
                            guard headerDragTranslation == nil else { return }
                            var fold = min(max(newOffset - headerFoldOrigin, 0), headerPanelHeight)
                            if fold >= headerPanelHeight, headerFoldOrigin != 0 {
                                // Scrolled past it again: the panel goes back to living at the
                                // top of the list, so it can't reappear halfway down.
                                headerFoldOrigin = 0
                                fold = scrollFold
                            }
                            if abs(fold - headerOriginFold) > 0.5 { headerOriginFold = fold }
                        }
                        // The viewport with the panel folded away — the reference the content's
                        // minimum height is built on. Adding the live reveal back keeps it
                        // constant while the panel contracts.
                        .onScrollGeometryChange(for: CGFloat.self) { geometry in
                            geometry.containerSize.height
                        } action: { _, height in
                            let folded = height + headerPanelRevealHeight
                            if abs(folded - foldedViewportHeight) > 8 { foldedViewportHeight = folded }
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
                        // Run the list to the physical bottom edge, under the tray sheet. The
                        // tray's fixed detent (with background interaction) contributes a bottom
                        // safe-area inset to the presenting content; ignoring it must wrap the
                        // WHOLE scroll stack — applied further in, the outer wrappers (mask,
                        // sheet anchor, overlay) still respect the inset and the rows get
                        // clipped ~100pt above the screen edge, leaving a black band.
                        .ignoresSafeArea(.container, edges: .bottom)
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
                    // snapped back), re-enable scrolling and forget the hand-over
                    // baselines even if the gesture's own onEnded didn't fire (e.g.
                    // the scroll pan won the arbitration).
                    listDragActive = false
                    headerDismissBaseline = nil
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
                // The panel's state comes from the scroll alone, so the opening scroll decides
                // it: a fresh (or template) start has nothing to scroll and leads with the
                // session panel, while a resumed workout opens scrolled to its last set and
                // is therefore already compact.

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
                if let workout = workoutRecorder.workout, headerPanelIsPresent {
                    headerExpandedPanel(for: workout)
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .onChange(of: geometry.size.height, initial: true) { _, height in
                                        guard height > 0, height != headerPanelHeight else { return }
                                        headerPanelHeight = height
                                        // Both folds are clamped to the panel's height, so they
                                        // were pinned at 0 until this first measurement —
                                        // re-derive them from wherever the list already sits, or
                                        // a recorder that opened scrolled into the list would
                                        // show the panel it has long since scrolled past.
                                        let fold = min(max(scrollTracker.offset - headerFoldOrigin, 0), height)
                                        headerScrollFold = min(max(scrollTracker.offset, 0), height)
                                        headerOriginFold = fold
                                    }
                            }
                        )
                        .frame(height: headerPanelRevealHeight, alignment: .top)
                        .clipped()
                        .opacity(headerPanelHeight > 0 ? headerRevealFraction : 1)
                        .allowsHitTesting(headerIsFullyRevealed)
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
        // A finger on the header pulls the panel open or closed 1:1 (simultaneous, so the title
        // field and the caption's own tap still work) — wherever the list is, not only at its
        // top; release snaps to whichever side the current reveal and the fling velocity
        // favour, and the fold then measures from there, so scrolling down contracts it exactly
        // as it does from the top. Pulling down on a header that is already fully out AND
        // resting at the top of the list has nothing left to open, so past the engagement
        // distance that pull drags the whole recorder down instead. Measured globally: once the
        // dismissal has the screen, the header moves with it.
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    let translation = value.translation.height
                    let startOffset = headerDragStartOffset ?? {
                        let offset = scrollTracker.offset
                        headerDragStartOffset = offset
                        return offset
                    }()
                    if headerDismissBaseline == nil,
                       translation >= RECORDER_DISMISS_ENGAGEMENT_DISTANCE,
                       startOffset <= 2,
                       headerOriginFold <= 0.5
                    {
                        headerDragTranslation = nil
                        headerDismissBaseline = translation
                    }
                    guard let baseline = headerDismissBaseline else {
                        headerDragTranslation = translation
                        return
                    }
                    recorderDragDriver.dragChanged(
                        translation: CGSize(width: 0, height: translation - baseline)
                    )
                }
                .onEnded { value in
                    headerDragStartOffset = nil
                    if let baseline = headerDismissBaseline {
                        headerDismissBaseline = nil
                        recorderDragDriver.dragEnded(
                            translation: CGSize(width: 0, height: value.translation.height - baseline),
                            velocity: CGSize(width: 0, height: value.velocity.height)
                        )
                        return
                    }
                    let base = max(headerPanelHeight - headerOriginFold, 0)
                    let revealed = min(max(base + value.translation.height, 0), headerPanelHeight)
                    let fraction = headerPanelHeight > 0 ? revealed / headerPanelHeight : 0
                    let open: Bool
                    if value.velocity.height > 400 {
                        open = true
                    } else if value.velocity.height < -400 {
                        open = false
                    } else {
                        open = fraction >= 0.5
                    }
                    withAnimation(headerExpansionAnimation) {
                        headerDragTranslation = nil
                        if open { openHeaderPanel() } else { foldHeaderPanel() }
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
                    if let workout = workoutRecorder.workout {
                        RecorderSetCountText(workout: workout)
                    }
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
                // Grows into a large-title as the panel opens: the size rides the reveal
                // fraction, so it scales with the scroll's contraction instead of snapping
                // between the two ends (and `AnimatableTitleFont` interpolates the tap and
                // drag-settle springs on top).
                .modifier(
                    AnimatableTitleFont(
                        size: collapsedTitleSize + (expandedTitleSize - collapsedTitleSize) * headerRevealFraction
                    )
                )
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
    /// above the Minimize and Finish (Cancel, while nothing is logged) actions. The tiles appear
    /// only once the workout has a logged value — an empty (fresh / template) start shows just
    /// the two buttons, so the panel stays small. The actions use the app's shared secondary/primary button styles, so they
    /// match the Add Set button's capsule height and read as the standard action hierarchy.
    private func headerExpandedPanel(for workout: Workout) -> some View {
        VStack(spacing: 8) {
            RecorderHeaderStatTiles(workout: workout)
            HStack(spacing: 8) {
                Button {
                    dismissWorkoutRecorder()
                } label: {
                    Label(NSLocalizedString("minimize", comment: ""), systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(TertiaryButtonStyle())
                // Nothing logged yet means there is no session to finish — the action just
                // throws the empty workout away, so it says Cancel rather than promising a
                // finished workout (and skips the finish confirmation).
                let hasEntries = workout.hasEntries
                Button {
                    guard hasEntries else {
                        finishWorkout(shouldSave: false)
                        return
                    }
                    isShowingFinishConfirmation = true
                } label: {
                    Label(
                        NSLocalizedString(hasEntries ? "finish" : "cancel", comment: ""),
                        systemImage: hasEntries ? "flag.checkered" : "xmark"
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
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

    // MARK: - Scroll metrics

    /// Clearance under the last set group so it isn't hidden behind the exercise tray. The
    /// breathing room past it lives in `RECORDER_LIST_SCROLL_SLACK`, outside the anchored
    /// content, so the recorder still opens with the last set resting on the tray's edge.
    private var listBottomClearance: CGFloat {
        exerciseSelectionPresentationDetent == .medium
            ? (UIScreen.current?.bounds.height ?? 0) * 0.5
            : BOTTOM_SHEET_SMALL
    }

    /// Enough content for the panel to be scrolled fully away: the panel-less viewport plus
    /// the panel's own height, so `maxContentOffset` is never smaller than the fold — even
    /// for a workout with a single short set group.
    private var minScrollContentHeight: CGFloat {
        guard foldedViewportHeight > 0, headerPanelHeight > 0 else { return 0 }
        return foldedViewportHeight + headerPanelHeight
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
        return workoutRecorder.workout?.sets.first { $0.id == focusedIndex.setID }
    }

    func nextIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout,
              let focusedIndex = focusedIntegerFieldIndex,
              let position = workout.sets.firstIndex(where: { $0.id == focusedIndex.setID })
        else { return nil }
        // Advance entry by entry within the set (drops, super set sides), then set by set.
        let focusedWorkoutSet = workout.sets[position]
        if focusedIndex.secondary + 1 < focusedWorkoutSet.entryValues.count {
            return clampedIndex(
                for: focusedWorkoutSet,
                secondary: focusedIndex.secondary + 1,
                tertiary: focusedIndex.tertiary
            )
        }
        guard let nextSet = workout.sets.value(at: position + 1) else { return nil }
        return clampedIndex(for: nextSet, secondary: 0, tertiary: focusedIndex.tertiary)
    }

    func previousIntegerFieldIndex() -> IntegerField.Index? {
        guard let workout = workoutRecorder.workout,
              let focusedIndex = focusedIntegerFieldIndex,
              let position = workout.sets.firstIndex(where: { $0.id == focusedIndex.setID })
        else { return nil }
        guard focusedIndex.secondary == 0 else {
            return clampedIndex(
                for: workout.sets[position],
                secondary: focusedIndex.secondary - 1,
                tertiary: focusedIndex.tertiary
            )
        }
        guard position > 0 else { return nil }
        let previousSet = workout.sets[position - 1]
        return clampedIndex(
            for: previousSet,
            secondary: max(0, previousSet.entryValues.count - 1),
            tertiary: focusedIndex.tertiary
        )
    }

    /// Builds a focus index whose field column is clamped to the target entry's fields —
    /// moving from a two-field reps+weight row onto a single-field reps-only row lands on
    /// that row's last field instead of dropping focus.
    private func clampedIndex(
        for workoutSet: WorkoutSet, secondary: Int, tertiary: Int
    ) -> IntegerField.Index? {
        guard let setID = workoutSet.id else { return nil }
        let targetType = workoutSet.entryValues.value(at: secondary)?.type ?? .repsAndWeight
        return IntegerField.Index(
            setID: setID,
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

// MARK: - Header pieces that must not re-derive per scroll frame

// The header re-renders on every frame of a scroll-linked fold. Anything in it that walks the
// workout's sets (a Core Data relationship traversal per set) therefore lives in its own
// workout-observing view: the fold rebuilds the same view value, so SwiftUI skips these
// bodies, while a real edit still publishes through the workout and refreshes them.

/// The compact row's set count.
private struct RecorderSetCountText: View {
    @ObservedObject var workout: Workout

    var body: some View {
        Text("\(workout.numberOfSets) \(NSLocalizedString("sets", comment: ""))")
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
        // Liquid Glass rather than the usual opaque `tileStyle()`: the tiles float over the
        // header's ambient muscle wash, so the clear glass picks up the workout's colours and
        // its specular rim separates them from the backdrop without a solid fill.
        .glassEffect(.clear, in: .rect(cornerRadius: 30))
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

/// Animates a bold title's point size: because `size` is the `animatableData`, SwiftUI
/// interpolates it frame-by-frame inside a `withAnimation`, so the workout title scales
/// smoothly between its folded and unfolded sizes instead of snapping.
private struct AnimatableTitleFont: ViewModifier, Animatable {
    var size: CGFloat

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .bold))
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
