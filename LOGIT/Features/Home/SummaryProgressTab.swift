//
//  SummaryProgressTab.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI

// MARK: - Summary tab

/// The Summary screen's top switcher: the everyday `This Week` view vs the new `Progress` lens
/// (recent highlights + the overall strength trend). Replaces the old Week / Month / Year period
/// segments on the Summary — the longer windows still live on the stat detail screens.
enum SummaryTab: String, CaseIterable, Identifiable {
    case thisWeek, progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek: return NSLocalizedString("thisWeek", comment: "")
        case .progress: return NSLocalizedString("progress", comment: "")
        }
    }
}

/// The shared segmented `This Week` / `Progress` control, mirroring `PeriodPicker`'s styling.
struct SummaryTabPicker: View {
    @Binding var selection: SummaryTab

    var body: some View {
        Picker(NSLocalizedString("progress", comment: ""), selection: $selection) {
            ForEach(SummaryTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Progress tab

/// The `Progress` tab body: the Strength tile leads as the tab's headline, the Highlights
/// carousel below — recent bests, milestones, and trends as swipeable cards (see
/// `ProgressHighlights`). Computes both off the already-fetched `[Workout]` in a `.task` (no new
/// Core Data fetches), the way the Summary's records tile does.
struct SummaryProgressTab: View {
    let workouts: [Workout]

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @State private var strength: StrengthProgress = .empty
    @State private var highlights: [ProgressHighlight] = []

    var body: some View {
        VStack(spacing: 8) {
            Button {
                homeNavigationCoordinator.path.append(.strength)
            } label: {
                StrengthTile(progress: strength)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TileButtonStyle())
            if !highlights.isEmpty {
                highlightsSection
                    .padding(.top, 8)
            }
        }
        .task(id: workouts.count) {
            strength = StrengthProgress.compute(workouts: workouts)
            highlights = ProgressHighlights.compute(workouts: workouts, database: database)
        }
    }

    /// Section header + carousel. The carousel shows the top few by priority; "Show All" appears
    /// only once there is genuinely more than it shows.
    private var highlightsSection: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(NSLocalizedString("highlights", comment: ""))
                    .sectionHeaderStyle2()
                Spacer()
                if highlights.count > ProgressHighlights.carouselLimit {
                    Button {
                        homeNavigationCoordinator.path.append(.progressHighlights)
                    } label: {
                        Text(NSLocalizedString("showAll", comment: ""))
                    }
                    .fontWeight(.semibold)
                }
            }
            ProgressHighlightsCarousel(
                items: Array(highlights.prefix(ProgressHighlights.carouselLimit))
            )
        }
    }
}
