//
//  TemplateDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.04.22.
//

import ColorfulX
import SwiftUI

struct TemplateDetailScreen: View {
    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.presentWorkoutRecorder) private var presentWorkoutRecorder
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var muscleGroupService: MuscleGroupService
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    // MARK: - State

    @State private var selectedWorkout: Workout?
    @State private var showingTemplateInfoAlert = false
    @State private var showingDeletionAlert = false
    @State private var showingTemplateEditor = false
    @State private var templateShareFileURL: URL?
    /// Sizes the header donut to the height of the kicker + title beside it (like the workout
    /// detail's header), so a wrapping title scales it rather than leaving it floating.
    @State private var headerTextHeight: CGFloat = 64

    // MARK: - Variables

    @StateObject var template: Template

    // MARK: - Sharing Service

    private var sharingService: WorkoutSharingService {
        WorkoutSharingService(database: database)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: SECTION_SPACING) {
                templateHeader
                VStack(spacing: 10) {
                    startButton
                    if hasSessions {
                        progressGrid
                    }
                }
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("exercises", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    exercisesList
                }
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("history", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    workoutList
                }
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            .padding(.horizontal)
        }
        .background(
            VStack {
                ColorfulView(color: template.muscleGroups.map({ $0.color }), speed: .constant(0))
                    .mask(
                        LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 300)
                Spacer()
            }
            .ignoresSafeArea(.all)
        )
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailScreen(workout: workout, canNavigateToTemplate: false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu(content: {
                    Button {
                        templateShareFileURL = sharingService.exportTemplate(template)
                    } label: {
                        Label(NSLocalizedString("shareTemplate", comment: ""), systemImage: "square.and.arrow.up")
                    }
                    Button(
                        action: { showingTemplateEditor = true },
                        label: {
                            Label(NSLocalizedString("edit", comment: ""), systemImage: "pencil")
                        }
                    )
                    Button(
                        role: .destructive,
                        action: {
                            showingDeletionAlert = true
                        },
                        label: {
                            Label(NSLocalizedString("delete", comment: ""), systemImage: "trash")
                        }
                    )
                }) {
                    Image(systemName: "ellipsis.circle")
                }
                .confirmationDialog(
                    NSLocalizedString("deleteTemplateMsg", comment: ""),
                    isPresented: $showingDeletionAlert,
                    titleVisibility: .visible
                ) {
                    Button(NSLocalizedString("deleteTemplate", comment: ""), role: .destructive) {
                        database.delete(template, saveContext: true)
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $templateShareFileURL) { url in
            ShareSheet(activityItems: [WorkoutActivityItemSource(fileURL: url, title: template.resolvedName ?? NSLocalizedString("template", comment: ""))])
                .onDisappear {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        // Ignore errors when attempting to remove the temporary share file
                    }
                    templateShareFileURL = nil
                }
        }
        .alert(
            NSLocalizedString("templates", comment: ""),
            isPresented: $showingTemplateInfoAlert,
            actions: {},
            message: { Text(NSLocalizedString("templateExplanation", comment: "")) }
        )
        .fullScreenCover(isPresented: $showingTemplateEditor) {
            TemplateEditorScreen(template: template, isEditingExistingTemplate: true)
        }
    }

    // MARK: - Supporting Views

    /// The kicker + title beside the muscle-group donut, mirroring the workout detail's header so
    /// the two screens read as one family. The donut carries the muscle split now that the standalone
    /// muscle-group tile is gone. The optional description flows full-width beneath.
    private var templateHeader: some View {
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("template", comment: ""))
                        .screenHeaderTertiaryStyle()
                    Text(template.resolvedName ?? "")
                        .screenHeaderStyle()
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    headerTextHeight = newValue
                }
                Spacer()
                MuscleGroupOccurancesChart(
                    muscleGroupOccurances: muscleGroupService.getMuscleGroupOccurances(in: template)
                )
                .frame(width: headerTextHeight, height: headerTextHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let description = template.displayDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The screen's primary action: start recording a workout from this template. Uses the same
    /// recorder entry point (`startWorkout(from:)` + `presentWorkoutRecorder`) as the Start tab's
    /// template list, so both paths behave identically.
    private var startButton: some View {
        Button {
            workoutRecorder.startWorkout(from: template)
            presentWorkoutRecorder()
        } label: {
            Label(NSLocalizedString("startWorkout", comment: ""), systemImage: "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    /// This template's recent sessions shown as the workout detail's stat grid — volume, duration,
    /// sets, and repetitions — each tile's bars the last few runs of the template with the newest
    /// highlighted, so the screen answers "is this routine getting more productive?" with the same
    /// components (and Pro gating) as the workout screen. Only shown once the template has been run.
    @ViewBuilder
    private var progressGrid: some View {
        let history = WorkoutRunHistory(basis: .sameWorkout, runs: recentSessions)
        let spacing: CGFloat = 10
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: spacing) {
                ForEach(WorkoutStatMetric.allCases) { metric in
                    templateStatTile(metric, history: history)
                }
            }
        } else {
            VStack(spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    templateStatTile(.volume, history: history)
                    templateStatTile(.duration, history: history)
                }
                HStack(alignment: .top, spacing: spacing) {
                    templateStatTile(.sets, history: history)
                    templateStatTile(.repetitions, history: history)
                }
            }
        }
    }

    /// One session-stat tile: the latest session's value, the trend versus the previous session, and
    /// the per-session bars — assembled from the shared `MetricTile` + `WorkoutRunsBarChart` the
    /// workout detail uses, so the two can't drift. Duration stays neutral gray (a longer session is
    /// neither better nor worse); the rest wear the template's muscle-group tint. No subtitle — the
    /// screen title and section already say these are this template's sessions.
    private func templateStatTile(_ metric: WorkoutStatMetric, history: WorkoutRunHistory) -> some View {
        let latest = history.runs.last
        let raw = latest.map { metric.rawValue(of: $0) } ?? 0
        let isDuration = metric == .duration
        let accent: AnyShapeStyle = isDuration
            ? AnyShapeStyle(Color.secondary)
            : (latest?.sets.muscleGroupGradientStyle(startPoint: .bottomLeading, endPoint: .topTrailing)
                ?? AnyShapeStyle(dominantMuscleColor.gradient))
        let barStyle: AnyShapeStyle = isDuration
            ? AnyShapeStyle(Color.secondary)
            : (latest?.sets.muscleGroupGradientStyle(startPoint: .bottom, endPoint: .top)
                ?? AnyShapeStyle(dominantMuscleColor.gradient))
        return MetricTile(
            title: metric.title,
            showsChevron: false,
            label: .none,
            value: raw > 0 ? metric.formattedValue(fromRaw: raw) : nil,
            unit: metric.unit,
            accent: accent,
            accentColor: isDuration ? .secondary : dominantMuscleColor,
            percentChange: history.percentChange(for: metric),
            requiresPro: metric.requiresPro,
            chartBleeds: false
        ) {
            WorkoutRunsBarChart(bars: runBars(for: metric, history: history), currentStyle: barStyle)
        }
    }

    /// Right-aligned into the chart's fixed five slots, newest run last — the template-side twin of
    /// `WorkoutStatTile.runBars`.
    private func runBars(for metric: WorkoutStatMetric, history: WorkoutRunHistory) -> [WorkoutRunsBarChart.Bar] {
        let offset = WorkoutRunsBarChart.slotCount - history.runs.count
        let latestID = history.runs.last?.objectID
        return history.runs.enumerated().map { index, run in
            WorkoutRunsBarChart.Bar(
                slot: offset + index,
                value: metric.displayValue(fromRaw: metric.rawValue(of: run)),
                isCurrent: run.objectID == latestID
            )
        }
    }

    private var exercisesList: some View {
        VStack(spacing: 0) {
            ForEach(template.setGroups) { templateSetGroup in
                VStack(spacing: 0) {
                    TemplateSetGroupCell(
                        setGroup: templateSetGroup,
                        focusedIntegerFieldIndex: .constant(nil),
                        sheetType: .constant(nil),
                        isReordering: .constant(false),
                        supplementaryText: nil
                    )
                    .tileStyle()
                    .canEdit(false)
                    .shadow(color: .black, radius: 5)
                    .zIndex(1)
                    if template.setGroups.last != templateSetGroup {
                        Rectangle()
                            .foregroundStyle(.secondary)
                            .frame(width: 3, height: SECTION_SPACING)
                            .zIndex(0)
                    }
                }
            }
        }
    }

    private var workoutList: some View {
        ForEach(pastWorkouts, id: \.objectID) { workout in
            Button {
                selectedWorkout = workout
            } label: {
                WorkoutCell(workout: workout)
            }
            .buttonStyle(TileButtonStyle())
        }
        .emptyPlaceholder(pastWorkouts) {
            Text(NSLocalizedString("templateNeverUsed", comment: ""))
        }
    }

    // MARK: - Computed Properties

    /// This template's completed sessions, newest first — the "History" list. The in-progress
    /// workout (if one was just started from here) is excluded so it doesn't masquerade as history.
    private var pastWorkouts: [Workout] {
        Array(template.workouts.filter { !$0.isCurrentWorkout }.reversed())
    }

    /// The last few real sessions of this template, oldest → newest, that feed the progress bars.
    private var recentSessions: [Workout] {
        Array(
            template.workouts
                .filter { !$0.isEmpty && !$0.isCurrentWorkout }
                .suffix(WorkoutRunsBarChart.slotCount)
        )
    }

    private var hasSessions: Bool {
        !recentSessions.isEmpty
    }

    /// The template's most-trained muscle group's color — the flat tint behind the tiles' pills and
    /// the fallback when a session has no muscle-group gradient.
    private var dominantMuscleColor: Color {
        muscleGroupService.getMuscleGroupOccurances(in: template).first?.0.color ?? .accentColor
    }
}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database

    var body: some View {
        NavigationStack {
            TemplateDetailScreen(template: database.testTemplate)
        }
    }
}

struct TemplateDetailView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
