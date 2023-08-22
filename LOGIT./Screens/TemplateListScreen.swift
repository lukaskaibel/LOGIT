//
//  TemplateListScreen.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.04.22.
//

import SwiftUI

struct TemplateListScreen: View {

    // MARK: - Environment

    @EnvironmentObject var database: Database

    // MARK: - State

    @State private var searchedText = ""
    @State private var sortingKey: Database.TemplateSortingKey = .name
    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var showingTemplateCreation = false
    @State private var isShowingNoTemplatesTip = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SECTION_SPACING) {
                MuscleGroupSelector(selectedMuscleGroup: $selectedMuscleGroup)
                if isShowingNoTemplatesTip {
                    TipView(
                        title: NSLocalizedString("noTemplatesTip", comment: ""),
                        description: NSLocalizedString("noTemplatesTipDescription", comment: ""),
                        buttonAction: .init(title: NSLocalizedString("createTemplate", comment: ""), action: { showingTemplateCreation = true }), isShown: $isShowingNoTemplatesTip)
                    .padding(CELL_PADDING)
                    .tileStyle()
                    .padding(.horizontal)
                }
                ForEach(groupedTemplates.indices, id: \.self) { index in
                    VStack(spacing: CELL_SPACING) {
                        Text(header(for: index))
                            .sectionHeaderStyle2()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(groupedTemplates.value(at: index) ?? [], id: \.objectID) {
                            template in
                            NavigationLink(value: template) {
                                HStack {
                                    TemplateCell(template: template)
                                    NavigationChevron()
                                        .muscleGroupGradientStyle(for: template.muscleGroups)
                                }
                                .padding(CELL_PADDING)
                                .tileStyle()
                            }
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
        .navigationDestination(for: Template.self) { selectedTemplate in
            TemplateDetailScreen(template: selectedTemplate)
        }
        .navigationTitle(NSLocalizedString("templates", comment: ""))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        sortingKey = .name
                    }) {
                        Label(NSLocalizedString("name", comment: ""), systemImage: "textformat")
                    }
                    Button(action: {
                        sortingKey = .lastUsed
                    }) {
                        Label(NSLocalizedString("lastUsed", comment: ""), systemImage: "calendar")
                    }
                } label: {
                    Label(
                        NSLocalizedString(sortingKey == .name ? "name" : "lastUsed", comment: ""),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                Button(action: {
                    showingTemplateCreation = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .popover(isPresented: $showingTemplateCreation) {
            TemplateEditorScreen(template: database.newTemplate(), isEditingExistingTemplate: false)
        }
    }

    // MARK: - Computed Properties

    private var groupedTemplates: [[Template]] {
        database.getGroupedTemplates(
            withNameIncluding: searchedText,
            groupedBy: sortingKey,
            usingMuscleGroup: selectedMuscleGroup
        )
    }

    private func header(for index: Int) -> String {
        switch sortingKey {
        case .name:
            return String(groupedTemplates.value(at: index)?.first?.name?.first ?? " ").capitalized
        case .lastUsed:
            guard let date = groupedTemplates.value(at: index)?.first?.lastUsed else {
                return NSLocalizedString("unused", comment: "")
            }
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)

        }
    }

}

struct TemplateListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TemplateListScreen()
        }
        .environmentObject(Database.preview)
    }
}
