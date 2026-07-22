//
//  TemplateCell.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 06.04.22.
//

import Charts
import SwiftUI

/// A template row in the lists you pick from. Structured like `WorkoutCell` — recency caption, name
/// with a navigation chevron, muscle-group donut, then a contents summary — so a plan and a performed
/// workout read as the same family. Kept deliberately distinct from `WorkoutCell` in two ways: it has
/// no colorful muscle-gradient background (a plan is quieter than a session), and its caption is the
/// *recency* of use ("Last used 3 days ago" / "Never used") rather than a concrete date and duration.
/// Content only — the caller supplies the flat `.tileStyle()` background and padding.
struct TemplateCell: View {
    // MARK: - Environment

    @EnvironmentObject private var muscleGroupService: MuscleGroupService

    // MARK: - Variables

    @ObservedObject var template: Template

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            summaryRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - View Components

    private var headerRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recencyCaption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 5) {
                    Text(template.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    NavigationChevron()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            muscleGroupChart
        }
    }

    private var muscleGroupChart: some View {
        Chart {
            ForEach(muscleGroupService.getMuscleGroupOccurances(in: template), id: \.0) { muscleGroupOccurance in
                SectorMark(
                    angle: .value("Value", muscleGroupOccurance.1),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.5
                )
                .foregroundStyle(muscleGroupOccurance.0.color.gradient)
            }
        }
        .frame(width: 40, height: 40)
    }

    private var summaryRow: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(contentsSummary)
                .font(.footnote)
                .lineLimit(2)
            Spacer()
        }
    }

    // MARK: - Computed Properties

    /// "Last used 3 days ago" for a used template, "Never" for one that has never been run — the
    /// plan-side counterpart to the workout cell's date, built from `template.lastUsed`. The relative
    /// date is system-localized and the "Last used" prefix reuses the existing string, so the caption
    /// stays localized in every language without adding new keys.
    private var recencyCaption: String {
        guard let lastUsed = template.lastUsed else {
            return NSLocalizedString("never", comment: "")
        }
        let relative = lastUsed.formatted(.relative(presentation: .named))
        return "\(NSLocalizedString("lastUsed", comment: "")) \(relative)"
    }

    /// The user's description when they wrote one — their words win — otherwise the planned exercises,
    /// mirroring the workout cell's exercise summary so an unused template still says what it trains.
    private var contentsSummary: String {
        if let description = template.displayDescription {
            return description
        }
        let names = template.exercises.compactMap { $0.displayName.isEmpty ? nil : $0.displayName }
        if names.isEmpty {
            return NSLocalizedString("noExercises", comment: "")
        }
        let maxToShow = 20
        let shown = names.prefix(maxToShow)
        return names.count > maxToShow
            ? shown.joined(separator: ", ") + " & more"
            : shown.joined(separator: ", ")
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
