//
//  WorkoutDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 20.12.21.
//

import ColorfulX
import Combine
import CoreData
import SwiftUI

struct WorkoutDetailScreen: View {
    enum SheetType: Int, Identifiable {
        case workoutEditor
        var id: Int { rawValue }
    }

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var healthKitSyncManager: HealthKitSyncManager

    // MARK: - State

    @AppStorage(CalorieEstimator.enabledKey) private var calorieEstimatesEnabled = true

    @State private var isShowingDeleteWorkoutAlert: Bool = false
    @State private var sheetType: SheetType? = nil
    @State private var newTemplateFromWorkout: Template?
    @State private var selectedTemplate: Template?
    @State private var selectedStatMetric: WorkoutStatMetric?
    @State private var headerTextHeight: CGFloat = 64
    @State private var progressReport: WorkoutProgressReport?
    @State private var calorieEstimate: CalorieEstimator.Estimate?
    @State private var calorieBodyWeightMissing = false
    @State private var isShowingPersonalRecords: Bool = false
    @State private var workoutShareFileURL: URL?
    @State private var templateShareFileURL: URL?
    @State private var isRatingEffort = false

    // MARK: - Variables

    @StateObject var workout: Workout
    let canNavigateToTemplate: Bool

    /// Top to bottom, not leading to trailing: the effort marker is a narrow, tall capsule, and a
    /// horizontal sweep would squeeze the whole spectrum into ~25pt.
    private var effortTint: AnyShapeStyle {
        workout.sets.muscleGroupGradientStyle(startPoint: .top, endPoint: .bottom)
    }
    
    // MARK: - Sharing Service
    
    private var sharingService: WorkoutSharingService {
        WorkoutSharingService(database: database)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                workoutHeader

                VStack(spacing: 10) {
                    WorkoutStatTileGrid(workout: workout) { metric in
                        selectedStatMetric = metric
                    }
                    if calorieEstimatesEnabled {
                        WorkoutCalorieRow(
                            workout: workout,
                            estimate: calorieEstimate,
                            isMissingBodyWeight: calorieBodyWeightMissing
                        )
                    }
                    progressAndVolumeRow
                    // Effort is the one thing on this screen that can still be answered, so it
                    // shows even unrated — as "Add Effort", opening the same rating screen the
                    // recorder and the editor open. The note has no such invitation: an old
                    // workout that was never annotated shouldn't grow an empty slot on a screen
                    // that is otherwise all things that happened.
                    WorkoutEffortTile(score: workout.effortScore, tint: effortTint, style: .tile) {
                        isRatingEffort = true
                    }
                    if let note = workout.note, workout.hasNote {
                        WorkoutNoteCard(note: note)
                    }
                }

                VStack(spacing: SECTION_HEADER_SPACING) {
                    HStack {
                        Text(NSLocalizedString("exercises", comment: ""))
                            .sectionHeaderStyle2()
                        Spacer()
                        if let progressReport, progressReport.comparableTrendCount > 0 {
                            ExercisesImprovedPill(
                                report: progressReport,
                                style: workout.sets.muscleGroupGradientStyle(
                                    startPoint: .bottomLeading,
                                    endPoint: .topTrailing
                                )
                            )
                        }
                    }
                    WorkoutSetGroupList(
                        workout: workout,
                        focusedIntegerFieldIndex: .constant(nil),
                        canReorder: false
                    )
                    .canEdit(false)
                }
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            .padding(.horizontal)
        }
        .workoutEffortRatingSheet(
            isPresented: $isRatingEffort,
            score: Binding(
                get: { workout.effortScore },
                // Rated from here there is no Save button to land on, so the rating commits
                // itself — and re-exports, since Health's copy of the workout carries the score.
                set: { newValue in
                    guard workout.effortScore != newValue else { return }
                    workout.effortScore = newValue
                    database.save()
                    healthKitSyncManager.syncWorkout(workout.healthKitPayload)
                }
            ),
            tint: effortTint,
            muscleGroups: workout.muscleGroups
        )
        .onAppear {
            progressReport = WorkoutProgressReport.compute(for: workout, database: database)
            refreshCalorieEstimate()
        }
        .onReceive(
            workout.objectWillChange.debounce(for: .seconds(0.5), scheduler: RunLoop.main)
        ) { _ in
            progressReport = WorkoutProgressReport.compute(for: workout, database: database)
            refreshCalorieEstimate()
        }
        .background(
            VStack {
                ColorfulView(color: workout.muscleGroups.map({ $0.color }), speed: .constant(0))
                    .mask(
                        LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        
                    )
                    .frame(height: 300)
                Spacer()
            }
            .ignoresSafeArea(.all)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Share Section
                    Section {
                        Button {
                            workoutShareFileURL = sharingService.exportWorkout(workout)
                        } label: {
                            Label(NSLocalizedString("inviteToWorkout", comment: ""), systemImage: "person.badge.plus")
                        }
                        Button {
                            templateShareFileURL = sharingService.exportWorkoutAsTemplate(workout)
                        } label: {
                            Label(NSLocalizedString("shareAsTemplate", comment: ""), systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    // Template Section
                    if let template = workout.template, canNavigateToTemplate {
                        Button {
                            selectedTemplate = template
                        } label: {
                            Label(NSLocalizedString("viewTemplate", comment: ""), systemImage: "list.bullet.rectangle.portrait")
                        }
                    } else {
                        Button {
                            newTemplateFromWorkout = database.newTemplate(from: workout)
                        } label: {
                            Label(NSLocalizedString("saveAsTemplate", comment: ""), systemImage: "plus.square.on.square")
                        }
                    }
                    Button(
                        action: {
                            sheetType = .workoutEditor
                        },
                        label: {
                            Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                        }
                    )
                    Button(
                        role: .destructive,
                        action: {
                            isShowingDeleteWorkoutAlert = true
                        }
                    ) {
                        Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .confirmationDialog(
                    NSLocalizedString("deleteWorkoutDescription", comment: ""),
                    isPresented: $isShowingDeleteWorkoutAlert,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("deleteWorkout", comment: ""), role: .destructive) {
                        if let workoutID = workout.id {
                            healthKitSyncManager.removeWorkout(id: workoutID)
                        }
                        database.delete(workout, saveContext: true)
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $workoutShareFileURL, onDismiss: {
            if let url = workoutShareFileURL {
                try? FileManager.default.removeItem(at: url)
                workoutShareFileURL = nil
            }
        }) { url in
            ShareSheet(activityItems: [WorkoutActivityItemSource(fileURL: url, title: workout.name ?? NSLocalizedString("workout", comment: ""))])
        }
        .sheet(item: $templateShareFileURL, onDismiss: {
            if let url = templateShareFileURL {
                try? FileManager.default.removeItem(at: url)
                templateShareFileURL = nil
            }
        }) { url in
            ShareSheet(activityItems: [WorkoutActivityItemSource(fileURL: url, title: workout.name ?? NSLocalizedString("template", comment: ""))])
        }
        .sheet(item: $sheetType) { type in
            switch type {
            case .workoutEditor:
                WorkoutEditorScreen(workout: workout, isAddingNewWorkout: false)
            }
        }
        .sheet(item: $newTemplateFromWorkout) { template in
            TemplateEditorScreen(
                template: template,
                isEditingExistingTemplate: false
            )
        }
        .navigationDestination(item: $selectedTemplate) { template in
            NavigationStack {
                TemplateDetailScreen(template: template)
            }
        }
        .navigationDestination(item: $selectedStatMetric) { metric in
            WorkoutStatScreen(metric: metric, workout: workout)
        }
        .navigationDestination(isPresented: $isShowingPersonalRecords) {
            WorkoutPersonalRecordsScreen(workout: workout, report: progressReport ?? .empty)
        }
    }

    /// Recomputes the calorie estimate (and whether only a body weight is missing — the
    /// teaser state). Cheap: one measurement fetch plus a pass over the sets' entries.
    private func refreshCalorieEstimate() {
        calorieEstimate = CalorieEstimator.estimate(for: workout)
        if calorieEstimate == nil,
           let start = workout.date, let end = workout.endDate, end > start,
           !workout.sets.isEmpty,
           let context = workout.managedObjectContext {
            calorieBodyWeightMissing = CalorieEstimator.bodyWeight(nearestTo: start, in: context) == nil
        } else {
            calorieBodyWeightMissing = false
        }
    }

    // MARK: - Supporting Views

    private var workoutHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text(workout.date?.description(.long) ?? "")
                    if let durationString = workoutDurationString {
                        Text("·")
                        Text(durationString)
                    }
                }
                .screenHeaderTertiaryStyle()
                Text(workout.name ?? "")
                    .screenHeaderStyle()
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            // The donut matches the height of date + title (like the workout cell's header row),
            // measured so a wrapping title scales it rather than leaving it floating.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newValue in
                headerTextHeight = newValue
            }
            Spacer()
            MuscleGroupOccurancesChart(muscleGroupOccurances: getMuscleGroupOccurancesInWorkout)
                .frame(width: headerTextHeight, height: headerTextHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The full-width records tile under the stat grid. The per-set volume tile that used to sit
    /// beside it is temporarily disabled (see the commented `volumePerSetTile` below) — re-enable it
    /// to bring back the side-by-side layout.
    @ViewBuilder
    private var progressAndVolumeRow: some View {
        if !(progressReport?.exerciseRecords.isEmpty ?? true) {
            personalBestsTile
        }
    }

    /// The full-width records tile as a button into the records screen.
    private var personalBestsTile: some View {
        Button {
            isShowingPersonalRecords = true
        } label: {
            WorkoutPersonalBestsTile(workout: workout, report: progressReport ?? .empty)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .tileStyle()
        }
        .buttonStyle(TileButtonStyle())
    }

    // MARK: - Volume per set tile (temporarily disabled — re-enable with the side-by-side layout above)

    /*
    private func volumePerSetTile(stretch: Bool) -> some View {
        volumePerSetTileContent
            .padding(CELL_PADDING)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .tileStyle()
    }

    /// Per-set volume at half width: the chart unique to this screen (totals live in the stat grid)
    /// with the average per set beneath it. The full-width tile's muscle-split legend is dropped
    /// here — the header donut already carries the split — so the chart keeps its room next to the
    /// records tile.
    private var volumePerSetTileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NSLocalizedString("volumePerSet", comment: ""))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 10) {
                SetVolumeBarChart(sets: workout.sets)
                    .frame(height: 100)
                averageVolumePerSetCaption
            }
            .padding(.top, 12)
            .isBlockedWithoutPro()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Average 693 KG" — the mean volume across this workout's sets, the figure the per-set bars
    /// vary around. Rendered through `UnitView` so the unit's casing matches the rest of the screen.
    private var averageVolumePerSetCaption: some View {
        HStack(spacing: 4) {
            Text(NSLocalizedString("average", comment: ""))
            UnitView(
                value: formatWeightForDisplay(averageVolumePerSet),
                unit: WeightUnit.used.rawValue,
                configuration: .extraSmall,
                unitColor: .secondaryLabel
            )
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var averageVolumePerSet: Int {
        let count = workout.sets.count
        guard count > 0 else { return 0 }
        return workoutVolume / count
    }
    */

    // MARK: - Computed Properties

    // Temporarily unused while the volume per set tile is disabled.
    // private var workoutVolume: Int {
    //     getVolume(of: workout.sets)
    // }

    private var workoutDurationString: String? {
        guard let start = workout.date, let end = workout.endDate else { return nil }
        let totalMinutes = Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0

        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
    }

    var getMuscleGroupOccurancesInWorkout: [(MuscleGroup, Int)] {
        muscleGroupService.getMuscleGroupOccurances(in: workout)
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject var database: Database

    var body: some View {
        NavigationStack {
            WorkoutDetailScreen(
                workout: database.testWorkout,
                canNavigateToTemplate: true
            )
        }
    }
}

struct WorkoutDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
