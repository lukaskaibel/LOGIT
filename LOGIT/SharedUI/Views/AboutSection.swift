//
//  AboutSection.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.06.26.
//

import SwiftUI

/// Health-app-style explanation shown at the bottom of metric detail screens:
/// an "About <Metric>" header followed by a short secondary description sitting
/// in a tile, matching the `HighlightView` section directly above it.
struct AboutSection: View {
    let metricTitle: String
    let text: String

    var body: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            Text(String(
                format: NSLocalizedString("aboutMetric", comment: ""),
                metricTitle
            ))
            .sectionHeaderStyle2()
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CELL_PADDING)
                .tileStyle()
        }
    }
}

#Preview {
    AboutSection(
        metricTitle: "Volume",
        text: "Volume is the total weight you've moved: weight × reps, summed over all sets in a week."
    )
    .padding(.horizontal)
}
