//
//  SummaryWelcomeView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 29.06.26.
//

import SwiftUI

/// The brand-new-user Summary (`summary-first-open.html`): a welcome hero with the two starting
/// actions, then a dimmed "WHAT YOU'LL TRACK" preview grid that teases the value rather than showing a
/// setup checklist. Shown by `HomeScreen` when no non-empty workout has ever been logged.
struct SummaryWelcomeView: View {
    let onStartWorkout: () -> Void
    let onBrowseTemplates: () -> Void

    var body: some View {
        VStack(spacing: SECTION_SPACING) {
            welcomeCard
            previewSection
        }
    }

    private var welcomeCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 66, height: 66)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
            }
            Text(NSLocalizedString("summaryWelcomeTitle", comment: ""))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.top, 16)
            Text(NSLocalizedString("summaryWelcomeSubtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .padding(.horizontal, 8)
            Button(action: onStartWorkout) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(NSLocalizedString("startWorkout", comment: ""))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 20)
            Button(action: onBrowseTemplates) {
                Text(NSLocalizedString("browseTemplates", comment: ""))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .tileStyle()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(NSLocalizedString("whatYoullTrack", comment: ""))
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                previewTile(icon: "flame.fill", name: NSLocalizedString("weeklyGoal", comment: ""))
                previewTile(icon: "chart.bar.fill", name: NSLocalizedString("volumeAndSets", comment: ""))
                previewTile(icon: "trophy.fill", name: NSLocalizedString("records", comment: ""))
                previewTile(icon: "chart.pie.fill", name: NSLocalizedString("muscleBalance", comment: ""))
            }
            .opacity(0.55)
        }
    }

    private func previewTile(icon: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.fill))
            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .tileStyle()
    }
}

#Preview {
    ScrollView {
        SummaryWelcomeView(onStartWorkout: {}, onBrowseTemplates: {})
            .padding(.horizontal)
    }
}
