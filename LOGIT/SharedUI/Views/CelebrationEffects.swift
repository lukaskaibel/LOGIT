//
//  CelebrationEffects.swift
//  LOGIT
//
//  Created by Lukas Kaibel on 21.09.26.
//

import CoreHaptics
import SwiftUI
import UIKit
import Vortex

// MARK: - Confetti

/// One burst of confetti to fire: from what, in what colours.
struct ConfettiBurst: Identifiable, Equatable {
    let id: Int
    /// The frame of the thing it leaves, in global coordinates — the pieces are born across all of
    /// it, so the burst reads as coming out of that thing rather than out of a point near it. Nil
    /// fires from the top third of the screen.
    let origin: CGRect?
    let colors: [Color]
}

/// Small bursts of confetti fired out of things on screen, dissolving where they hang.
///
/// **Earned, never routine.** The finish panel fires one from each personal record's number, in that
/// exercise's colour, as it climbs — not for every finished workout, and not for the week.
/// A reward that arrives every time stops meaning anything, and one that arrives for something real
/// keeps meaning it.
///
/// **Small, and tied to its number.** A burst is a small fountain of pieces born across the number
/// itself, not a screenful from somewhere near it: a screen-wide explosion read as the app losing
/// it, and pieces raining down through the rows below no longer said which number they were for.
/// Tuned offline against Vortex's own integration: the pieces rise about 100 pt in a narrow fan,
/// turn over and fall back, shrinking to nothing over their 1.4 s life, so the burst dissolves
/// around its number rather than falling out of the bottom of the screen.
///
/// **Only while it's alive.** Vortex draws with a `TimelineView` that ticks as long as it is in the
/// tree, particles or not, so each burst lives in its own view that is removed once its pieces are
/// gone — no idle 120 Hz timeline behind the rest of the session.
struct CelebrationConfetti: View {
    /// Every burst fired so far; new ones are mounted as they are appended.
    let bursts: [ConfettiBurst]

    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mounted: [Mounted] = []
    @State private var seen: Set<Int> = []

    private struct Mounted: Identifiable {
        let id: Int
        let system: VortexSystem
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(mounted) { burst in
                    VortexView(burst.system, targetFrameRate: 120) {
                        Self.symbols
                    }
                }
            }
            .onChange(of: bursts.map(\.id)) { _, ids in
                guard !reduceMotion else { return }
                let frame = proxy.frame(in: .global)
                for burst in bursts where !seen.contains(burst.id) {
                    seen.insert(burst.id)
                    let origin = burst.origin
                        ?? CGRect(x: frame.midX, y: frame.minY + frame.height * 0.3, width: 0, height: 0)
                    let width = max(frame.width, 1)
                    let height = max(frame.height, 1)
                    let system = Self.system(
                        at: SIMD2(Double((origin.midX - frame.minX) / width), Double((origin.midY - frame.minY) / height)),
                        // Vortex's box spreads half its size each way, so this covers the number.
                        across: SIMD2(Double(origin.width / width), Double(origin.height / height)),
                        colors: resolve(burst.colors)
                    )
                    mounted.append(Mounted(id: burst.id, system: system))
                    let id = burst.id
                    Task { @MainActor in
                        // The lifespan plus a little, so nothing is cut off.
                        try? await Task.sleep(for: .seconds(system.lifespan + 0.4))
                        mounted.removeAll { $0.id == id }
                    }
                }
                if ids.isEmpty { seen.removeAll() }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// White shapes the system tints per piece: long strips (the ones that visibly tumble), squares,
    /// and a few dots.
    @ViewBuilder
    private static var symbols: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white)
            .frame(width: 7, height: 14)
            .tag("strip")
        RoundedRectangle(cornerRadius: 1.5)
            .fill(.white)
            .frame(width: 9, height: 9)
            .tag("square")
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .tag("dot")
    }

    private func resolve(_ colors: [Color]) -> [VortexSystem.Color] {
        let palette = colors.isEmpty ? [Color.accentColor, .white] : colors
        return palette.map { color in
            let resolved = color.resolve(in: environment)
            return VortexSystem.Color(
                red: Double(resolved.red),
                green: Double(resolved.green),
                blue: Double(resolved.blue),
                opacity: Double(resolved.opacity)
            )
        }
    }

    /// One burst, emitted over its first frames: Vortex's `burst()` is only reachable through a
    /// proxy that isn't wired up until after the first layout pass, so the system instead emits at a
    /// rate it can only sustain for ~10 ms before `emissionLimit` stops it.
    static func system(at position: SIMD2<Double>, across size: SIMD2<Double>, colors: [VortexSystem.Color]) -> VortexSystem {
        let lifespan = 1.4
        return VortexSystem(
            tags: ["strip", "strip", "square", "dot"],
            position: position,
            shape: .box(width: size.x, height: size.y),
            birthRate: 3000,
            emissionLimit: 26,
            lifespan: lifespan,
            // About 100 pt up before it turns over (screen heights per second).
            speed: 0.9,
            speedVariation: 0.5,
            // Straight up, fanned 35° either side.
            angleRange: .degrees(70),
            acceleration: [0, 1.6],
            // Vortex scales damping by the lifespan: this is 5/s of drag.
            dampingFactor: 5 * lifespan,
            angularSpeedVariation: [9, 9, 7],
            colors: .random(colors),
            size: 0.6,
            sizeVariation: 0.3,
            // Shrinks to nothing over its life: the burst dissolves instead of raining down.
            sizeMultiplierAtDeath: 0
        )
    }
}

// MARK: - Ripple

/// A ring that runs out from a mark and fades each time `trigger` changes — the mark landing with a
/// push. Laid behind the mark at its size (`.background { RippleRing(…) }`); invisible at rest.
struct RippleRing<Style: ShapeStyle>: View {
    let style: Style
    let trigger: Int
    var lineWidth: CGFloat = 2.5
    /// How far it runs, as a multiple of the mark's size.
    var reach: CGFloat = 2.1
    /// Held back this long, so it can leave the mark as the mark reaches its full size.
    var delay: Double = 0

    private struct Wave {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        Circle()
            .strokeBorder(style, lineWidth: lineWidth)
            .keyframeAnimator(initialValue: Wave(), trigger: trigger) { ring, wave in
                ring.scaleEffect(wave.scale).opacity(wave.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: max(delay, 0.001))
                    SpringKeyframe(reach, duration: 0.45, spring: .smooth(duration: 0.45))
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(0, duration: max(delay, 0.001))
                    MoveKeyframe(0.9)
                    // Gone by the time it is out: a ring that stops and then fades reads as a circle
                    // left behind, not as a wave.
                    LinearKeyframe(0, duration: 0.32)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Haptics

/// The feel of the confetti: a soft lead-in and a firm pop 70 ms apart as the burst leaves, a short
/// fading fizz while it spreads, and three light sparkles as the pieces turn over at the top of their
/// arc. Played through Core Haptics, because no system feedback type says "celebration" — `.success`
/// already means "saved" when End Workout fires it a moment later, and one pattern shouldn't mean two
/// things. Falls back to `.success` where Core Haptics isn't available.
@MainActor
final class CelebrationHaptics {
    static let shared = CelebrationHaptics()

    private var engine: CHHapticEngine?

    private init() {}

    func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        do {
            let engine = try preparedEngine()
            try engine.start()
            let player = try engine.makePlayer(with: Self.pattern())
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func preparedEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let engine = try CHHapticEngine()
        // Stops itself once the pattern has played, and comes back on the next `start()`.
        engine.isAutoShutdownEnabled = true
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        self.engine = engine
        return engine
    }

    private static func pattern() throws -> CHHapticPattern {
        func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time
            )
        }
        func rumble(_ time: TimeInterval, duration: TimeInterval, intensity: Float) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12),
                ],
                relativeTime: time,
                duration: duration
            )
        }
        return try CHHapticPattern(
            events: [
                transient(0, intensity: 0.5, sharpness: 0.3),
                transient(0.07, intensity: 1, sharpness: 0.55),
                // The fizz, stepped down rather than curved: parameter curves apply to everything
                // playing at the time, and would dim the sparkles too.
                rumble(0.09, duration: 0.1, intensity: 0.34),
                rumble(0.19, duration: 0.1, intensity: 0.22),
                rumble(0.29, duration: 0.1, intensity: 0.12),
                transient(0.26, intensity: 0.34, sharpness: 0.9),
                transient(0.38, intensity: 0.26, sharpness: 0.9),
                transient(0.53, intensity: 0.18, sharpness: 0.9),
            ],
            parameters: []
        )
    }
}
