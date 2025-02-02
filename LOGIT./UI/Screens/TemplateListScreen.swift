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

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @EnvironmentObject private var workoutRecorder: WorkoutRecorder

    // MARK: - State

    @State private var searchedText = ""
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var showingTemplateCreation = false
    @State private var isShowingNoTemplatesTip = false
    
    var startWorkoutOnTap: Bool = false

    // MARK: - Body

    var body: some View {
        FetchRequestWrapper(
            Template.self,
            sortDescriptors: [SortDescriptor(\.name)],
            predicate: TemplatePredicateFactory.getTemplates(
                nameIncluding: searchedText,
                withMuscleGroup: selectedMuscleGroup
            )
        ) { templates in
            let groupedTemplates = Dictionary(grouping: templates, by: {
                $0.name?.prefix(1) ?? ""
            }).sorted { $0.key < $1.key }
            ScrollView {
                LazyVStack(spacing: SECTION_SPACING) {
                    MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                    if isShowingNoTemplatesTip {
                        TipView(
                            title: NSLocalizedString("noTemplatesTip", comment: ""),
                            description: NSLocalizedString("noTemplatesTipDescription", comment: ""),
                            buttonAction: .init(
                                title: NSLocalizedString("createTemplate", comment: ""),
                                action: { showingTemplateCreation = true }
                            ),
                            isShown: $isShowingNoTemplatesTip
                        )
                        .padding(CELL_PADDING)
                        .tileStyle()
                        .padding(.horizontal)
                    }
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
                                        dismiss()
                                    } else {
                                        homeNavigationCoordinator.path.append(.template(template))
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
                    .emptyPlaceholder(groupedTemplates) {
                        Text(NSLocalizedString("noTemplates", comment: ""))
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
            }
            .searchable(text: $searchedText)
            .onAppear {
                isShowingNoTemplatesTip = groupedTemplates.isEmpty
            }
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle(NSLocalizedString(startWorkoutOnTap ? "selectTemplate" : "templates", comment: ""))
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    CreateTemplateMenu()
                }
            }
            .popover(isPresented: $showingTemplateCreation) {
                TemplateEditorScreen(template: database.newTemplate(), isEditingExistingTemplate: false)
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
