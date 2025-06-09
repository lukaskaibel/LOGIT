//
//  WidgetCollection+.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 12.09.23.
//

import Foundation

extension WidgetCollection {
    var type: WidgetCollectionType {
        WidgetCollectionType(rawValue: id!)!
    }

    var items: [Widget] {
        get {
            return (itemOrder ?? .emptyList)
                .compactMap { id in (items_?.allObjects as? [Widget])?.first { $0.id == id } }
        }
        set {
            itemOrder = newValue.map { $0.id! }
            items_ = NSSet(array: newValue)
        }
    }
}
