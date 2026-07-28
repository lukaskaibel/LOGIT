//
//  SummaryTrendSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 30.06.26.
//

import CoreData
import SwiftUI

// MARK: - Trend section

/// The Summary's opening band: the Strength + Balance pair, then the Highlights carousel — the
/// trend, then what just happened. The pair leads because both halves always render and barely move
/// week to week, which makes them a stable anchor; Highlights is conditional (it vanishes with
/// nothing to show), so it can never be the thing the screen opens on.
///
/// Both tiles read the **same four weeks** — `Exercise.currentBestWindowStart`, the window the rest
/// of the app already means by "current". That is why they can sit side by side without a caption
/// each: there is only one period on this band, so naming it twice would be noise.
struct SummaryTrendSection: View {
    let workouts: [Workout]

    @EnvironmentObject private var database: Database
    @EnvironmentObject private var homeNavigationCoordinator: HomeNavigationCoordinator
    @State private var strength: StrengthProgress = .empty
    @State private var highlights: [ProgressHighlight] = []

    /// The same four weeks the Strength figure compares against — see the type doc.
    private var currentWindowWorkouts: [Workout] {
        let start = Exercise.currentBestWindowStart
        return workouts.filter { !$0.isEmpty && ($0.date ?? .distantPast) >= start }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    homeNavigationCoordinator.path.append(.strength)
                } label: {
                    StrengthTile(progress: strength)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
                Button {
                    homeNavigationCoordinator.path.append(.muscleGroupsOverview)
                } label: {
                    MuscleBalanceGoalTile(workouts: currentWindowWorkouts)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TileButtonStyle())
            }
            .frame(height: PAIRED_TILE_HEIGHT)
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
