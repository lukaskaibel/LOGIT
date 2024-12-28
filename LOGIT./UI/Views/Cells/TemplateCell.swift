//
//  TemplateCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.04.22.
//

import Charts
import SwiftUI

struct TemplateCell: View {
    
    // MARK: - Environment
    
    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - Variables

    @ObservedObject var template: Template

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 12) {
                Chart {
                    ForEach(muscleGroupService.getMuscleGroupOccurances(in: template), id:\.0) { muscleGroupOccurance in
                        SectorMark(
                            angle: .value("Value", muscleGroupOccurance.1),
                            innerRadius: .ratio(0.65),
                            angularInset: 1
                        )
                        .foregroundStyle(muscleGroupOccurance.0.color.gradient)
                    }
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("template", comment: "").uppercased())
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(template.name ?? NSLocalizedString("noName", comment: ""))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct PreviewWrapperView: View {
    @EnvironmentObject private var database: Database
    
    var body: some View {
        ScrollView {
            TemplateCell(template: database.testTemplate)
                .padding(CELL_PADDING)
                .tileStyle()
        }
    }
}

struct TemplateCell_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
            .previewEnvironmentObjects()
    }
}
