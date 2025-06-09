//
//  DateLineChart.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 06.09.23.
//

import Charts
import SwiftUI

struct DateLineChart: View {
    struct Item: Identifiable {
        var id: String { "\(date)\(value)" }
        let date: Date
        let value: Int
    }

    enum DateDomain: Int {
        case threeMonths = 3
        case sixMonths = 6
        case year = 12
        case allTime = -1
    }

    // MARK: - Constants

    private let yValuePaddingRatio = 0.1

    // MARK: - Properties

    let dateDomain: DateDomain
    let items: [Item]

    init(dateDomain: DateDomain, items: () -> [Item]) {
        self.dateDomain = dateDomain
        self.items = items()
    }

    // MARK: - Body

    var body: some View {
        Chart {
            ForEach(items) { item in
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Value", item.value)
                )
                .interpolationMethod(.catmullRom)
                .symbol(by: .value("Value", "Value"))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(preset: .aligned) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(dateDescription(for: date))
                }
            }
        }
        .chartXScale(domain: [minXValue, Date.now])
        .chartYAxis {
            AxisMarks(values: [minYValue, maxYValue]) { value in
                if let value = value.as(Int.self) {
                    AxisGridLine()
                    AxisValueLabel(String(value))
                }
            }
        }
        .chartYScale(domain: [minYValue, maxYValue])
    }

    // MARK: - Computed Properties

    private var minXValue: Date {
        guard dateDomain != .allTime else {
            let minDate = items.map { $0.date }.min() ?? .now
            let oneYearAgo = Calendar.current.date(byAdding: .month, value: -12, to: .now) ?? .now
            return minDate < oneYearAgo ? minDate : oneYearAgo
        }
        return Calendar.current.date(byAdding: .month, value: -dateDomain.rawValue, to: .now)!
    }

    private var maxYValue: Int {
        (items.map { $0.value }.max() ?? 1) + yValuePadding
    }

    private var minYValue: Int {
        let result = (items.map { $0.value }.min() ?? 0) - yValuePadding
        return result > 0 ? result : 0
    }

    private var yValuePadding: Int {
        Int(ceil(Double(items.map { $0.value }.max() ?? 1) * yValuePaddingRatio))
    }

    private func dateDescription(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat =
            dateDomain == .threeMonths || dateDomain == .sixMonths ? "MMM" : "MMM YY"
        return formatter.string(from: date).uppercased()
    }
}

struct DateLineChart_Previews: PreviewProvider {
    static var previews: some View {
        DateLineChart(dateDomain: .sixMonths) {
            (1 ... 10)
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
