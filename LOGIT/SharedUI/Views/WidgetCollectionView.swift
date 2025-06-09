//
//  WidgetCollectionView.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 11.09.23.
//

import SwiftUI

struct WidgetCollectionView<Content: View>: View {
    @EnvironmentObject private var database: Database
    @EnvironmentObject private var purchaseManager: PurchaseManager

    let type: WidgetCollectionType
    let title: String
    let views: [WidgetView<Content>]

    @StateObject private var collection: WidgetCollection
    @State private var isShowingUpgradeToPro = false

    init(type: WidgetCollectionType, title: String, views: [WidgetView<Content>], database: Database) {
        self.type = type
        self.title = title
        self.views = views
        _collection = StateObject(wrappedValue: Self.createWidgetCollectionIfNotExisting(withId: type.rawValue, in: database))
    }

    var body: some View {
        VStack(spacing: SECTION_HEADER_SPACING) {
            HStack {
                Text(title)
                    .sectionHeaderStyle2()
                Spacer()
                Menu {
                    ForEach(collection.items) { item in
                        if let type = item.type {
                            let canUseFeature = !item.isProFeature || purchaseManager.hasUnlockedPro
                            Button {
                                if canUseFeature {
                                    item.isAdded.toggle()
                                    database.save()
                                } else {
                                    isShowingUpgradeToPro = true
                                }
                            } label: {
                                Text(type.title)
                                Text(type.unit)
                                if canUseFeature {
                                    Image(systemName: item.isAdded ? "checkmark" : "plus")
                                } else {
                                    Image(systemName: "crown.fill")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.square.dashed")
                        .font(.title2)
                        .foregroundStyle(Color.label)
                }
            }
            VStack(spacing: CELL_SPACING) {
                ReorderableForEach(
                    $collection.items,
                    onOrderChanged: { database.save() }
                ) { item in
                    if item.isAdded, let widgetView = views.first(where: { $0.type == item.type }) {
                        widgetView
                            .transition(.scale)
                            .isBlockedWithoutPro(item.isProFeature)
                    }
                }
            }
            .emptyPlaceholder(collection.items.filter { $0.isAdded }) {
                Text(NSLocalizedString("noWidgetsAdded", comment: ""))
            }
            .animation(.interactiveSpring())
        }
        .onAppear {
            for view in views {
                createWidgetIfNotExisting(
                    withId: view.type.rawValue,
                    for: collection,
                    isAdded: view.isAddedByDefault
                )
            }
        }
        .sheet(isPresented: $isShowingUpgradeToPro) {
            UpgradeToProScreen()
        }
    }

    // MARK: - Supporting Methods

    func createWidgetIfNotExisting(
        withId id: String,
        for collection: WidgetCollection,
        isAdded: Bool
    ) {
        guard !collection.items.map({ $0.id }).contains(where: { $0 == id }) else { return }
        let item = Widget(context: database.context)
        item.id = id
        item.isAdded = isAdded
        collection.items.append(item)
    }

    @discardableResult
    static func createWidgetCollectionIfNotExisting(withId id: String, in database: Database) -> WidgetCollection {
        let predicate = NSPredicate(format: "id == %@", id)
        var collection =
            database.fetch(WidgetCollection.self, predicate: predicate).first as? WidgetCollection
        if collection == nil {
            collection = WidgetCollection(context: database.context)
            collection!.id = id
        }
        return collection!
    }
}

struct WidgetView<Content: View>: View {
    let type: WidgetType
    let isAddedByDefault: Bool
    let content: Content

    var body: some View {
        content
    }
}

extension View {
    func widget(ofType type: WidgetType, isAddedByDefault: Bool) -> WidgetView<AnyView> {
        WidgetView(type: type, isAddedByDefault: isAddedByDefault, content: AnyView(self))
    }
}

// MARK: - Preview

// private struct PreviewWrapperView: View {
//
//    @State private var items: [WidgetCollectionView.Item] = [.init(id: "1", name: "1", content: AnyView(Text("1")), isAdded: false), .init(id: "2", name: "2", content: AnyView(Text("2")), isAdded: true), .init(id: "3", name: "3", content: AnyView(Text("3")), isAdded: false)]
//
//    var body: some View {
//        OverviewView(items: $items)
//    }
//
// }
//
// struct OverviewView_Previews: PreviewProvider {
//    static var previews: some View {
//        PreviewWrapperView()
//    }
// }
