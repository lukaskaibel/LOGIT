//
//  DraggableFullScreenCover.swift
//  FullScreenDraggableCoverTest
//
//  Created by Lukas Kaibel on 05.03.24.
//

import SwiftUI

let Y_OFFSET_THRESHOLD_FOR_DISMISS: CGFloat = 1 / 3

struct FullScreenDraggableCover<ScreenContent: View, Background: ShapeStyle>: ViewModifier {
    @State private var animateContent: Bool = false
    @State private var yOffset: CGFloat = 0
    @State private var dragGestureChanged: (DragGesture.Value) -> Void = { _ in }
    @State private var dragGestureEnded: (DragGesture.Value) -> Void = { _ in }

    @FocusState private var bringFocusToCover: Bool

    @Binding var isPresented: Bool
    let background: Background
    let screenContent: () -> ScreenContent

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .overlay {
                Group {
                    GeometryReader { geometry in
                        if isPresented {
                            screenContent()
                                .environment(\.fullScreenDraggableCoverIsDragging, yOffset != 0 && isPresented)
                                .environment(\.fullScreenDraggableCoverTopInset, yOffset == 0 ? 1 : yOffset < geometry.safeAreaInsets.top ? yOffset : geometry.safeAreaInsets.top + (geometry.safeAreaInsets.bottom == 0 ? 10 : 0))
                                .environment(\.fullScreenDraggableDragChanged) { value in
                                    guard yOffset + value.translation.height > 0 else { yOffset = 0; return }
                                    yOffset = value.translation.height
                                }
                                .environment(\.fullScreenDraggableDragEnded) { _ in
                                    if yOffset > geometry.size.height * Y_OFFSET_THRESHOLD_FOR_DISMISS {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 1.0)) {
                                            yOffset = geometry.size.height + geometry.safeAreaInsets.top
                                        } completion: {
                                            isPresented = false
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                yOffset = 0
                                            }
                                        }
                                    } else {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            yOffset = 0
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .clipped()
                                .background(background)
                                .clipShape(RoundedRectangle(cornerRadius: yOffset != 0 ? UIScreen.main.displayCornerRadius : 0, style: .continuous))
                                .offset(y: yOffset > 0 ? yOffset : 0)
                                .ignoresSafeArea(.container, edges: .all)
                                .ignoresSafeArea(.keyboard)
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .animation(
                        .spring(response: 0.2, dampingFraction: 1.0),
                        value: isPresented
                    )
                }
            }
    }
}

private struct FullScreenDraggableCoverDragAreaModifier: ViewModifier {
    @Environment(\.fullScreenDraggableDragChanged) var fullScreenDraggableDragChanged
    @Environment(\.fullScreenDraggableDragEnded) var fullScreenDraggableDragEnded

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        fullScreenDraggableDragChanged(value)
                    }
                    .onEnded { value in
                        fullScreenDraggableDragEnded(value)
                    }
            )
    }
}

private struct FullScreenDraggableCoverTopInsetModifier: ViewModifier {
    @Environment(\.fullScreenDraggableCoverTopInset) var fullScreenDraggableCoverTopInset

    func body(content: Content) -> some View {
        content
            .padding(.top, fullScreenDraggableCoverTopInset)
    }
}

extension View {
    @ViewBuilder
    func fullScreenDraggableCover<Content: View>(isPresented: Binding<Bool>, content: @escaping () -> Content) -> some View {
        modifier(FullScreenDraggableCover(isPresented: isPresented, background: Color.background, screenContent: content))
    }

    @ViewBuilder
    func fullScreenDraggableCoverDragArea() -> some View {
        modifier(FullScreenDraggableCoverDragAreaModifier())
    }

    @ViewBuilder
    func fullScreenDraggableCoverTopInset() -> some View {
        modifier(FullScreenDraggableCoverTopInsetModifier())
    }
}

private struct FullScreenDraggableCoverTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct FullScreenDraggableCoverDragChangedKey: EnvironmentKey {
    static let defaultValue: (DragGesture.Value) -> Void = { _ in }
}

private struct FullScreenDraggableCoverDragEndedKey: EnvironmentKey {
    static let defaultValue: (DragGesture.Value) -> Void = { _ in }
}

private struct FullScreenDraggableCoverIsDragging: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var fullScreenDraggableCoverIsDragging: Bool {
        get { self[FullScreenDraggableCoverIsDragging.self] }
        set { self[FullScreenDraggableCoverIsDragging.self] = newValue }
    }

    var fullScreenDraggableCoverTopInset: CGFloat {
        get { self[FullScreenDraggableCoverTopInsetKey.self] }
        set { self[FullScreenDraggableCoverTopInsetKey.self] = newValue }
    }

    var fullScreenDraggableDragChanged: (DragGesture.Value) -> Void {
        get { self[FullScreenDraggableCoverDragChangedKey.self] }
        set { self[FullScreenDraggableCoverDragChangedKey.self] = newValue }
    }

    var fullScreenDraggableDragEnded: (DragGesture.Value) -> Void {
        get { self[FullScreenDraggableCoverDragEndedKey.self] }
        set { self[FullScreenDraggableCoverDragEndedKey.self] = newValue }
    }
}

// MARK: - Preview

struct PreviewWrapperr: View {
    @State private var isShowingFullScreenCover = true
    @State private var isShowingTestSheet = false

    var body: some View {
        TabView {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Button {
                    isShowingFullScreenCover = true
                } label: {
                    Text("Show Full Screen Cover")
                }
            }
            .padding()
            .tabItem { Label("Home", systemImage: "house") }
        }
        .fullScreenDraggableCover(isPresented: $isShowingFullScreenCover) {
            VStack {
                Rectangle()
                    .frame(width: 60, height: 60)
                    .fullScreenDraggableCoverTopInset()
                    .fullScreenDraggableCoverDragArea()
                Button {
                    isShowingTestSheet = true
                } label: {
                    Text("Show Sheet")
                }
                .navigationTitle("Draggable Full Screen")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $isShowingTestSheet) {
                    NavigationView {
                        Text("Sheet")
                    }
                    .presentationBackground(.thinMaterial)
                }
            }
            .background(.red)
        }
    }
}

#Preview {
    PreviewWrapperr()
}
