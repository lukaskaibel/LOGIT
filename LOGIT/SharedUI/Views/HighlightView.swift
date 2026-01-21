//
//  HighlightView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 19.01.26.
//

import SwiftUI

/// A reusable view for displaying period-over-period comparison highlights.
/// Shows a headline, current period value with comparison bar, and previous period value with comparison bar.
struct HighlightView: View {
    /// The localized headline text describing the comparison (e.g., "You're averaging more...")
    let headline: String
    /// The formatted current period value (e.g., "8.5")
    let currentValue: String
    /// The formatted previous period value (e.g., "6.2")
    let previousValue: String
    /// The unit label (e.g., "sets/workout", "kg/week")
    let unit: String
    /// Label for current period (e.g., "This Week", "This Month")
    let currentLabel: String
    /// Label for previous period (e.g., "Last Week", "Last Month")
    let previousLabel: String
    /// Numeric value for current period (for bar ratio calculation)
    let currentNumericValue: Double
    /// Numeric value for previous period (for bar ratio calculation)
    let previousNumericValue: Double
    /// Accent color for the current period bar (defaults to .accentColor)
    var accentColor: Color = .accentColor

    private var maxBar: Double {
        max(max(currentNumericValue, previousNumericValue), 1.0)
    }

    /// Whether there is any data to show (at least one period has data)
    private var hasAnyData: Bool {
        currentNumericValue > 0 || previousNumericValue > 0
    }

    /// Whether both periods have data
    private var hasBothPeriods: Bool {
        currentNumericValue > 0 && previousNumericValue > 0
    }

    var body: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("highlights", comment: ""))
                .sectionHeaderStyle2()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if hasBothPeriods {
                // Both periods have data - show full comparison
                VStack(alignment: .leading, spacing: 14) {
                    Text(headline)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)

                    // Current period
                    VStack(alignment: .leading, spacing: 6) {
                        UnitView(value: currentValue, unit: unit, configuration: .large, unitColor: Color.secondaryLabel)
                        ComparisonBar(value: currentNumericValue, maxValue: maxBar, tint: accentColor, label: currentLabel)
                            .frame(height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Previous period
                    VStack(alignment: .leading, spacing: 6) {
                        UnitView(value: previousValue, unit: unit, configuration: .large, unitColor: Color.secondaryLabel)
                        ComparisonBar(value: previousNumericValue, maxValue: maxBar, tint: .gray.opacity(0.25), label: previousLabel)
                            .frame(height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(CELL_PADDING)
                .tileStyle()
            } else if hasAnyData {
                // Only one period has data - show it prominently with encouraging message
                let hasCurrentData = currentNumericValue > 0
                let value = hasCurrentData ? currentValue : previousValue
                let numericValue = hasCurrentData ? currentNumericValue : previousNumericValue
                let label = hasCurrentData ? currentLabel : previousLabel
                
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        UnitView(value: value, unit: unit, configuration: .large, unitColor: Color.secondaryLabel)
                        ComparisonBar(value: numericValue, maxValue: numericValue, tint: accentColor, label: label)
                            .frame(height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    
                    // Encouraging message
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("keepTrackingForComparison", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(CELL_PADDING)
                .tileStyle()
            } else {
                // Empty state - no data for either period
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(NSLocalizedString("noData", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .tileStyle()
            }
        }
    }
}

// MARK: - Convenience Initializer with Granularity

extension HighlightView {
    /// A granularity enum for period comparisons (week, month, year)
    enum Granularity {
        case week, month, year

        var currentLabel: String {
            switch self {
            case .week: return NSLocalizedString("thisWeek", comment: "")
            case .month: return NSLocalizedString("thisMonth", comment: "")
            case .year: return String(Calendar.current.component(.year, from: Date()))
            }
        }

        var previousLabel: String {
            switch self {
            case .week: return NSLocalizedString("lastWeek", comment: "")
            case .month: return NSLocalizedString("lastMonth", comment: "")
            case .year: return String(Calendar.current.component(.year, from: Date()) - 1)
            }
        }

        /// Returns current and previous period date ranges
        func periodRanges() -> (current: (start: Date, end: Date), previous: (start: Date, end: Date)) {
            switch self {
            case .week:
                let current = (Date.now.startOfWeek, Date.now.endOfWeek)
                let lastStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: .now.startOfWeek)!
                let previous = (lastStart, lastStart.endOfWeek)
                return (current, previous)
            case .month:
                let current = (Date.now.startOfMonth, Date.now.endOfMonth)
                let lastStart = Calendar.current.date(byAdding: .month, value: -1, to: .now.startOfMonth)!
                let previous = (lastStart, lastStart.endOfMonth)
                return (current, previous)
            case .year:
                let current = (Date.now.startOfYear, Date.now.endOfYear)
                let lastStart = Calendar.current.date(byAdding: .year, value: -1, to: .now.startOfYear)!
                let previous = (lastStart, lastStart.endOfYear)
                return (current, previous)
            }
        }
    }

    /// Convenience initializer using granularity for automatic period labels
    init(
        headline: String,
        currentValue: String,
        previousValue: String,
        unit: String,
        currentNumericValue: Double,
        previousNumericValue: Double,
        granularity: Granularity,
        accentColor: Color = .accentColor
    ) {
        self.headline = headline
        self.currentValue = currentValue
        self.previousValue = previousValue
        self.unit = unit
        self.currentLabel = granularity.currentLabel
        self.previousLabel = granularity.previousLabel
        self.currentNumericValue = currentNumericValue
        self.previousNumericValue = previousNumericValue
        self.accentColor = accentColor
    }
}

// MARK: - Number Formatting Helper

extension HighlightView {
    static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

#Preview {
    ScrollView {
        HighlightView(
            headline: "You're averaging more volume per workout this month than last month.",
            currentValue: "2,450",
            previousValue: "1,890",
            unit: "kg/workout",
            currentNumericValue: 2450,
            previousNumericValue: 1890,
            granularity: .month
        )
        .padding()
    }
}
