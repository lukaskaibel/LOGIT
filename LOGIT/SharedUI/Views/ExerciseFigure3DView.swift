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
            FigureMetalView(rig: rig, yaw: rig.yaw + yawOffset, pitch: pitch, playing: !reduceMotion)
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
        ExerciseAnimationLibrary.key(for: exercise).map(ExerciseRig.has(key:)) ?? false
    }
}

// MARK: - Metal view

private struct FigureMetalView: UIViewRepresentable {
    let rig: ExerciseRig
    let yaw: Float
    let pitch: Float
    let playing: Bool

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: ExerciseFigureMetal.shared.device)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.rig = rig
        renderer.yaw = yaw
        renderer.pitch = pitch
        renderer.playing = playing
        view.isPaused = !playing
        view.enableSetNeedsDisplay = !playing
        if !playing {
            view.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> ExerciseFigureRenderer {
        ExerciseFigureRenderer(rig: rig)
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
    var yaw: Float = 0
    var pitch: Float = 0
    var playing = true
    private let start = CACurrentMediaTime()

    private struct Uniforms {
        var origin: SIMD2<Float>
        var scale: Float
        var primCount: UInt32
    }

    init(rig: ExerciseRig) {
        self.rig = rig
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let metal = ExerciseFigureMetal.shared
        guard let device = metal.device, let queue = metal.queue, let pipeline = metal.pipeline,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable else { return }
        let time = playing ? CACurrentMediaTime() - start : 0
        let camera = FigureCamera(yaw: yaw, pitch: pitch)
        let frame = FigureScene.build(rig: rig, pose: rig.pose(at: time), camera: camera)

        // the same scale at every angle: everything the exercise sweeps through stays in frame
        let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let center = (rig.boundsMin + rig.boundsMax) / 2
        let half = (rig.boundsMax - rig.boundsMin) / 2
        let radius = (half.x * half.x + half.z * half.z).squareRoot()
        let ph = abs(pitch) * .pi / 180
        let halfHeight = half.y * cos(ph) + radius * sin(ph)
        let scale = min(size.x / (2 * radius * 1.04), size.y / (2 * halfHeight * 1.06))
        let c2 = camera.p(center)
        var uniforms = Uniforms(origin: SIMD2(size.x / 2 - c2.x * scale, size.y / 2 + c2.y * scale), scale: scale,
                                primCount: UInt32(frame.prims.count))

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setFragmentBuffer(Self.buffer(frame.prims, device: device), offset: 0, index: 1)
        enc.setFragmentBuffer(Self.buffer(frame.verts, device: device), offset: 0, index: 2)
        enc.setFragmentBuffer(Self.buffer(frame.overlays, device: device), offset: 0, index: 3)
        enc.setFragmentBuffer(Self.buffer(frame.aux, device: device), offset: 0, index: 4)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private static func buffer<T>(_ array: [T], device: MTLDevice) -> MTLBuffer? {
        array.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else {
                return device.makeBuffer(length: 16, options: .storageModeShared)
            }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }
}
