//
//  ReorderableForEach.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 07.09.23.
//

import SwiftUI

public typealias Reorderable = Equatable & Identifiable

struct ReorderableForEach<Content: View, Item: Reorderable>: View {
    // MARK: - Constants

    private let itemDragType = ".com.lukaskbl.itemDragType"
    private let allowedSecondsOutsideDropArea = 5.0

    // MARK: - Properties

    @Binding var items: [Item]
    let canReorder: Bool
    @Binding var isReordering: Bool
    let onOrderChanged: (() -> Void)?
    let content: (Item) -> Content

    // MARK: - State

    @State private var draggedItem: Item?
    @State private var isDraggingOnValidDropDestination = false
    @State private var stopDraggingTimer: Timer?

    // MARK: - Init

    init(
        _ items: Binding<[Item]>,
        canReorder: Bool = true,
        isReordering: Binding<Bool> = .constant(false),
        onOrderChanged: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        _items = items
        self.canReorder = canReorder
        _isReordering = isReordering
        self.onOrderChanged = onOrderChanged
        self.content = content
    }

    var body: some View {
        if canReorder {
            ForEach(items) { item in
                content(item)
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedItem = item
                        isDraggingOnValidDropDestination = true
                        return NSItemProvider(
                            item: "\(item.id)" as NSSecureCoding,
                            typeIdentifier: itemDragType
                        )
                    }
                    .onDrop(
                        of: [itemDragType],
                        delegate: DropViewDelegate(
                            destinationItem: item,
                            items: $items,
                            draggedItem: $draggedItem,
                            isDraggingOnValidDropDestination: $isDraggingOnValidDropDestination,
                            onOrderChanged: onOrderChanged
                        )
                    )
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        draggedItem = nil
                    }
            )
            .onChange(of: draggedItem) { value in
                isReordering = value != nil
            }
            .onChange(of: isDraggingOnValidDropDestination) { value in
                guard !value else {
                    stopDraggingTimer?.invalidate()
                    stopDraggingTimer = nil
                    return
                }
                stopDraggingTimer = Timer.scheduledTimer(
                    withTimeInterval: allowedSecondsOutsideDropArea,
                    repeats: false
                ) { _ in
                    draggedItem = nil
                }
            }
        } else {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

struct DropViewDelegate<Item: Reorderable>: DropDelegate {
    let destinationItem: Item
    @Binding var items: [Item]
    @Binding var draggedItem: Item?
    @Binding var isDraggingOnValidDropDestination: Bool
    let onOrderChanged: (() -> Void)?

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info _: DropInfo) {
        isDraggingOnValidDropDestination = true
        // Swap Items
        if let draggedItem {
            let fromIndex = items.firstIndex(of: draggedItem)
            if let fromIndex {
                let toIndex = items.firstIndex(of: destinationItem)
                if let toIndex, fromIndex != toIndex {
                    UISelectionFeedbackGenerator().selectionChanged()
                    items.move(
                        fromOffsets: IndexSet(integer: fromIndex),
                        toOffset: toIndex > fromIndex ? (toIndex + 1) : toIndex
                    )
                    onOrderChanged?()
                }
            }
        }
    }

    func dropExited(info _: DropInfo) {
        isDraggingOnValidDropDestination = false
    }
}

// MARK: - Preview

private struct PreviewWrapperView: View {
    struct Item: Codable, Reorderable {
        var id: Int { value }
        let value: Int
    }

    @State private var data = [1, 2, 3, 4, 5].map { Item(value: $0) }

    var body: some View {
        VStack {
            ReorderableForEach($data) { item in
                Button {
                    print("Test")
                } label: {
                    Text(String(item.value))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ReorderableForEach_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapperView()
    }
}
