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

    /// One iOS context-menu dismissal animation. The date/time editor is deferred by this long
    /// after its menu item is tapped so its (sheet-on-sheet) presentation doesn't overlap the
    /// menu closing; see the "Edit date & time" button.
    private static let menuDismissAnimationDuration: TimeInterval = 0.35

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
    @State private var selectedRestDurationSet: WorkoutSet?
    @State private var isShowingReorderSheet = false
    @State private var exerciseForDetailSheet: Exercise?
    /// Whether the persistent exercise tray lets touches through to the editor behind it.
    /// Driven by `hasNestedTraySheet` with an asymmetric delay — see that property's docs.
    @State private var trayAllowsBackgroundInteraction = true

    // MARK: - Parameters

    @StateObject var workout: Workout
    let isAddingNewWorkout: Bool
    var isImportedWorkout: Bool = false

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
                .clipShape(ConcentricRectangle(corners: .concentric, isUniform: true))
                .padding()
            }
            ScrollViewReader { _ in
                ScrollView {
                    VStack(spacing: SECTION_SPACING) {
                        // Shared with you banner for imported workouts
                        if isImportedWorkout {
                            SharedWithYouBanner(
                                title: NSLocalizedString("sharedWorkout", comment: ""),
                                subtitle: NSLocalizedString("sharedWorkoutDescription", comment: "")
                            )
                        }
                        
                        VStack(spacing: CELL_SPACING) {
                            WorkoutSetGroupList(
                                workout: workout,
                                focusedIntegerFieldIndex: $focusedIntegerFieldIndex,
                                canReorder: true,
                                reduceShadow: true,
                                showDetailAsSheet: true,
                                // Defer the flag to the next runloop turn so the set-group Menu's
                                // dismissal and the reorder sheet's presentation land in separate
                                // transactions — flipping it synchronously inside the Menu action
                                // entangles the two and, because the reorder sheet is a sheet-on-sheet,
                                // the entanglement keeps it from ever presenting (same reason as the
                                // editDateTime button below).
                                onReorderSetGroups: {
                                    DispatchQueue.main.async {
                                        isShowingReorderSheet = true
                                    }
                                },
                                onTapPreviousSet: { exerciseForDetailSheet = $0 }
                            )
                            .padding(.bottom, exerciseSelectionPresentationDetent == .medium ? (UIScreen.current?.bounds.height ?? 0) * 0.5 : BOTTOM_SHEET_SMALL)
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
                    // Structured like the recorder's tray (sheet chain directly off the
                    // NavigationStack root) — see TemplateEditorScreen for why: the old
                    // NavigationView + wrapper made nested sheets fight the tray.
                    NavigationStack {
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
                            currentWorkoutExercises: workout.exercises,
                            supersetPrimaryExercise: nil,
                            presentationDetentSelection: $exerciseSelectionPresentationDetent
                        )
                        .toolbar(.hidden, for: .navigationBar)
                        .sheet(item: $selectedRestDurationSet) { workoutSet in
                            RestDurationEditorSheet(workoutSet: workoutSet)
                                .presentationDetents([.fraction(0.65)])
                                .padding()
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .sheet(item: $exerciseForDetailSheet) { exercise in
                            NavigationStack {
                                ExerciseDetailScreen(exercise: exercise, isShowingAsSheet: true, scrollToRecentAttempts: true)
                            }
                            .presentationDragIndicator(.visible)
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
                    }
                    .presentationDetents([.height(BOTTOM_SHEET_SMALL), .medium, .large], selection: $exerciseSelectionPresentationDetent)
                    // Pass-through only while nothing is stacked on the tray: a
                    // background-interactive sheet can't stably host a nested sheet — UIKit
                    // dismisses the tray, SwiftUI re-presents it, and the nested sheet
                    // flashes away in the fight (see TemplateEditorScreen).
                    .presentationBackgroundInteraction(
                        trayAllowsBackgroundInteraction ? .enabled : .disabled
                    )
                    .interactiveDismissDisabled()
                    .sheet(isPresented: $isEditingStartEndDate) {
                        WorkoutStartEndDateEditorSheet(
                            workout: workout,
                            isPresented: $isEditingStartEndDate
                        )
                    }
                }
                // Asymmetric switch for the tray's pass-through: off the moment a nested
                // sheet presents, back on only after the nested sheet's dismissal transition
                // has settled — reconfiguring the tray's presentation mid-dismissal makes
                // UIKit cancel that dismissal and the nested sheet springs back
                // (see TemplateEditorScreen).
                .onChange(of: hasNestedTraySheet) { _, hasNested in
                    if hasNested {
                        trayAllowsBackgroundInteraction = false
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            if !hasNestedTraySheet {
                                trayAllowsBackgroundInteraction = true
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isRenamingWorkout)
            .interactiveDismissDisabled(true)
            .presentationBackground(.thickMaterial)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedTextField = .workoutName
                            }
                            isRenamingWorkout = true
                            exerciseSelectionPresentationDetent = .height(BOTTOM_SHEET_SMALL)
                        } label: {
                            Label(NSLocalizedString("rename", comment: ""), systemImage: "pencil")
                        }
                        Button {
                            // Present only after the menu's dismissal animation has finished. The date
                            // editor is a sheet-on-sheet (it opens from the always-present exercise
                            // selection sheet), so its presentation is fragile while another transition
                            // is in flight: flipping the flag synchronously made it bounce in and out,
                            // and deferring by a single runloop turn (`main.async`) still overlapped the
                            // menu dismissal — the dismissal then cancelled the presentation and nothing
                            // appeared. Waiting one menu-animation cycle lets the two stay separate.
                            DispatchQueue.main.asyncAfter(deadline: .now() + Self.menuDismissAnimationDuration) {
                                isEditingStartEndDate = true
                            }
                        } label: {
                            Label(NSLocalizedString("editDateTime", comment: ""), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                    } label: {
                        HStack {
                            VStack {
                                Text((workout.name?.isEmpty ?? true) ? Workout.getStandardName(for: workout.date ?? .now) : workout.name!)
                                    .foregroundStyle(Color.label)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(workout.date?.formatted(.dateTime.day().month().year()) ?? "")
                                    if let workoutDurationString {
                                        Text("•")
                                        Text(workoutDurationString)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                            }
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.secondaryLabel)
                        }
                        .frame(maxWidth: isImportedWorkout ? 140 : 200)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isImportedWorkout ? NSLocalizedString("addToHistory", comment: "") : NSLocalizedString("save", comment: "")) {
                        if workout.name?.isEmpty ?? true || workout.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" == "", let date = workout.date {
                            workout.name = Workout.getStandardName(for: date)
                        }
                        // Unflag exercises and workout if this is an imported workout
                        if isImportedWorkout {
                            workout.exercises.forEach { database.unflagAsTemporary($0) }
                            database.unflagAsTemporary(workout)
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
                                // Defer — same transaction entanglement as the
                                // editDateTime button above.
                                DispatchQueue.main.async {
                                    isShowingReorderSheet = true
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                                    .keyboardToolbarButtonStyle()
                            }
                            Button {
                                focusedIntegerFieldIndex = nil
                            } label: {
                                Image(systemName: "keyboard.chevron.compact.down")
                                    .keyboardToolbarButtonStyle()
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Guarantee a start date (a workout's place in history); `newWorkout()` already sets
                // one, this is just defensive. The end date stays untouched — duration is optional,
                // so a workout with none is saved without one rather than getting a fabricated value.
                if workout.date == nil {
                    workout.date = .now
                }
                refreshOnChange()
                exerciseSelectionPresentationDetent = workout.isEmpty ? .medium : .height(BOTTOM_SHEET_SMALL)
            }
        }
    }

    // MARK: - Computed Properties

    /// True while any sheet is stacked on the persistent exercise tray.
    private var hasNestedTraySheet: Bool {
        selectedRestDurationSet != nil
            || exerciseForDetailSheet != nil
            || isShowingReorderSheet
            || isEditingStartEndDate
    }

    private var workoutName: Binding<String> {
        Binding(get: { workout.name ?? "" }, set: { workout.name = $0 })
    }

    /// The header's duration string, or nil when the workout has no end date — a workout without a
    /// logged duration shows no duration rather than a fabricated "0:00".
    private var workoutDurationString: String? {
        guard let start = workout.date, let end = workout.endDate else { return nil }
        let hours = Calendar.current.dateComponents([.hour], from: start, to: end).hour ?? 0
        let minutes =
            (Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0) % 60
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
    }

    private var canSaveWorkout: Bool {
        workout.canBeSavedToHistory
    }

    // MARK: - Autosave

    private func refreshOnChange() {
        // Throttled: typing into a set field fires a context change per
        // keystroke, and rebroadcasting each one re-rendered the whole screen
        // per digit (see the recorder's autosave pipeline for the same fix).
        cancellable = NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: database.context)
            .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: true)
            .sink { _ in
                self.workout.objectWillChange.send()
            }
    }
}

// MARK: - Start/End Date Editor Sheet

/// Edits the workout's start and end dates.
///
/// The pickers write to local `@State` rather than directly to the Core Data
/// `workout`. Writing through to `workout` on every scrub tick fires
/// `NSManagedObjectContextObjectsDidChange`, which `WorkoutEditorScreen`
/// rebroadcasts as a full-screen `objectWillChange`, re-rendering the sheet's
/// presenter on every value change and making the sheet animate in and out.
/// Holding the values locally and committing once on dismiss avoids that storm.
private struct WorkoutStartEndDateEditorSheet: View {
    let workout: Workout
    @Binding var isPresented: Bool

    @State private var start: Date
    @State private var end: Date

    init(workout: Workout, isPresented: Binding<Bool>) {
        self.workout = workout
        self._isPresented = isPresented
        self._start = State(initialValue: workout.date ?? .now)
        self._end = State(initialValue: workout.endDate ?? .now)
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack {
                Text(NSLocalizedString("editTime", comment: ""))
                    .font(.title)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button {
                    isPresented = false
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
                    selection: $start,
                    in: ...end,
                    displayedComponents: [.date, .hourAndMinute]
                )

                DatePicker(
                    NSLocalizedString("end", comment: ""),
                    selection: $end,
                    in: start...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Divider()
                HStack {
                    Label(NSLocalizedString("duration", comment: ""), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Spacer()
                    Text(durationString)
                        .padding(.trailing)
                }
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .presentationDetents([.fraction(0.35)])
        .onDisappear {
            if workout.date != start { workout.date = start }
            if workout.endDate != end { workout.endDate = end }
        }
    }

    private var durationString: String {
        let hours = Calendar.current.dateComponents([.hour], from: start, to: end).hour ?? 0
        let minutes =
            (Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0) % 60
        return "\(hours):\(minutes < 10 ? "0" : "")\(minutes)"
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
            }
    }
}

#Preview {
    PreviewWrapperView()
        .previewEnvironmentObjects()
}
