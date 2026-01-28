//
//  TemplateListScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.04.22.
//

import SwiftUI

struct TemplateListScreen: View {
    // MARK: - Environment

    @Environment(\.dismiss) var dismiss
    @Environment(\.presentWorkoutRecorder) var presentWorkoutRecorder

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    // MARK: - State

    @State private var searchedText = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var showingTemplateCreation = false
    @State private var isShowingNoTemplatesTip = false
    @State private var selectedTemplate: Template?

    var startWorkoutOnTap: Bool = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Template.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: TemplatePredicateFactory.getTemplates(
                nameIncluding: "",
                withMuscleGroup: selectedMuscleGroup
            )
        ) { allTemplates in
            let templates = FuzzySearchService.shared.searchTemplates(searchedText, in: allTemplates)
            let sortedTemplates = searchedText.isEmpty
                ? templates.sorted { ($0.name ?? "").localizedCompare($1.name ?? "") == .orderedAscending }
                : templates // Keep fuzzy search order when searching
            let groupedTemplates = Dictionary(grouping: sortedTemplates, by: {
                String($0.name?.prefix(1) ?? "")
            }).sorted { $0.key < $1.key }
            let isSearching = !searchedText.isEmpty
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isShowingNoTemplatesTip {
                        TipView(
                            category: NSLocalizedString("planAhead", comment: ""),
                            title: NSLocalizedString("noTemplatesTip", comment: ""),
                            description: NSLocalizedString("noTemplatesTipDescription", comment: ""),
                            buttonAction: .init(
                                title: NSLocalizedString("createTemplate", comment: ""),
                                action: { showingTemplateCreation = true }
                            ),
                            isShown: $isShowingNoTemplatesTip
                        )
                        .padding(.horizontal)
                    }
                    if isSearching {
                        // Flat list when searching - results ordered by relevance
                        VStack(spacing: CELL_SPACING) {
                            ForEach(sortedTemplates) { template in
                                Button {
                                    if startWorkoutOnTap {
                                        workoutRecorder.startWorkout(from: template)
                                        presentWorkoutRecorder()
                                        dismiss()
                                    } else {
                                        selectedTemplate = template
                                    }
                                } label: {
                                    VStack {
                                        HStack {
                                            TemplateCell(template: template)
                                            NavigationChevron()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(CELL_PADDING)
                                    .tileStyle()
                                }
                                .buttonStyle(TileButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        // Grouped by first letter when not searching
                        ForEach(groupedTemplates, id: \.0) { key, templates in
                            VStack(spacing: CELL_SPACING) {
                                Text(key)
                                    .sectionHeaderStyle2()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                ForEach(templates) {
                                    template in
                                    Button {
                                        if startWorkoutOnTap {
                                            workoutRecorder.startWorkout(from: template)
                                            presentWorkoutRecorder()
                                            dismiss()
                                        } else {
                                            selectedTemplate = template
                                        }
                                    } label: {
                                        VStack {
                                            HStack {
                                                TemplateCell(template: template)
                                                NavigationChevron()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(CELL_PADDING)
                                        .tileStyle()
                                    }
                                    .buttonStyle(TileButtonStyle())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    EmptyView()
                        .emptyPlaceholder(templates) {
                            Text(NSLocalizedString("noTemplates", comment: ""))
                        }
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .searchable(text: $searchedText)
            .onAppear {
                isShowingNoTemplatesTip = groupedTemplates.isEmpty
            }
            .navigationBarTitleDisplayMode(startWorkoutOnTap ? .inline : .large)
            .navigationTitle(startWorkoutOnTap ? "" : NSLocalizedString("templates", comment: ""))
            .toolbar {
                if !startWorkoutOnTap {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        CreateTemplateMenu()
                    }
                }
            }
            .popover(isPresented: $showingTemplateCreation) {
                TemplateEditorScreen(template: database.newTemplate(), isEditingExistingTemplate: false)
                    .presentationBackground(Color.black)
            }
            .navigationDestination(item: $selectedTemplate) { template in
                TemplateDetailScreen(template: template)
            }
        }
    }
}

struct TemplateListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TemplateListScreen()
        }
        .previewEnvironmentObjects()
    }
}
