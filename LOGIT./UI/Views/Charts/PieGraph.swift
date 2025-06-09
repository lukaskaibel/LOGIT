//
//  PieGraph.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 01.06.22.
//

import SwiftUI

struct PieGraph<CenterView: View>: View {
    enum Configuration {
        case normal, small
    }

    let items: [Item]
    let circleLineWidth: CGFloat
    let configuration: Configuration
    let centerView: CenterView?
    let showZeroValuesInLegend: Bool
    let hideLegend: Bool

    init(
        items: [Item],
        configuration: Configuration = .normal,
        centerView: CenterView? = Spacer(),
        showZeroValuesInLegend: Bool = false,
        hideLegend: Bool = false
    ) {
        self.items = items.filter { showZeroValuesInLegend ? true : $0.amount > 0 }
        circleLineWidth = configuration == .small ? 10 : 15
        self.configuration = configuration
        self.centerView = centerView
        self.showZeroValuesInLegend = showZeroValuesInLegend
        self.hideLegend = hideLegend
    }

    var body: some View {
        HStack {
            if configuration == .normal && !hideLegend {
                HStack {
                    Grid(verticalSpacing: 5) {
                        ForEach(0 ..< ((items.count + 1) / 2), id: \.self) { index in
                            GridRow {
                                HStack {
                                    itemView(for: items[index * 2])
                                    if items.indices.contains(index * 2 + 1) {
                                        itemView(for: items[index * 2 + 1])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ZStack {
                Circle()
                    .stroke(lineWidth: circleLineWidth)
                    .foregroundStyle(Color.placeholder.gradient)
                ForEach(items) { item in
                    Circle()
                        .trim(from: trimFrom(for: item) + 0.001, to: trimTo(for: item) - 0.001)
                        .stroke(
                            style: StrokeStyle(
                                lineWidth: circleLineWidth * (item.isSelected ? 1.5 : 1.0)
                            )
                        )
//                        .rotation(Angle(degrees: -90))
                        .foregroundStyle(item.color.gradient)
                        .shadow(radius: item.isSelected ? 5 : 0)
                }
//                if let centerView = centerView {
//                    centerView
//                }
            }
            .padding(circleLineWidth / 2)
            .background(.red)
            .padding(configuration == .small ? 5 : 15)
        }
    }

    @ViewBuilder
    private func itemView(for item: Item) -> some View {
        VStack(alignment: .leading) {
            Text(item.title)
                .foregroundColor(.primary)
            UnitView(value: "\(percentage(for: item))", unit: "%")
                .foregroundStyle((item.amount > 0 ? item.color : .placeholder).gradient)
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    private var overallAmount: Int {
        items.map(\.amount).reduce(0, +)
    }

    private func percentage(for item: Item) -> Int {
        guard overallAmount > 0 else { return 0 }
        return Int(round(Float(item.amount) / Float(overallAmount) * 100))
    }

    private func trimFrom(for item: Item) -> CGFloat {
        guard overallAmount > 0 else { return 0.0 }
        return
            items
                .prefix(items.firstIndex { $0 == item } ?? 0)
                .map { CGFloat($0.amount) / CGFloat(overallAmount) }
                .reduce(0, +)
    }

    private func trimTo(for item: Item) -> CGFloat {
        guard overallAmount > 0 else { return 0.0 }
        return
            items
                .prefix((items.firstIndex { $0 == item } ?? 0) + 1)
                .map { CGFloat($0.amount) / CGFloat(overallAmount) }
                .reduce(0, +)
    }

    struct Item: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let amount: Int
        let color: Color
        let isSelected: Bool
    }
}

struct PieGraph_Previews: PreviewProvider {
    static var previews: some View {
        PieGraph(
            items: [
                PieGraph.Item(title: "Chest", amount: 4, color: .blue, isSelected: false),
                PieGraph.Item(title: "Back", amount: 3, color: .green, isSelected: false),
                PieGraph.Item(title: "Arms", amount: 4, color: .yellow, isSelected: true),
                PieGraph.Item(title: "Shoulders", amount: 2, color: .purple, isSelected: false),
                PieGraph.Item(title: "Abs", amount: 1, color: .cyan, isSelected: false),
                PieGraph.Item(title: "Legs", amount: 2, color: .red, isSelected: false),
            ],
            configuration: .normal,
            centerView: Text("3")
        )
        .frame(height: 200)
        .tileStyle()
        .padding()
    }
}
