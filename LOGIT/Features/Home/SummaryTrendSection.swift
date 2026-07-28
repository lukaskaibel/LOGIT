//
//  SummaryTrendSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI

// MARK: - Trend section

/// The Summary's opening band: the Strength tile, then the Highlights carousel — the trend, then
/// what just happened. Strength leads because it always renders and barely moves week to week, which
/// makes it a stable anchor; Highlights is conditional (it vanishes with nothing to show), so it can
/// never be the thing the screen opens on. Both compute off the already-fetched `[Workout]` in one
/// `.task`, with no new Core Data fetches.
struct SummaryTrendSection: View {
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
