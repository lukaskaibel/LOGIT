//
//  ProgressIndicatorPill.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 22.06.26.
//

import SwiftUI

/// The app's single progress-indicator pill: an optional leading SF Symbol — a trend arrow, a
/// trophy, an arrow, a clock — beside a label, on a translucent capsule tinted with an accent
/// style. Every trend, record, gain and lapsed pill in the app is built from this so the symbol
/// weight, capsule fill and 0.15 tint stay identical everywhere.
///
/// The accent is an `AnyShapeStyle`, so it can be a flat `Color` or a gradient — a single `Color`
/// can't carry a multi-muscle workout's gradient (see `Sequence.muscleGroupGradientStyle()`). It tints the
/// symbol, the label's default foreground and the capsule fill at 0.15 opacity. Pass
/// `Color.secondary` for the muted "decline / no change / metadata" look.
///
/// The label supplies its own fonts, so a one-line percent and the metric badge's two-line
/// value+name both fit. A gradient (`style:`) accent fills the symbol and label as one continuous
/// sweep (see `continuousForegroundStyle`) so the gradient doesn't restart inside each; a flat
/// (`color:`) accent keeps a plain foreground, so a per-glyph `foregroundStyle` inside the label
/// still wins over the pill's tint — the two-line badges rely on this.
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

    /// The leading SF Symbol — `arrow.up`/`arrow.down` for a trend, `trophy.fill` for a record,
    /// `arrow.up` for a gain, `minus` for "no change". Nil draws the label alone: a flat trend shows
    /// no icon so it can't be mistaken for a decline.
    let symbol: String?
    /// Tints the symbol, the label's default foreground and the capsule fill (at 0.15 opacity).
    let style: AnyShapeStyle
    let size: Size
    let label: Label
    /// Whether the symbol+label share one gradient sweep (the `style:` initializer) rather than each
    /// resolving it on its own — see `continuousForegroundStyle`. Off for the flat-`color:` badges
    /// whose two-line labels set their own per-line colors, which a single masked fill would flatten.
    private let fillsContinuously: Bool

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
        self.fillsContinuously = true
    }

    /// Convenience for a flat-color accent — the common case (a single muscle-group color).
    init(
        symbol: String?,
        color: Color,
        size: Size = .regular,
        @ViewBuilder label: () -> Label
    ) {
        self.symbol = symbol
        self.style = AnyShapeStyle(color)
        self.size = size
        self.label = label()
        self.fillsContinuously = false
    }

    var body: some View {
        tintedContent
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(Capsule().fill(style.opacity(0.15)))
        // The pill always takes its ideal width, so its label never compresses: a percent like
        // "100 %" can't wrap to two lines or ellipsize. Being rigid, the pill also claims its space
        // first in any HStack, so a neighbor (a tile title, an exercise name) truncates around it
        // rather than squeezing it. Vertical stays flexible for the metric badge's two-line label.
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Symbol + label, tinted by `style`. A gradient accent (the `style:` initializer) fills the
    /// symbol and label as one continuous sweep so the gradient doesn't restart inside each; a flat
    /// `color:` badge keeps a plain foreground so its label's own per-line colors survive.
    @ViewBuilder
    private var tintedContent: some View {
        let content = HStack(spacing: size.spacing) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            label
        }
        if fillsContinuously {
            content.continuousForegroundStyle(style)
        } else {
            content.foregroundStyle(style)
        }
    }
}

struct ProgressIndicatorPill_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            ProgressIndicatorPill(symbol: "arrow.up", color: .green) {
                Text("12 %").font(.system(.footnote, design: .rounded, weight: .bold))
            }
            ProgressIndicatorPill(symbol: "arrow.down", color: .secondary) {
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
