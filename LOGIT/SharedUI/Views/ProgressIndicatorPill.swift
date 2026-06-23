//
//  ProgressIndicatorPill.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import SwiftUI

/// The app's single progress-indicator pill: an optional leading SF Symbol — a trend chevron, a
/// trophy, an arrow, a clock — beside a label, on a translucent capsule tinted with an accent
/// style. Every trend, record, gain and lapsed pill in the app is built from this so the chevron
/// weight, capsule fill and 0.15 tint stay identical everywhere.
///
/// The accent is an `AnyShapeStyle`, so it can be a flat `Color` or a gradient — a single `Color`
/// can't carry a multi-muscle workout's gradient (see `Sequence.gradientStyle()`). It tints the
/// symbol, the label's default foreground and the capsule fill at 0.15 opacity. Pass
/// `Color.secondary` for the muted "decline / no change / metadata" look.
///
/// The label supplies its own fonts, so a one-line percent and the metric badge's two-line
/// value+name both fit; a per-glyph `foregroundStyle` inside the label wins over the pill's tint.
struct ProgressIndicatorPill<Label: View>: View {
    /// Padding and spacing presets. `.regular` is the trend / gain / "n improved" pill; `.prominent`
    /// is the in-workout metric badge (a touch wider for its two-line content); `.compact` is quieter
    /// metadata like the lapsed-tile pill — smaller and tighter, a size below a score.
    enum Size {
        case regular, prominent, compact

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 10
            case .prominent: return 12
            case .compact: return 8
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .regular, .prominent: return 6
            case .compact: return 5
            }
        }

        var spacing: CGFloat {
            switch self {
            case .regular, .prominent: return 4
            case .compact: return 3
            }
        }
    }

    /// The leading SF Symbol — `chevron.up`/`chevron.down` for a trend, `trophy.fill` for a record,
    /// `arrow.up` for a gain, `minus` for "no change". Nil draws the label alone: a flat trend shows
    /// no icon so it can't be mistaken for a decline.
    let symbol: String?
    /// Tints the symbol, the label's default foreground and the capsule fill (at 0.15 opacity).
    let style: AnyShapeStyle
    let size: Size
    let label: Label

    init(
        symbol: String?,
        style: AnyShapeStyle,
        size: Size = .regular,
        @ViewBuilder label: () -> Label
    ) {
        self.symbol = symbol
        self.style = style
        self.size = size
        self.label = label()
    }

    /// Convenience for a flat-color accent — the common case (a single muscle-group color).
    init(
        symbol: String?,
        color: Color,
        size: Size = .regular,
        @ViewBuilder label: () -> Label
    ) {
        self.init(symbol: symbol, style: AnyShapeStyle(color), size: size, label: label)
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            label
        }
        .foregroundStyle(style)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(Capsule().fill(style.opacity(0.15)))
    }
}

struct ProgressIndicatorPill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            ProgressIndicatorPill(symbol: "chevron.up", color: .green) {
                Text("12 %").font(.system(.footnote, design: .rounded, weight: .bold))
            }
            ProgressIndicatorPill(symbol: "chevron.down", color: .secondary) {
                Text("8 %").font(.system(.footnote, design: .rounded, weight: .bold))
            }
            ProgressIndicatorPill(
                symbol: "trophy.fill",
                style: AnyShapeStyle(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            ) {
                Text("+5 kg").font(.system(.footnote, design: .rounded, weight: .bold))
            }
            ProgressIndicatorPill(symbol: "clock.arrow.circlepath", color: .secondary, size: .compact) {
                Text("2 mo").font(.system(.caption2, design: .rounded, weight: .bold))
            }
        }
        .padding()
    }
}
