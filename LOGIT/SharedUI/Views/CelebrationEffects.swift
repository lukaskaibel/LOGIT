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

/// One burst of confetti to fire: where from, in what colours, how big.
struct ConfettiBurst: Identifiable, Equatable {
    let id: Int
    /// Global coordinates. Nil fires from the top third of the screen.
    let origin: CGPoint?
    let colors: [Color]
    /// 1 is the full-screen fountain; the finish panel's per-record pops run at about a third.
    var scale: Double = 1
}

/// Bursts of confetti fired from points on screen and left to fall out of the bottom of it.
///
/// **Earned, never routine.** The finish panel fires one from each personal record's pill, in that
/// exercise's colour, as its number climbs — not for every finished workout, and not for the week.
/// A reward that arrives every time stops meaning anything, and one that arrives for something real
/// keeps meaning it.
///
/// **Physics.** A burst is a fountain, not a rain: pieces leave the thing they celebrate, fan out
/// above it and drift down through everything below. Tuned offline against Vortex's own integration
/// (at full scale ~97% of pieces stay on screen and the last leave the bottom edge after about
/// 3.5 s): a stiff launch, heavy air drag, so the pieces stop rising quickly and then fall at a slow,
/// fluttering terminal speed instead of accelerating like stones. Smaller bursts launch slower and
/// with fewer pieces, so a record's pop stays around its own tile.
///
/// **Only while it's falling.** Vortex draws with a `TimelineView` that ticks as long as it is in the
/// tree, particles or not, so each burst lives in its own view that is removed once its pieces are
/// gone — no idle 120 Hz timeline behind the rest of the session.
struct CelebrationConfetti: View {
    /// Every burst fired so far; new ones are mounted as they are appended.
    let bursts: [ConfettiBurst]

    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mounted: [Mounted] = []
    @State private var seen: Set<Int> = []

    /// How long a burst stays mounted: the system's lifespan plus a little, so nothing is cut off.
    static let burstDuration: Duration = .seconds(5.2)

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
                    let point = burst.origin ?? CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.3)
                    let unit = SIMD2(
                        Double((point.x - frame.minX) / max(frame.width, 1)),
                        Double((point.y - frame.minY) / max(frame.height, 1))
                    )
                    mounted.append(Mounted(
                        id: burst.id,
                        system: Self.system(at: unit, colors: resolve(burst.colors), scale: burst.scale)
                    ))
                    let id = burst.id
                    Task { @MainActor in
                        try? await Task.sleep(for: Self.burstDuration)
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

    /// One burst, emitted over its first few frames: Vortex's `burst()` is only reachable through a
    /// proxy that isn't wired up until after the first layout pass, so the system instead emits at a
    /// rate it can only sustain for ~50 ms before `emissionLimit` stops it — which also reads more
    /// like a real cannon than every piece leaving in the same frame.
    static func system(at position: SIMD2<Double>, colors: [VortexSystem.Color], scale: Double = 1) -> VortexSystem {
        // A small burst lives shorter: it has less height to fall through before it is out of the way.
        let lifespan = 2.6 + 2.4 * scale
        return VortexSystem(
            tags: ["strip", "strip", "square", "dot"],
            position: position,
            // A puff rather than a point: born on one spot, the first frames drew a solid blob. A
            // small burst keeps a floor on its spawn width for the same reason — a pill is wider
            // than a third of the big burst's box.
            shape: .box(width: max(0.14 * scale, 0.1), height: max(0.04 * scale, 0.02)),
            birthRate: 3200,
            emissionLimit: max(Int(170 * scale), 24),
            lifespan: lifespan,
            // Launch speed falls with the square root of the scale, so a third-size burst still
            // rises about a third of the way — height goes with speed squared.
            speed: 1.3 * scale.squareRoot(),
            speedVariation: 0.7 * scale.squareRoot(),
            // Straight up, fanned 50° either side.
            angleRange: .degrees(100),
            // Gravity, in screen heights per second squared.
            acceleration: [0, 1.2],
            // Vortex scales damping by the lifespan: this is 3.8/s of drag, which caps the fall at
            // ~0.32 screen heights per second — a drift, not a drop.
            dampingFactor: 3.8 * lifespan,
            angularSpeedVariation: [9, 9, 7],
            colors: .random(colors),
            size: 0.9 * (0.75 + 0.25 * scale),
            sizeVariation: 0.5
        )
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
