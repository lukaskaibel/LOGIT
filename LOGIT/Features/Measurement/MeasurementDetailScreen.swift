//
//  MeasurementDetailScreen.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 26.11.24.
//

import Charts
import SwiftUI

struct MeasurementDetailScreen: View {
    private enum ChartGranularity {
        case month, year
    }

    @EnvironmentObject var measurementController: MeasurementEntryController

    let measurementType: MeasurementEntryType

    @State private var chartGranularity: ChartGranularity = .month
    @State private var chartScrollPosition: Date = .now
    @State private var selectedDate: Date?
    @State private var isAddingEntry = false
    @State private var newEntryDate: Date = .now
    @State private var newEntryValue: Double = 0

    private var entries: [MeasurementEntry] {
        measurementController.getMeasurementEntries(ofType: measurementType)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SECTION_SPACING) {
                chartSection
                entriesListSection
            }
            .padding(.horizontal)
            .padding(.bottom, SCROLLVIEW_BOTTOM_PADDING)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack {
                    Text(measurementType.title)
                        .font(.headline)
                    Text(NSLocalizedString("measurements", comment: ""))
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingEntry = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingEntry) {
            addEntrySheet
        }
        .onAppear {
            initializeChartScrollPosition()
        }
        .onChange(of: chartGranularity) { _ in
            initializeChartScrollPosition()
        }
    }

    // MARK: - Chart Section

    @ViewBuilder
    private var chartSection: some View {
        let snappedSelectedEntry = selectedDate != nil ? nearestEntry(to: selectedDate) : nil
        let bestVisibleValue = bestValueInGranularity()

        VStack {
            Picker("Select Chart Granularity", selection: $chartGranularity) {
                Text(NSLocalizedString("month", comment: ""))
                    .tag(ChartGranularity.month)
                Text(NSLocalizedString("year", comment: ""))
                    .tag(ChartGranularity.year)
            }
            .pickerStyle(.segmented)
            .padding(.vertical)

            VStack(alignment: .leading) {
                Text(NSLocalizedString("best", comment: ""))
                    .font(.footnote)
                    .fontWeight(.medium)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                if let bestVisibleValue = bestVisibleValue {
                    UnitView(
                        value: formatDecimal(bestVisibleValue),
                        unit: measurementType.unit.uppercased()
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                }
                Text(chartHeaderTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart {
                if selectedDate != nil, let selectedEntry = snappedSelectedEntry, let sDate = selectedEntry.date {
                    let snapped = Calendar.current.startOfDay(for: sDate)
                    RuleMark(x: .value("Selected", snapped, unit: .day))
                        .foregroundStyle(Color.accentColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading) {
                                UnitView(
                                    value: formatDecimal(selectedEntry.decimalValue),
                                    unit: measurementType.unit.uppercased()
                                )
                                .foregroundStyle(Color.accentColor.gradient)
                                Text(snapped.formatted(.dateTime.day().month()))
                                    .fontWeight(.bold)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondaryBackground))
                        }
                }

                if let firstEntry = entries.last {
                    LineMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Value", firstEntry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .opacity(snappedSelectedEntry == nil ? 1.0 : 0.3)
                    AreaMark(
                        x: .value("Date", Date.distantPast, unit: .day),
                        y: .value("Value", firstEntry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        Color.accentColor.opacity(0.5),
                        Color.accentColor.opacity(0.2),
                        Color.accentColor.opacity(0.05),
                    ]))
                    .opacity(snappedSelectedEntry == nil ? 1.0 : 0.3)
                }

                ForEach(entries.reversed()) { entry in
                    LineMark(
                        x: .value("Date", entry.date ?? .now, unit: .day),
                        y: .value("Value", entry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.accentColor.gradient)
                    .lineStyle(StrokeStyle(lineWidth: 5))
                    .symbol {
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(
                                Color.accentColor.gradient
                                    .opacity({
                                        guard let s = snappedSelectedEntry?.date else { return 1.0 }
                                        return Calendar.current.isDate(entry.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                                    }())
                            )
                            .overlay {
                                Circle()
                                    .frame(width: 4, height: 4)
                                    .foregroundStyle(Color.black)
                            }
                            .background(Circle().fill(Color.black))
                    }
                    .opacity({
                        guard let s = snappedSelectedEntry?.date else { return 1.0 }
                        return Calendar.current.isDate(entry.date ?? .distantPast, inSameDayAs: s) ? 1.0 : 0.3
                    }())
                    AreaMark(
                        x: .value("Date", entry.date ?? .now, unit: .day),
                        y: .value("Value", entry.decimalValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Gradient(colors: [
                        Color.accentColor.opacity(0.5),
                        Color.accentColor.opacity(0.2),
                        Color.accentColor.opacity(0.05),
                    ]))
                    .opacity(selectedDate == nil ? 1.0 : 0.0)
                }

                if selectedDate == nil, let lastEntry = entries.first, let lastDate = lastEntry.date, !Calendar.current.isDateInToday(lastDate) {
                    RuleMark(
                        xStart: .value("Start", lastDate),
                        xEnd: .value("End", Date()),
                        y: .value("Value", lastEntry.decimalValue)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 5,
                            lineCap: .round,
                            dash: [5, 10]
                        )
                    )
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: 0.0 ... chartYScaleMax)
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: $chartScrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: chartGranularity == .month ? DateComponents(weekday: Calendar.current.firstWeekday) : DateComponents(month: 1, day: 1)
                )
            )
            .chartXSelection(value: $selectedDate)
            .chartXVisibleDomain(length: visibleChartDomainInSeconds)
            .chartXAxis {
                AxisMarks(
                    position: .bottom,
                    values: .stride(by: chartGranularity == .month ? .weekOfYear : .month)
                ) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.5))
                        AxisValueLabel(xAxisDateString(for: date))
                            .foregroundStyle(isDateNow(date) ? Color.primary : .secondary)
                            .font(.caption.weight(.bold))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0.0, chartYScaleMax / 2.0, chartYScaleMax])
            }
            .emptyPlaceholder(entries) {
                Text(NSLocalizedString("noData", comment: ""))
            }
            .frame(height: 300)
            .padding(.trailing, 5)
        }
        .isBlockedWithoutPro()
    }

    // MARK: - Entries List Section

    @ViewBuilder
    private var entriesListSection: some View {
        VStack(alignment: .leading, spacing: SECTION_HEADER_SPACING) {
            Text(NSLocalizedString("allEntries", comment: "All Entries"))
                .tileHeaderStyle()
            VStack(spacing: CELL_SPACING) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.date?.description(.short) ?? NSLocalizedString("noDate", comment: ""))
                        Spacer()
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(formatDecimal(entry.decimalValue))
                                .font(.title3)
                            Text(measurementType.unit)
                                .font(.footnote)
                                .textCase(.uppercase)
                        }
                        .fontWeight(.semibold)
                    }
                    .padding(CELL_PADDING)
                    .onDeleteView {
                        withAnimation {
                            measurementController.deleteMeasurementEntry(entry)
                        }
                    }
                    .tileStyle()
                }
            }
            .emptyPlaceholder(entries) {
                Text(NSLocalizedString("noData", comment: ""))
            }
        }
    }

    // MARK: - Add Entry Sheet

    @ViewBuilder
    private var addEntrySheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    NSLocalizedString("date", comment: ""),
                    selection: $newEntryDate,
                    displayedComponents: [.date]
                )
                HStack {
                    Text(NSLocalizedString("value", comment: ""))
                    Spacer()
                    DecimalField(
                        placeholder: 0,
                        value: $newEntryValue,
                        maxDigits: 4,
                        decimalPlaces: 1,
                        index: .init(primary: 0),
                        focusedIntegerFieldIndex: .constant(nil),
                        unit: measurementType.unit
                    )
                }
            }
            .navigationTitle(NSLocalizedString("addMeasurement", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        resetNewEntry()
                        isAddingEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("add", comment: "")) {
                        measurementController.addMeasurementEntry(
                            ofType: measurementType,
                            decimalValue: newEntryValue,
                            onDate: newEntryDate
                        )
                        resetNewEntry()
                        isAddingEntry = false
                    }
                    .fontWeight(.bold)
                    .disabled(newEntryValue == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Private Methods

    private func initializeChartScrollPosition() {
        let anchor: Date
        switch chartGranularity {
        case .month:
            anchor = Calendar.current.date(byAdding: .day, value: 1, to: .now.endOfWeek)!
        case .year:
            anchor = Calendar.current.date(byAdding: .month, value: 1, to: .now.startOfMonth)!
        }
        chartScrollPosition = Calendar.current.date(byAdding: .second, value: -visibleChartDomainInSeconds, to: anchor)!
    }

    private func resetNewEntry() {
        newEntryDate = .now
        newEntryValue = 0
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private var visibleChartDomainInSeconds: Int {
        3600 * 24 * (chartGranularity == .month ? 35 : 365)
    }

    private var xDomain: ClosedRange<Date> {
        let maxStartDate = Calendar.current.date(
            byAdding: chartGranularity == .month ? .month : .year,
            value: -1,
            to: .now
        )!
        let endDate = chartGranularity == .month ? Date.now.endOfWeek : Date.now.endOfYear
        guard let firstEntryDate = entries.last?.date, firstEntryDate < maxStartDate
        else { return maxStartDate ... endDate }
        let startDate = chartGranularity == .month ? firstEntryDate.startOfMonth : firstEntryDate.startOfYear
        return startDate ... endDate
    }

    private var chartYScaleMax: Double {
        let maxValue = entries.map { $0.decimalValue }.max() ?? 100
        let yAxisMaxValues: [Double] = [10, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000]
        return yAxisMaxValues.filter { $0 > maxValue }.min() ?? maxValue
    }

    private func xAxisDateString(for date: Date) -> String {
        switch chartGranularity {
        case .month:
            return date.formatted(.dateTime.day().month(.defaultDigits))
        case .year:
            return date.formatted(Date.FormatStyle().month(.narrow))
        }
    }

    private func isDateNow(_ date: Date) -> Bool {
        switch chartGranularity {
        case .month:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.weekOfYear, .yearForWeekOfYear])
        case .year:
            return Calendar.current.isDate(date, equalTo: .now, toGranularity: [.month, .year])
        }
    }

    private var chartHeaderTitle: String {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        switch chartGranularity {
        case .month:
            return "\(chartScrollPosition.isInCurrentYear ? chartScrollPosition.formatted(.dateTime.day().month()) : chartScrollPosition.formatted(.dateTime.day().month().year())) - \(endDate.isInCurrentYear ? endDate.formatted(.dateTime.day().month()) : endDate.formatted(.dateTime.day().month().year()))"
        case .year:
            return "\(chartScrollPosition.formatted(.dateTime.month().year())) - \(endDate.formatted(.dateTime.month().year()))"
        }
    }

    private func bestValueInGranularity() -> Double? {
        let endDate = Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
        let entriesInTimeFrame = entries.filter { ($0.date ?? .distantPast) >= chartScrollPosition && ($0.date ?? .distantFuture) <= endDate }

        guard !entriesInTimeFrame.isEmpty else {
            return entries.first.map { $0.decimalValue }
        }

        return entriesInTimeFrame
            .map { $0.decimalValue }
            .max()
    }

    private var visibleEndDate: Date {
        Calendar.current.date(byAdding: .second, value: visibleChartDomainInSeconds, to: chartScrollPosition)!
    }

    private func nearestEntry(to date: Date?) -> MeasurementEntry? {
        let visibleEntries = entries.filter {
            guard let d = $0.date else { return false }
            return d >= chartScrollPosition && d <= visibleEndDate
        }
        let candidates = visibleEntries.isEmpty ? entries : visibleEntries
        guard !candidates.isEmpty else { return nil }
        guard let target = date else { return nil }
        return candidates.min { a, b in
            let ad = a.date ?? .distantPast
            let bd = b.date ?? .distantPast
            return abs(ad.timeIntervalSince(target)) < abs(bd.timeIntervalSince(target))
        }
    }
}

struct MeasurementDetailScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MeasurementDetailScreen(measurementType: .bodyweight)
                .previewEnvironmentObjects()
        }
    }
}
