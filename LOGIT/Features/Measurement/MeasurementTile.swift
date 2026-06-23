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
                            unit: measurementType.unit,
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
            tileSparklineMarks(
                points: chartEntries.map {
                    TileSparklinePoint(date: $0.date ?? .now, value: $0.decimalValue)
                },
                color: .accentColor
            )
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0 ... (entries.map { $0.decimalValue }.max() ?? 1) * 1.1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .tileSparklineChartStyle()
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
