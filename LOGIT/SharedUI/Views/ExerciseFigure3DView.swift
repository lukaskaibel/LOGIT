//
//  ExerciseFigure3DView.swift
//  LOGIT
//

import MetalKit
import SwiftUI

/// A built-in exercise performed by the app's figure in 3D, drawn live with Metal from the
/// exercise's baked rig (`ExerciseRig`). Drag to turn the camera round the figure (and tilt it a
/// little); double-tap to go back to the angle the exercise was designed for. Renders nothing for
/// an exercise without a rig, so call sites can place it unconditionally.
struct ExerciseFigure3DView: View {
    let exercise: Exercise?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var yawOffset: Float = 0
    @State private var pitch: Float = 8
    @State private var dragStart: (yaw: Float, pitch: Float)?

    var body: some View {
        if let key = ExerciseAnimationLibrary.key(for: exercise), let rig = ExerciseRig.named(key) {
            FigureMetalView(rig: rig, framing: .orbit(yaw: rig.yaw + yawOffset, pitch: pitch), playing: !reduceMotion)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = dragStart ?? (yawOffset, pitch)
                            dragStart = start
                            yawOffset = start.yaw + Float(value.translation.width) * 0.45
                            pitch = min(max(start.pitch + Float(value.translation.height) * 0.25, -5), 60)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.smooth) {
                        yawOffset = 0
                        pitch = 8
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(exercise?.displayName ?? ""))
                .accessibilityIdentifier("exerciseFigure3D")
        }
    }

    static func has(_ exercise: Exercise?) -> Bool {
        ExerciseAnimationLibrary.hasAnimation(for: exercise)
    }
}

// MARK: - Metal view

/// How a figure is framed.
enum FigureFraming: Equatable {
    /// Turnable: the camera at any angle, the scale fixed so everything the exercise sweeps through
    /// stays in frame from every side; with the floor, at 60 fps.
    case orbit(yaw: Float, pitch: Float)
    /// The small looping figure: the exercise's own camera, cropped tight to the figure the way the
    /// offline clips were (its 2D content box); no floor, 30 fps.
    case icon
}

struct FigureMetalView: UIViewRepresentable {
    let rig: ExerciseRig
    let framing: FigureFraming
    let playing: Bool

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: ExerciseFigureMetal.shared.device)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.rig = rig
        renderer.framing = framing
        renderer.playing = playing
        view.preferredFramesPerSecond = framing == .icon ? 30 : 60
        view.isPaused = !playing
        view.enableSetNeedsDisplay = !playing
        if !playing {
            view.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> ExerciseFigureRenderer {
        ExerciseFigureRenderer(rig: rig, framing: framing)
    }
}

// MARK: - Renderer

/// The device, queue and pipeline, made once. The shader is compiled from source on first use.
final class ExerciseFigureMetal {
    static let shared = ExerciseFigureMetal()

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    let pipeline: MTLRenderPipelineState?

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        guard let device, let library = try? device.makeLibrary(source: ExerciseFigureShaders.source, options: nil)
        else {
            pipeline = nil
            return
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "figure_vertex")
        desc.fragmentFunction = library.makeFunction(name: "figure_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}

final class ExerciseFigureRenderer: NSObject, MTKViewDelegate {
    var rig: ExerciseRig
    var framing: FigureFraming
    var playing = true
    private let start = CACurrentMediaTime()

    /// A screen of exercise cells draws a dozen of these at once, so a frame's data goes into
    /// buffers reused round a small ring rather than into new ones; a frame whose slot is still
    /// with the GPU is skipped rather than waited for.
    private static let slotCount = 3
    private var slots: [[MTLBuffer?]] = Array(repeating: Array(repeating: nil, count: 4), count: slotCount)
    private var slot = 0
    private let inFlight = DispatchSemaphore(value: slotCount)

    private struct Uniforms {
        var origin: SIMD2<Float>
        var scale: Float
        var primCount: UInt32
    }

    init(rig: ExerciseRig, framing: FigureFraming) {
        self.rig = rig
        self.framing = framing
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let metal = ExerciseFigureMetal.shared
        guard let device = metal.device, let queue = metal.queue, let pipeline = metal.pipeline,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let time = playing ? CACurrentMediaTime() - start : 0
        let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let camera: FigureCamera
        let origin: SIMD2<Float>
        let scale: Float
        switch framing {
        case let .orbit(yaw, pitch):
            // the same scale at every angle: everything the exercise sweeps through stays in frame
            camera = FigureCamera(yaw: yaw, pitch: pitch)
            let center = (rig.boundsMin + rig.boundsMax) / 2
            let half = (rig.boundsMax - rig.boundsMin) / 2
            let radius = (half.x * half.x + half.z * half.z).squareRoot()
            let ph = abs(pitch) * .pi / 180
            let halfHeight = half.y * cos(ph) + radius * sin(ph)
            scale = min(size.x / (2 * radius * 1.04), size.y / (2 * halfHeight * 1.06))
            let c2 = camera.p(center)
            origin = SIMD2(size.x / 2 - c2.x * scale, size.y / 2 + c2.y * scale)
        case .icon:
            // Exercise.canvas_for(mode='icon') in Tools/ExerciseAnimations: the content box, its
            // sides pulled in 2 cm, fitted with 6% to spare
            camera = FigureCamera(yaw: rig.yaw, pitch: rig.pitch)
            let box = rig.contentBox
            let x0 = box.x + 2, x1 = box.z - 2
            let side = max(x1 - x0, box.w - box.y) * 1.06
            scale = min(size.x, size.y) / max(side, 1)
            origin = SIMD2(size.x / 2 - (x0 + x1) / 2 * scale, size.y / 2 + (box.y + box.w) / 2 * scale)
        }
        let frame = FigureScene.build(rig: rig, pose: rig.pose(at: time), camera: camera, floor: framing != .icon)
        var uniforms = Uniforms(origin: origin, scale: scale, primCount: UInt32(frame.prims.count))

        let buffers = [fill(0, frame.prims, device), fill(1, frame.verts, device),
                       fill(2, frame.overlays, device), fill(3, frame.aux, device)]
        slot = (slot + 1) % Self.slotCount
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        for (i, buffer) in buffers.enumerated() {
            enc.setFragmentBuffer(buffer, offset: 0, index: i + 1)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        let semaphore = inFlight
        cmd.addCompletedHandler { _ in semaphore.signal() }
        cmd.present(drawable)
        cmd.commit()
    }

    /// The current slot's buffer `index`, grown when the frame needs more room, holding `array`.
    private func fill<T>(_ index: Int, _ array: [T], _ device: MTLDevice) -> MTLBuffer? {
        array.withUnsafeBytes { raw in
            let length = max(raw.count, 16)
            if (slots[slot][index]?.length ?? 0) < length {
                slots[slot][index] = device.makeBuffer(length: max(length, 2 * (slots[slot][index]?.length ?? 0)),
                                                       options: .storageModeShared)
            }
            guard let buffer = slots[slot][index] else { return nil }
            if let base = raw.baseAddress, raw.count > 0 {
                buffer.contents().copyMemory(from: base, byteCount: raw.count)
            }
            return buffer
        }
    }
}
