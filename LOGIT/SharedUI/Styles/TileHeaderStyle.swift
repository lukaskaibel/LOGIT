//
//  TileHeaderStyle.swift
//  LOGIT.
//
//  Created by Lukas Kaibel on 22.08.23.
//

import SwiftUI

struct TileHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold))
            .foregroundColor(.label)
    }
}

struct TileHeaderSecondaryModifier: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundColor(color ?? .secondaryLabel)
    }
}

struct TileHeaderTertiaryModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.secondaryLabel)
    }
}

extension View {
    func tileHeaderStyle() -> some View {
        modifier(TileHeaderModifier())
    }

    func tileHeaderSecondaryStyle(color: Color? = nil) -> some View {
        modifier(TileHeaderSecondaryModifier(color: color))
    }

    func tileHeaderTertiaryStyle() -> some View {
        modifier(TileHeaderTertiaryModifier())
    }
}

/// The standard tile header row: a title in `tileHeaderStyle`, an optional trailing accessory, and a
/// `NavigationChevron` — the one shared top row every navigable tile uses (`VolumeTile`, the
/// pinned-exercise tiles, …), so they can't drift apart. The accessory sits just left of the chevron
/// (e.g. a "+n more" count); pass `showsChevron: false` for a tile that isn't a button.
struct TileHeader<Accessory: View>: View {
    private let title: String
    private let showsChevron: Bool
    private let accessory: () -> Accessory

    init(_ title: String, showsChevron: Bool = true, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.showsChevron = showsChevron
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .tileHeaderStyle()
            Spacer(minLength: 8)
            accessory()
            if showsChevron {
                NavigationChevron()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension TileHeader where Accessory == EmptyView {
    init(_ title: String, showsChevron: Bool = true) {
        self.init(title, showsChevron: showsChevron) { EmptyView() }
    }
}
