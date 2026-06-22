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
    /// When set, the filled portion renders with this gradient instead of `tint` — used where the
    /// bar stands for a whole workout rather than a single metric (muscle-group themed bars).
    let gradient: LinearGradient?

    init(value: Double, maxValue: Double, tint: Color, label: String = "", gradient: LinearGradient? = nil) {
        self.value = value
        self.maxValue = maxValue
        self.tint = tint
        self.label = label
        self.gradient = gradient
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = maxValue > 0 ? CGFloat(min(max(value / maxValue, 0), 1)) : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondaryBackground)
                if let gradient {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(gradient)
                        .frame(width: width * ratio)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tint)
                        .frame(width: width * ratio)
                }
                if !label.isEmpty {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint == .accentColor || gradient != nil ? .black : .primary)
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
