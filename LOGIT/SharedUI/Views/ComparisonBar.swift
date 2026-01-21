//
//  ComparisonBar.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 19.01.26.
//

import SwiftUI

/// A horizontal bar that fills proportionally based on a value relative to a maximum.
/// Used in Highlights sections to visually compare current vs previous period metrics.
struct ComparisonBar: View {
    let value: Double
    let maxValue: Double
    let tint: Color
    let label: String

    init(value: Double, maxValue: Double, tint: Color, label: String = "") {
        self.value = value
        self.maxValue = maxValue
        self.tint = tint
        self.label = label
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = maxValue > 0 ? CGFloat(min(max(value / maxValue, 0), 1)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondaryBackground)
                RoundedRectangle(cornerRadius: 10)
                    .fill(tint)
                    .frame(width: width * ratio)
                if !label.isEmpty {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint == .accentColor ? .black : .primary)
                        .padding(.horizontal, 10)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ComparisonBar(value: 8.5, maxValue: 10, tint: .accentColor, label: "This Week")
            .frame(height: 30)
        ComparisonBar(value: 6.2, maxValue: 10, tint: .gray.opacity(0.25), label: "Last Week")
            .frame(height: 30)
    }
    .padding()
}
