//
//  DateBarChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 14.09.23.
//

import Charts
import SwiftUI

struct DateBarChart: View {
    struct Item: Identifiable {
        var id: String { "\(date)\(value)" }
        let date: Date
        let value: Int
    }

    // MARK: - Constants

    private let yValuePaddingRatio = 0.1

    // MARK: - Properties

    let dateUnit: Calendar.Component
    let items: [Item]

    init(dateUnit: Calendar.Component, items: () -> [Item]) {
        self.dateUnit = dateUnit
        self.items = items()
    }

    // MARK: - Body

    var body: some View {
        Chart {
            ForEach(items) { item in
                BarMark(
                    x: .value("Date", item.date, unit: dateUnit),
                    y: .value("Value", item.value),
                    width: 20
                )
                .annotation(position: .top) {
                    Text(String(item.value))
                        .font(.footnote)
                }
                .clipShape(Capsule())
            }
        }
        .chartXAxis {
            AxisMarks(preset: .extended, values: .stride(by: dateUnit)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(dateDescription(for: date))
                        .foregroundStyle(isInSameDateUnitAsNow(date: date) ? Color.primary : .secondary)
                        .font(.caption.weight(.bold))
                }
            }
        }
        .chartXScale(domain: [
            minXValue, maxXValue,
        ])
        .chartYAxis(.hidden)
    }

    // MARK: - Computed Properties

    private var maxXValue: Date {
        switch dateUnit {
        case .day:
            guard let startOfNextDay = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date().addingTimeInterval(24 * 60 * 60)) else {
                fatalError("Failed to calculate start of next day.")
            }
            return startOfNextDay.addingTimeInterval(-1)

        case .weekOfYear, .weekOfMonth:
            guard let startOfNextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date().startOfWeek) else {
                fatalError("Failed to calculate start of next week.")
            }
            return startOfNextWeek.addingTimeInterval(-1)

        case .month:
            guard let startOfNextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date().startOfMonth) else {
                fatalError("Failed to calculate start of next month.")
            }
            return startOfNextMonth.addingTimeInterval(-1)

        case .year:
            guard let startOfNextYear = Calendar.current.date(byAdding: .year, value: 1, to: Date().startOfYear) else {
                fatalError("Failed to calculate start of next year.")
            }
            return startOfNextYear.addingTimeInterval(-1)

        default:
            return Date()
        }
    }

    private var minXValue: Date {
        guard let dateMinusUnits = Calendar.current.date(
            byAdding: dateUnit,
            value: -7,
            to: Date()
        ) else {
            fatalError("Failed to calculate dateMinusUnits.")
        }

        switch dateUnit {
        case .day:
            return Calendar.current.startOfDay(for: dateMinusUnits)
        case .weekOfYear, .weekOfMonth:
            return Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dateMinusUnits)) ?? dateMinusUnits
        case .month:
            return Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: dateMinusUnits)) ?? dateMinusUnits
        case .year:
            return Calendar.current.date(from: Calendar.current.dateComponents([.year], from: dateMinusUnits)) ?? dateMinusUnits
        default:
            return dateMinusUnits
        }
    }

    private var maxYValue: Int {
        (items.map { $0.value }.max() ?? 1) + yValuePadding
    }

    private var yValuePadding: Int {
        Int(ceil(Double(items.map { $0.value }.max() ?? 1) * yValuePaddingRatio))
    }

    private func dateDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat =
            dateUnit == .day || dateUnit == .weekOfYear ? "d.M." : dateUnit == .month ? "MMM" : "MMM YY"
        return formatter.string(from: date).uppercased()
    }

    private func isInSameDateUnitAsNow(date: Date) -> Bool {
        switch dateUnit {
        case .day:
            return Calendar.current.isDate(date, inSameDayAs: Date())
        case .weekOfYear, .weekOfMonth:
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
        case .year:
            return Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        default:
            // For other units, you might need to adjust or add more cases.
            return false
        }
    }
}

struct DateBarChart_Previews: PreviewProvider {
    static var previews: some View {
        DateBarChart(dateUnit: .weekOfYear) {
            (1 ... 11)
                .map {
                    .init(
                        date: Date().addingTimeInterval(-7_882_880 + 788_288 * Double($0)),
                        value: Int.random(in: 0 ... 100)
                    )
                }
        }
        .frame(height: 250)
    }
}
