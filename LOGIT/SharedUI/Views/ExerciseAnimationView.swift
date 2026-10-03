//
//  ExerciseAnimationView.swift
//  LOGIT
//

import AVFoundation
import SwiftUI

/// The looping demonstration of a built-in exercise: the app's minimalist figure performing it,
/// with the working muscles highlighted. The clips are rendered offline by
/// `Tools/ExerciseAnimations` as transparent HEVC loops cropped tight to the figure, one per
/// exercise (`<key>.mov`, 288 px). They show at 96 pt beside the detail screen's title and 48 pt
/// in the exercise cells, whole-number scales on a 3x screen.
///
/// An exercise without a clip (a custom one) renders nothing, so call sites can place the view
/// unconditionally. A clip plays only while it is on screen, and Reduce Motion holds its first
/// frame instead of looping.
struct ExerciseAnimationView: View {
    let exercise: Exercise?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOnScreen = false

    var body: some View {
        if let url = ExerciseAnimationLibrary.url(for: exercise) {
            LoopingVideo(url: isOnScreen ? url : nil, isPlaying: !reduceMotion)
                .aspectRatio(1, contentMode: .fit)
                .onScrollVisibilityChange(threshold: 0.01) { isOnScreen = $0 }
                .accessibilityHidden(true)
        }
    }
}

/// The looping figure left of an exercise's name in the exercise cells. It stands bare on the
/// cell, a little taller than the name and muscle group together, inside the cell's own padding.
/// Collapses when the exercise has no clip.
struct ExerciseAnimationIcon: View {
    let exercise: Exercise?

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 48

    var body: some View {
        if ExerciseAnimationLibrary.hasAnimation(for: exercise) {
            ExerciseAnimationView(exercise: exercise)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Clip lookup

enum ExerciseAnimationLibrary {
    private static let defaultPrefix = "_default.exercise."
    private static let directory = Bundle.main.url(forResource: "ExerciseAnimations", withExtension: nil)
    /// The folder is listed once, so a lookup is a set check rather than a bundle search on every
    /// render of a cell.
    private static let clips: Set<String> = {
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(names)
    }()

    static func url(for exercise: Exercise?) -> URL? {
        guard let key = key(for: exercise), let directory else { return nil }
        let file = "\(key).mov"
        return clips.contains(file) ? directory.appendingPathComponent(file) : nil
    }

    static func hasAnimation(for exercise: Exercise?) -> Bool {
        url(for: exercise) != nil
    }

    /// The library key of the exercise's clip: a built-in exercise's name is its key behind the
    /// `_default.exercise.` prefix.
    static func key(for exercise: Exercise?) -> String? {
        guard let name = exercise?.name else { return nil }
        if name.hasPrefix(defaultPrefix) {
            let key = String(name.dropFirst(defaultPrefix.count))
            return keyAliases[key] ?? key
        }
        return previewAliases[name]
    }

    /// Keys the test scenarios use that aren't library keys.
    private static let keyAliases = [
        "overheadPress": "militaryPress",
        "inclineBenchPress": "inclinedBarbellBenchPress",
        "tricepsExtensions": "overheadTricepExtension",
        "bicepsCurls": "dumbbellCurls",
    ]

    /// The preview dataset names its exercises with display strings rather than library keys.
    private static let previewAliases: [String: String] = Dictionary(
        [
            ("previewBenchPress", "barbellBenchPress"),
            ("previewInclineBenchPress", "inclinedBarbellBenchPress"),
            ("previewOverheadPress", "militaryPress"),
            ("previewLateralRaises", "lateralRaises"),
            ("previewTricepsExtensions", "overheadTricepExtension"),
            ("previewDips", "dips"),
            ("previewSquat", "squats"),
            ("previewSquats", "squats"),
            ("previewLunges", "dumbbellLunges"),
            ("previewLegExtensions", "legExtension"),
            ("previewDeadlift", "deadlift"),
            ("previewStandingRows", "barbellRows"),
            ("previewBicepsCurls", "dumbbellCurls"),
            ("previewBarbellCurl", "barbellCurls"),
            ("previewLatPulldown", "latPulldowns"),
            ("previewCrunches", "crunches"),
            ("previewPushup", "pushups"),
        ].map { (NSLocalizedString($0.0, comment: ""), $0.1) },
        uniquingKeysWith: { first, _ in first }
    )
}

// MARK: - Player

private struct LoopingVideo: UIViewRepresentable {
    /// Nil unloads the clip (off screen), freeing its decoder.
    let url: URL?
    let isPlaying: Bool

    func makeUIView(context: Context) -> LoopingVideoView {
        LoopingVideoView()
    }

    func updateUIView(_ view: LoopingVideoView, context: Context) {
        view.show(url, playing: isPlaying)
    }

    static func dismantleUIView(_ view: LoopingVideoView, coordinator: ()) {
        view.show(nil, playing: false)
    }
}

final class LoopingVideoView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var url: URL?
    private var wantsPlaying = false

    /// The clips are silent, but a playing AVPlayer still activates the app's audio session; under
    /// the default solo-ambient category that would stop whatever music the user trains to.
    private static let mixWithOthers: Void = {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        _ = Self.mixWithOthers
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.videoGravity = .resizeAspect
        // HEVC-with-alpha composites only when the layer asks for a pixel format that has alpha.
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        playerLayer.player = player
        // Backgrounding pauses video playback; pick the loop back up on return.
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyPlayback),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ url: URL?, playing: Bool) {
        wantsPlaying = playing
        if url != self.url {
            self.url = url
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
            if let url {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
        }
        applyPlayback()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPlayback()
    }

    @objc private func applyPlayback() {
        if wantsPlaying, url != nil, window != nil {
            player.play()
        } else {
            player.pause()
        }
    }
}
