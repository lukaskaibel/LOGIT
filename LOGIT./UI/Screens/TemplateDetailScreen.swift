//
//  TemplateDetailScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 08.04.22.
//

import SwiftUI

struct TemplateDetailScreen: View {

    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - State

    @State private var selectedWorkout: Workout?
    @State private var showingTemplateInfoAlert = false
    @State private var showingDeletionAlert = false
    @State private var showingTemplateEditor = false
    @State private var isMuscleGroupExpanded = false

    // MARK: - Variables

    let template: Template

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: SECTION_SPACING) {
                templateHeader
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("overview", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: CELL_SPACING) {
                        templateInfo
                            .padding(CELL_PADDING)
                            .tileStyle()
                        setsPerMuscleGroup
                            .padding(CELL_PADDING)
                            .tileStyle()
                    }
                }
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("exercises", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    exercisesList
                }
                VStack(spacing: SECTION_HEADER_SPACING) {
                    Text(NSLocalizedString("lastUsed", comment: ""))
                        .sectionHeaderStyle2()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    workoutList
                }
            }
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            .padding(.horizontal)
        }
        .edgesIgnoringSafeArea(.bottom)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedWorkout) { workout in
            WorkoutDetailScreen(workout: workout, canNavigateToTemplate: false)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu(content: {
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
            }
        }
        .alert(
            NSLocalizedString("templates", comment: ""),
            isPresented: $showingTemplateInfoAlert,
            actions: {},
            message: { Text(NSLocalizedString("templateExplanation", comment: "")) }
        )
        .confirmationDialog(
            NSLocalizedString("deleteTemplateMsg", comment: ""),
            isPresented: $showingDeletionAlert
        ) {
            Button(NSLocalizedString("deleteTemplate", comment: ""), role: .destructive) {
                database.delete(template, saveContext: true)
                dismiss()
            }
        }
        .sheet(isPresented: $showingTemplateEditor) {
            TemplateEditorScreen(template: template, isEditingExistingTemplate: true)
        }
    }

    // MARK: - Supporting Views

    private var templateHeader: some View {
        VStack(alignment: .leading) {
            Text(NSLocalizedString("template", comment: ""))
                .screenHeaderTertiaryStyle()
            Text(template.name ?? "")
                .screenHeaderStyle()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var templateInfo: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("exercises", comment: ""))
                        .foregroundColor(.secondary)
                    Text("\(template.numberOfSetGroups)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("sets", comment: ""))
                        .foregroundColor(.secondary)
                    Text("\(template.sets.count)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var setsPerMuscleGroup: some View {
        VStack(alignment: .leading, spacing: 20) {
            let muscleGroupOccurances = muscleGroupService.getMuscleGroupOccurances(in: template)
            HStack {
                Text(NSLocalizedString("muscleGroups", comment: ""))
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.tint)
                    .rotationEffect(isMuscleGroupExpanded ? .degrees(90) : .degrees(0))
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("focusedOn", comment: ""))
                        HStack {
                            ForEach(getFocusedMuscleGroups()) { muscleGroup in
                                Text(muscleGroup.description)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroup.color)
                            }
                        }
                    }
                    .emptyPlaceholder(muscleGroupOccurances) {
                        Text(NSLocalizedString("noWorkoutsThisWeek", comment: ""))
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: 150)
                    Spacer()
                    MuscleGroupOccurancesChart(muscleGroupOccurances: muscleGroupService.getMuscleGroupOccurances(in: template))
                        .frame(width: 100, height: 100)
                        .padding(.trailing)
                }
                if isMuscleGroupExpanded {
                    VStack(spacing: CELL_SPACING) {
                        ForEach(muscleGroupOccurances, id:\.self.0) { muscleGroupOccurance in
                            HStack {
                                Text(muscleGroupOccurance.0.description)
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(muscleGroupOccurance.0.color)
                                Spacer()
                                HStack(spacing: 10) {

                                    VStack(alignment: .leading) {
                                        Text(NSLocalizedString("exercises", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(template.setGroups.filter({ $0.muscleGroups.contains(where: { $0 == muscleGroupOccurance.0 }) }).count)")
                                            .fontWeight(.bold)
                                            .fontDesign(.rounded)
                                    }
                                    Divider()
                                    VStack(alignment: .leading) {
                                        Text(NSLocalizedString("sets", comment: ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(template.sets.filter({ $0.setGroup?.muscleGroups.contains(where: { $0 == muscleGroupOccurance.0 }) ?? false }).count)")
                                            .fontWeight(.bold)
                                            .fontDesign(.rounded)
                                    }
                                }
                            }

                            .padding(CELL_PADDING)
                            .secondaryTileStyle(backgroundColor: muscleGroupOccurance.0.color.secondaryTranslucentBackground)
                        }
                    }
                }
            }
            .isBlockedWithoutPro()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isMuscleGroupExpanded.toggle()
            }
        }
    }

    private var exercisesList: some View {
        VStack(spacing: CELL_SPACING) {
            ForEach(template.setGroups) { templateSetGroup in
                TemplateSetGroupCell(
                    setGroup: templateSetGroup,
                    focusedIntegerFieldIndex: .constant(nil),
                    sheetType: .constant(nil),
                    isReordering: .constant(false),
                    supplementaryText:
                        "\(template.setGroups.firstIndex(of: templateSetGroup)! + 1) / \(template.setGroups.count)  ·  \(templateSetGroup.setType.description)"
                )
                .padding(CELL_PADDING)
                .tileStyle()
                .canEdit(false)
            }
        }
    }

    private var workoutList: some View {
        ForEach(template.workouts, id: \.objectID) { workout in
            Button {
                selectedWorkout = workout
            } label: {
                WorkoutCell(workout: workout)
            }
            .padding(CELL_PADDING)
            .tileStyle()
            .buttonStyle(TileButtonStyle())
        }
        .emptyPlaceholder(template.workouts) {
            Text(NSLocalizedString("templateNeverUsed", comment: ""))
        }
    }

    // MARK: - Computed Properties

    private var lastUsedDateString: String {
        template.workouts.first?.date?.description(.medium)
            ?? NSLocalizedString("never", comment: "")
    }
    
    private var amountOfOccurances: Int {
        muscleGroupService.getMuscleGroupOccurances(in: template).reduce(0, { $0 + $1.1 })
    }
    
    /// Calculates the smallest number of Muscle Groups that combined account for 51% of the overall sets in the timeframe
    /// - Returns: The focused Muscle Groups
    private func getFocusedMuscleGroups() -> [MuscleGroup] {
        var accumulatedPercetange: Float = 0
        var focusedMuscleGroups = [MuscleGroup]()
        for muscleGroupOccurance in muscleGroupService.getMuscleGroupOccurances(in: template) {
            accumulatedPercetange += Float(muscleGroupOccurance.1) / Float(amountOfOccurances)
            focusedMuscleGroups.append(muscleGroupOccurance.0)
            if accumulatedPercetange > 0.51 {
                return Array(focusedMuscleGroups.prefix(2))
            }
        }
        return []
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
