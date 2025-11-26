//
//  MeasurementTile.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.11.24.
//

import Charts
import SwiftUI

struct MeasurementTile: View {
    @EnvironmentObject var measurementController: MeasurementEntryController

    let measurementType: MeasurementEntryType

    private var entries: [MeasurementEntry] {
        measurementController.getMeasurementEntries(ofType: measurementType)
    }

    private var latestEntry: MeasurementEntry? {
        entries.first
    }

    var body: some View {
        VStack {
            HStack {
                Text(measurementType.title)
                    .tileHeaderStyle()
                Spacer()
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                Spacer()
                HStack {
                    Text(NSLocalizedString("noData", comment: ""))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text(NSLocalizedString("latest", comment: ""))
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .fontWeight(.semibold)
                        UnitView(
                            value: formatDecimal(latestEntry!.decimalValue),
                            unit: measurementType.unit.uppercased(),
                            configuration: .large
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                    }
                    Spacer()
                    miniChart
                }
            }
        }
        .padding(CELL_PADDING)
        .frame(height: 120)
        .tileStyle()
    }

    @ViewBuilder
    private var miniChart: some View {
        let chartEntries = Array(entries.prefix(20).reversed())
        Chart {
            if let firstEntry = chartEntries.first {
                LineMark(
                    x: .value("Date", Date.distantPast, unit: .day),
                    y: .value("Value", firstEntry.decimalValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(chartEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date ?? .now, unit: .day),
                    y: .value("Value", entry.decimalValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .symbol {
                    Circle()
                        .frame(width: 6, height: 6)
                        .foregroundStyle(Color.accentColor.gradient)
                        .overlay {
                            Circle()
                                .frame(width: 2, height: 2)
                                .foregroundStyle(Color.black)
                        }
                }
                AreaMark(
                    x: .value("Date", entry.date ?? .now, unit: .day),
                    y: .value("Value", entry.decimalValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Gradient(colors: [
                    Color.accentColor.opacity(0.3),
                    Color.accentColor.opacity(0.1),
                    Color.accentColor.opacity(0),
                ]))
            }
            if let lastEntry = chartEntries.last,
               let lastDate = lastEntry.date,
               !Calendar.current.isDateInToday(lastDate) {
                RuleMark(
                    xStart: .value("Start", lastDate),
                    xEnd: .value("End", Date()),
                    y: .value("Value", lastEntry.decimalValue)
                )
                .foregroundStyle(Color.accentColor.opacity(0.45))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        dash: [3, 6]
                    )
                )
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0 ... (entries.map { $0.decimalValue }.max() ?? 1) * 1.1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.frame(height: 70)
        }
        .frame(width: 120)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.1),
                    .init(color: .black, location: 1.0),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var xDomain: some ScaleDomain {
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: .now)!.startOfWeek
        return startDate ... Date.now
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

struct MeasurementTile_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeasurementTile(measurementType: .bodyweight)
                .padding()
                .previewEnvironmentObjects()
        }
    }
}
