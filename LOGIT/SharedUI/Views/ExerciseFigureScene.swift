//
//  ExerciseFigureScene.swift
//  LOGIT
//

import Foundation
import simd

// The figure and its equipment for one frame and one camera, as 2D primitives with a depth model
// each, ready for ExerciseFigureShaders.metal to composite per pixel. A port of
// Tools/ExerciseAnimations/logitanim/view3d.py (and the muscle regions of anatomy.py): change
// the two together.

/// An orthographic camera turned `yaw` degrees around the vertical from side-on (90: from the
/// front, -90: from behind) and raised `pitch` degrees above the horizon.
struct FigureCamera {
    let yaw: Float
    let pitch: Float
    /// Screen right, screen up, and towards the camera (depth grows with it).
    let r: SIMD3<Float>
    let u: SIMD3<Float>
    let v: SIMD3<Float>

    init(yaw: Float, pitch: Float) {
        self.yaw = yaw
        self.pitch = pitch
        let th = yaw * .pi / 180, ph = pitch * .pi / 180
        v = SIMD3(sin(th) * cos(ph), sin(ph), cos(th) * cos(ph))
        r = SIMD3(cos(th), 0, -sin(th))
        u = simd_cross(v, r)
    }

    func p(_ x: SIMD3<Float>) -> SIMD2<Float> { SIMD2(simd_dot(r, x), simd_dot(u, x)) }
    func depth(_ x: SIMD3<Float>) -> Float { simd_dot(v, x) }
    func lift(_ e: SIMD2<Float>) -> SIMD3<Float> { r * e.x + u * e.y }
    func toCamera(_ x: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simd_dot(r, x), simd_dot(u, x), simd_dot(v, x)) }
}

/// One primitive as the shader reads it (layout shared with ExerciseFigureShaders.metal).
struct FigurePrim {
    /// Shape bounds on the screen plane (x0, y0, x1, y1), before the knockout band.
    var bbox = SIMD4<Float>.zero
    /// kind, group, first overlay, overlay count.
    var info = SIMD4<UInt32>.zero
    /// rgb and the knockout band's width.
    var color = SIMD4<Float>.zero
    var p0 = SIMD4<Float>.zero
    var p1 = SIMD4<Float>.zero
    var p2 = SIMD4<Float>.zero
    var p3 = SIMD4<Float>.zero
    var p4 = SIMD4<Float>.zero
    /// Points near which the band fades away (x, y, r0, r1; r1 = 0: none).
    var a0 = SIMD4<Float>.zero
    var a1 = SIMD4<Float>.zero
    var range = SIMD4<UInt32>.zero

    enum Kind: UInt32 {
        case cone = 0, circle, cylinder, box, torso, floorBox, floorEllipse
    }
}

/// A muscle region painted on a primitive (layout shared with the shader).
struct FigureOverlay {
    /// kind (0 ellipse, 1 polygon), first vertex, vertex count.
    var info = SIMD4<UInt32>.zero
    /// ellipse: cx, cy, rx, ry; polygon: rounding.
    var g0 = SIMD4<Float>.zero
    /// ellipse: angle.
    var g1 = SIMD4<Float>.zero
    var color = SIMD4<Float>.zero
}

struct FigureFrame {
    var prims: [FigurePrim] = []
    var overlays: [FigureOverlay] = []
    var verts: [SIMD2<Float>] = []
    var aux: [SIMD4<Float>] = []
}

enum FigureScene {
    // spec.py
    static let rThigh: (Float, Float) = (9.0, 6.9)
    static let rShank: (Float, Float) = (6.9, 4.9)
    static let rThighFront: (Float, Float) = (7.9, 6.5)
    static let rShankFront: (Float, Float) = (6.5, 5.1)
    static let rUpper: (Float, Float) = (6.1, 5.2)
    static let rFore: (Float, Float) = (5.2, 4.3)
    static let rHand: Float = 4.9
    static let rHeel: Float = 4.1
    static let rToe: Float = 3.0
    static let rHead: Float = 12.5
    static let gap: Float = 1.6
    static let torsoLength: Float = 49.0

    /// view3d.TORSO_SECTIONS: height along the spine, forward offset, outer half-width, outer
    /// half-depth (cm).
    static let torsoSections: [(h: Float, c: Float, a: Float, s: Float)] = [
        (51.0, 1.2, 13.0, 9.0), (47.0, 1.2, 19.6, 11.8), (41.8, 1.2, 19.15, 12.9), (33.0, 1.2, 18.4, 12.26),
        (24.0, 1.2, 17.6, 11.6), (15.0, 0.79, 16.8, 11.91), (6.5, 0.4, 16.05, 12.2), (1.0, -1.05, 15.6, 12.35),
        (-5.5, -4.3, 15.0, 6.9), (-8.0, -2.6, 13.0, 5.97),
    ]
    static let torsoRound: Float = 3.0
    static let torsoDepthScale: Float = 0.5

    /// `floor: false` leaves out the floor line, as the small looping figure has none.
    static func build(rig: ExerciseRig, pose: ExerciseRig.Pose, camera cam: FigureCamera,
                      muscles: Bool = true, floor showsFloor: Bool = true) -> FigureFrame {
        var out = FigureFrame()
        let fig = rig.palette["fig"] ?? SIMD3(0.96, 0.96, 0.97)
        let pelvis = pose.joint("pelvis")
        let tf = (f: pose.vector("torsoF"), u: pose.vector("torsoU"), r: pose.vector("torsoR"))
        let pfR = pose.vector("pelvisR")

        // the torso and the head
        out.prims.append(torso(pose: pose, pelvis: pelvis, tf: tf, cam: cam, color: fig, out: &out))
        let head = pose.joint("head")
        out.prims.append(circlePrim(head, rHead, cam: cam, color: fig, gap: gap, group: 1))

        var owner: [String: Int] = ["torso": 0, "hips": 0]
        for (i, s) in ["L", "R"].enumerated() {
            let sg: Float = s == "L" ? -1 : 1
            func j(_ name: String) -> SIMD3<Float> { pose.joint(name + s) }
            let lat = pfR * sg
            let legGroup = UInt32(2 + 2 * i), armGroup = UInt32(6 + 2 * i)

            owner["leg" + s] = out.prims.count
            var thigh = limbPrim(j("hip"), j("knee"), rThigh.0, rThigh.1, cam: cam, lat: lat,
                                 raLat: rThighFront.0, rbLat: rThighFront.1)
            thigh.color = SIMD4(fig, gap)
            thigh.info.y = legGroup
            thigh.a0 = SIMD4(cam.p(j("hip")), 10.5, 15.0)
            thigh.a1 = SIMD4(cam.p(j("knee")), 8.0, 13.0)
            out.prims.append(thigh)

            owner["shin" + s] = out.prims.count
            var shank = limbPrim(j("knee"), j("ankle"), rShank.0, rShank.1, cam: cam, lat: lat,
                                 raLat: rShankFront.0, rbLat: rShankFront.1)
            shank.color = SIMD4(fig, gap)
            shank.info.y = legGroup + 1
            shank.a0 = SIMD4(cam.p(j("knee")), 8.0, 13.0)
            out.prims.append(shank)
            var foot = limbPrim(j("heel"), j("toe"), rHeel, rToe, cam: cam)
            foot.color = SIMD4(fig, gap)
            foot.info.y = legGroup + 1
            out.prims.append(foot)

            owner["arm" + s] = out.prims.count
            var upper = limbPrim(j("shoulder"), j("elbow"), rUpper.0, rUpper.1, cam: cam)
            upper.color = SIMD4(fig, gap)
            upper.info.y = armGroup
            upper.a0 = SIMD4(cam.p(j("shoulder")), 7.5, 12.0)
            upper.a1 = SIMD4(cam.p(j("elbow")), 6.0, 11.0)
            out.prims.append(upper)

            let hand = j("hand")
            let style = i == 0 ? rig.hands.left : rig.hands.right
            owner["fore" + s] = out.prims.count
            var fore: FigurePrim
            var handPrims: [FigurePrim] = []
            switch style {
            case .palm:
                fore = limbPrim(j("elbow"), hand, rFore.0, 4.0, cam: cam)
                let pd = pose.vector("palm" + s)
                let ha = hand - SIMD3(0, 1.3, 0) + pd * 0.6, hb = hand - SIMD3(0, 2.3, 0) + pd * 9.6
                handPrims.append(limbPrim(ha, hb, 3.1, 2.1, cam: cam))
            case .wrist:
                let wr = j("wrist")
                fore = limbPrim(j("elbow"), wr, rFore.0, rFore.1, cam: cam)
                handPrims.append(limbPrim(wr, hand, rFore.1, rHand - 0.4, cam: cam))
                handPrims.append(circlePrim(hand, rHand - 0.4, cam: cam, color: fig, gap: gap, group: 0))
            case .fist:
                fore = limbPrim(j("elbow"), hand, rFore.0, rFore.1, cam: cam)
                handPrims.append(circlePrim(hand, rHand, cam: cam, color: fig, gap: gap, group: 0))
            }
            fore.color = SIMD4(fig, gap)
            fore.info.y = armGroup + 1
            fore.a0 = SIMD4(cam.p(j("elbow")), 6.0, 11.0)
            out.prims.append(fore)
            for var h in handPrims {
                h.color = SIMD4(fig, gap)
                h.info.y = armGroup + 1
                out.prims.append(h)
            }
        }

        // muscle regions, painted on the primitive of the part that owns them
        if muscles {
            var byOwner: [Int: [FigureOverlay]] = [:]
            for region in FigureAnatomy.regions(pose: pose, names: rig.muscles) {
                guard let index = owner[region.part],
                      let overlay = project(region, cam: cam, color: rig.muscleColor, verts: &out.verts)
                else { continue }
                byOwner[index, default: []].append(overlay)
            }
            for (index, list) in byOwner.sorted(by: { $0.key < $1.key }) {
                out.prims[index].info.z = UInt32(out.overlays.count)
                out.prims[index].info.w = UInt32(list.count)
                out.overlays += list
            }
        }

        // equipment
        for e in rig.equipment {
            let color = e.color
            let g: Float = e.mode == .band ? gap : 0
            let group = UInt32(11 + e.group)
            let o = e.offset
            var prim: FigurePrim
            switch e.kind {
            case .cyl:
                prim = cylinderPrim(pose.vec3(o), simd_normalize(pose.vec3(o + 3)), pose.scalar(o + 6),
                                    pose.scalar(o + 7), cam: cam)
            case .cap:
                let r = pose.scalar(o + 6)
                prim = limbPrim(pose.vec3(o), pose.vec3(o + 3), r, r, cam: cam)
            case .cone:
                prim = limbPrim(pose.vec3(o), pose.vec3(o + 3), pose.scalar(o + 6), pose.scalar(o + 7), cam: cam)
            case .sph:
                prim = circlePrim(pose.vec3(o), pose.scalar(o + 3), cam: cam, color: color, gap: g, group: group)
            case .box:
                prim = boxPrim(pose.vec3(o), [pose.vec3(o + 3), pose.vec3(o + 6), pose.vec3(o + 9)],
                               SIMD3(pose.scalar(o + 12), pose.scalar(o + 13), pose.scalar(o + 14)),
                               pose.scalar(o + 15), cam: cam, verts: &out.verts)
            }
            prim.color = SIMD4(color, g)
            prim.info.y = group
            if e.mode == .backdrop {
                prim.range.w = 1        // the shader puts it behind every other part
            }
            out.prims.append(prim)
        }

        // the floor: a thin disc, a line side-on and an ellipse from above
        if showsFloor, let floor = rig.floor {
            var prim = FigurePrim()
            let c = cam.p(floor.center)
            let s = abs(sin(cam.pitch * .pi / 180))
            if s > 0.02 {
                let ry = max(floor.radius * s, 0.85)
                prim.info = SIMD4(FigurePrim.Kind.floorEllipse.rawValue, 10, 0, 0)
                prim.p0 = SIMD4(c, floor.radius, ry)
                prim.bbox = SIMD4(c.x - floor.radius, c.y - ry, c.x + floor.radius, c.y + ry)
            } else {
                prim.info = SIMD4(FigurePrim.Kind.floorBox.rawValue, 10, 0, 0)
                prim.p0 = SIMD4(c, floor.radius, 0.85)
                prim.p1 = SIMD4(0.85, 0, 0, 0)
                prim.bbox = SIMD4(c.x - floor.radius, c.y - 0.85, c.x + floor.radius, c.y + 0.85)
            }
            prim.color = SIMD4(rig.palette["floor"] ?? SIMD3(0.17, 0.17, 0.18), 0)
            out.prims.append(prim)
        }
        return out
    }

    // MARK: Primitives

    /// A round cone from a to b (view3d.limb). With `lat` and lateral radii its cross-section is
    /// an ellipse, so a leg reads slimmer from the front than side-on.
    static func limbPrim(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ ra: Float, _ rb: Float, cam: FigureCamera,
                         lat: SIMD3<Float>? = nil, raLat: Float = 0, rbLat: Float = 0) -> FigurePrim {
        let a2 = cam.p(a), b2 = cam.p(b)
        var raS = ra, rbS = rb, raV = ra, rbV = rb
        if let lat {
            let axis = normalized(b - a, fallback: SIMD3(0, 1, 0))
            let l = normalized(lat - simd_dot(lat, axis) * axis, fallback: SIMD3(1, 0, 0))
            let sag = normalized(simd_cross(axis, l), fallback: SIMD3(0, 0, 1))
            let d2 = b2 - a2
            let len = simd_length(d2)
            let e2 = len > 1e-3 ? SIMD2(-d2.y, d2.x) / len : SIMD2<Float>(1, 0)
            var e3 = cam.lift(e2)
            e3 -= simd_dot(e3, axis) * axis
            e3 = simd_length(e3) > 1e-6 ? simd_normalize(e3) : l
            var vc = cam.v - simd_dot(cam.v, axis) * axis
            vc = simd_length(vc) > 1e-6 ? simd_normalize(vc) : sag
            raS = support(raLat, ra, l, sag, e3)
            rbS = support(rbLat, rb, l, sag, e3)
            raV = support(raLat, ra, l, sag, vc)
            rbV = support(rbLat, rb, l, sag, vc)
        }
        var prim = FigurePrim()
        prim.info.x = FigurePrim.Kind.cone.rawValue
        prim.p0 = SIMD4(a2, b2)
        prim.p1 = SIMD4(raS, rbS, 0, 0)
        prim.p2 = SIMD4(cam.depth(a), cam.depth(b), raV, rbV)
        prim.bbox = SIMD4(min(a2.x - raS, b2.x - rbS), min(a2.y - raS, b2.y - rbS),
                          max(a2.x + raS, b2.x + rbS), max(a2.y + raS, b2.y + rbS))
        return prim
    }

    static func circlePrim(_ c: SIMD3<Float>, _ r: Float, cam: FigureCamera, color: SIMD3<Float>, gap: Float,
                           group: UInt32) -> FigurePrim {
        let c2 = cam.p(c)
        var prim = FigurePrim()
        prim.info = SIMD4(FigurePrim.Kind.circle.rawValue, group, 0, 0)
        prim.color = SIMD4(color, gap)
        prim.p0 = SIMD4(c2, r, 0)
        prim.p2 = SIMD4(cam.depth(c), r, 0, 0)
        prim.bbox = SIMD4(c2.x - r, c2.y - r, c2.x + r, c2.y + r)
        return prim
    }

    /// A capped cylinder: its silhouette as equipment.py's cyl() draws it, its depth by an exact ray
    /// test in camera space.
    static func cylinderPrim(_ c: SIMD3<Float>, _ axis: SIMD3<Float>, _ radius: Float, _ half: Float,
                             cam: FigureCamera) -> FigurePrim {
        let a = cam.p(axis)
        let s = simd_length(a)
        let ad = sqrt(max(0, 1 - min(s, 1) * min(s, 1)))
        let along = half * s + radius * ad
        let angle = s > 1e-3 ? atan2(a.y, a.x) : 0
        let corner = min(radius, max(along, 0.01), radius * ad + min(radius, 1.6))
        let hx = s < 1e-3 ? max(along, radius * 0.999) : along
        let c2 = cam.p(c)
        var prim = FigurePrim()
        prim.info.x = FigurePrim.Kind.cylinder.rawValue
        prim.p0 = SIMD4(c2, hx, radius)
        prim.p1 = SIMD4(corner, angle, 0, 0)
        prim.p2 = SIMD4(cam.toCamera(c), radius)
        prim.p3 = SIMD4(cam.toCamera(axis), half)
        prim.p4 = SIMD4(cam.depth(c) + abs(simd_dot(cam.v, axis)) * half, 0, 0, 0)
        let ca = abs(cos(angle)), sa = abs(sin(angle))
        let ex = ca * hx + sa * radius, ey = sa * hx + ca * radius
        prim.bbox = SIMD4(c2.x - ex, c2.y - ey, c2.x + ex, c2.y + ey)
        return prim
    }

    /// A rounded box: its silhouette as the hull of its projected (inset) corners, rounded; its depth
    /// by an exact slab test in camera space.
    static func boxPrim(_ c: SIMD3<Float>, _ axes: [SIMD3<Float>], _ half: SIMD3<Float>, _ rounding: Float,
                        cam: FigureCamera, verts: inout [SIMD2<Float>]) -> FigurePrim {
        let e = axes.map { normalized($0, fallback: SIMD3(1, 0, 0)) }
        var corners: [SIMD2<Float>] = []
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                for sz: Float in [-1, 1] {
                    corners.append(cam.p(c + e[0] * sx * (half.x - rounding) + e[1] * sy * (half.y - rounding)
                                         + e[2] * sz * (half.z - rounding)))
                }
            }
        }
        let hull = convexHull(corners)
        var prim = FigurePrim()
        prim.info.x = FigurePrim.Kind.box.rawValue
        prim.range = SIMD4(UInt32(verts.count), UInt32(hull.count), 0, 0)
        verts += hull
        prim.p1 = SIMD4(rounding, 0, 0, 0)
        let zc = cam.depth(c) + zip(e, [half.x, half.y, half.z]).map { abs(simd_dot(cam.v, $0)) * $1 }.reduce(0, +)
        prim.p2 = SIMD4(cam.toCamera(c), zc)
        prim.p3 = SIMD4(cam.toCamera(e[0]), half.x)
        prim.p4 = SIMD4(cam.toCamera(e[1]), half.y)
        prim.a0 = SIMD4(cam.toCamera(e[2]), half.z)
        prim.bbox = bounds(hull, pad: rounding)
        return prim
    }

    /// The torso: a loft of elliptical sections (each pair's projected hull), the shoulder yoke and
    /// caps, smooth-unioned in the shader; and the section table its depth is read from.
    static func torso(pose: ExerciseRig.Pose, pelvis: SIMD3<Float>, tf: (f: SIMD3<Float>, u: SIMD3<Float>, r: SIMD3<Float>),
                      cam: FigureCamera, color: SIMD3<Float>, out: inout FigureFrame) -> FigurePrim {
        let n = 16
        var rings: [[SIMD2<Float>]] = []
        for sec in torsoSections {
            let a = max(sec.a - torsoRound, 0.5), s = max(sec.s - torsoRound, 0.5)
            let ctr = pelvis + tf.u * sec.h + tf.f * sec.c
            rings.append((0 ..< n).map { k in
                let t = 2 * Float.pi * Float(k) / Float(n)
                return cam.p(ctr + tf.r * (a * cos(t)) + tf.f * (s * sin(t)))
            })
        }
        let hullStart = out.aux.count
        var box = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for k in 0 ..< rings.count - 1 {
            let hull = convexHull(rings[k] + rings[k + 1])
            out.aux.append(SIMD4(Float(out.verts.count), Float(hull.count), 0, 0))
            out.verts += hull
            let b = bounds(hull, pad: torsoRound)
            box = SIMD4(min(box.x, b.x), min(box.y, b.y), max(box.z, b.z), max(box.w, b.w))
        }
        let sl = pose.joint("shoulderL"), sr = pose.joint("shoulderR")
        let inward = normalized(sr - sl, fallback: tf.r)
        let ya = cam.p(sl + inward * 1.5 + tf.u * 0.3), yb = cam.p(sr - inward * 1.5 + tf.u * 0.3)
        let cl = cam.p(sl), cr = cam.p(sr)
        for (p, r) in [(ya, Float(6.8)), (yb, Float(6.8)), (cl, rUpper.0), (cr, rUpper.0)] {
            box = SIMD4(min(box.x, p.x - r), min(box.y, p.y - r), max(box.z, p.x + r), max(box.w, p.y + r))
        }

        // depth: the section at the pixel's height, its centre's depth plus a share of its bulge
        // towards the camera, rounded across the width
        var vc = cam.v - simd_dot(cam.v, tf.u) * tf.u
        vc = simd_length(vc) > 1e-6 ? simd_normalize(vc) : tf.f
        var rc = cam.r - simd_dot(cam.r, tf.u) * tf.u
        rc = simd_length(rc) > 1e-6 ? simd_normalize(rc) : tf.r
        let sectionStart = out.aux.count
        for sec in torsoSections.sorted(by: { $0.h < $1.h }) {
            let ev = support(sec.a, sec.s, tf.r, tf.f, vc)
            let er = support(sec.a, sec.s, tf.r, tf.f, rc)
            out.aux.append(SIMD4(sec.h, sec.c, ev, er))
        }
        let hBottom = torsoSections.last!.h, hTop = torsoSections.first!.h
        let bottom = pelvis + tf.u * hBottom, top = pelvis + tf.u * hTop
        var prim = FigurePrim()
        prim.info = SIMD4(FigurePrim.Kind.torso.rawValue, 0, 0, 0)
        prim.color = SIMD4(color, gap)
        prim.range = SIMD4(UInt32(hullStart), UInt32(rings.count - 1), UInt32(sectionStart), UInt32(torsoSections.count))
        prim.p0 = SIMD4(ya, yb)
        prim.p1 = SIMD4(6.8, rUpper.0, 6.0, torsoRound)
        prim.p2 = SIMD4(cl, cr)
        prim.p3 = SIMD4(cam.p(bottom), cam.p(top))
        let fwd2 = cam.p(tf.f)
        prim.p4 = SIMD4(cam.depth(bottom), cam.depth(top), fwd2.x, fwd2.y)
        prim.a1 = SIMD4(simd_dot(cam.v, tf.f), torsoDepthScale, hBottom, hTop)
        prim.bbox = SIMD4(box.x - 6, box.y - 6, box.z + 6, box.w + 6)
        return prim
    }

    // MARK: Regions

    static func project(_ region: FigureAnatomy.Region, cam: FigureCamera, color: SIMD3<Float>,
                        verts: inout [SIMD2<Float>]) -> FigureOverlay? {
        func visibility(_ n: SIMD3<Float>?) -> Float {
            guard let n else { return 1 }
            let x = min(max((simd_dot(n, cam.v) + 0.55) / 0.4, 0), 1)
            return x * x * (3 - 2 * x)
        }
        switch region.shape {
        case let .ellipsoid(c, axes, radii, normal):
            let vis = visibility(normal)
            guard vis > 0.02 else { return nil }
            var qa: Float = 0, qb: Float = 0, qc: Float = 0
            for i in 0 ..< 3 {
                let m = cam.p(axes[i] * radii[i])
                qa += m.x * m.x
                qb += m.x * m.y
                qc += m.y * m.y
            }
            let mid = (qa + qc) / 2, rad = sqrt(((qa - qc) / 2) * ((qa - qc) / 2) + qb * qb)
            let rx = sqrt(max(mid + rad, 1e-6)) * vis, ry = sqrt(max(mid - rad, 1e-6)) * vis
            let angle = 0.5 * atan2(2 * qb, qa - qc)
            return FigureOverlay(info: SIMD4(0, 0, 0, 0), g0: SIMD4(cam.p(c), max(rx, 0.05), max(ry, 0.05)),
                                 g1: SIMD4(angle, 0, 0, 0), color: SIMD4(color, 1))
        case let .patch(points, normal, rounding):
            let vis = visibility(normal)
            guard vis > 0.02 else { return nil }
            let pts = points.map { cam.p($0) }
            let c = pts.reduce(SIMD2<Float>.zero, +) / Float(pts.count)
            let start = verts.count
            verts += pts.map { c + ($0 - c) * vis }
            return FigureOverlay(info: SIMD4(1, UInt32(start), UInt32(pts.count), 0),
                                 g0: SIMD4(rounding * vis, 0, 0, 0), g1: .zero, color: SIMD4(color, 1))
        }
    }

    // MARK: Helpers

    /// Half-extent along d of an ellipse with semi-axes a (along e1) and b (along e2).
    static func support(_ a: Float, _ b: Float, _ e1: SIMD3<Float>, _ e2: SIMD3<Float>, _ d: SIMD3<Float>) -> Float {
        let x = a * simd_dot(d, e1), y = b * simd_dot(d, e2)
        return sqrt(x * x + y * y)
    }

    static func normalized(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let n = simd_length(v)
        return n > 1e-6 ? v / n : fallback
    }

    static func bounds(_ pts: [SIMD2<Float>], pad: Float) -> SIMD4<Float> {
        var b = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for p in pts {
            b = SIMD4(min(b.x, p.x), min(b.y, p.y), max(b.z, p.x), max(b.w, p.y))
        }
        return SIMD4(b.x - pad, b.y - pad, b.z + pad, b.w + pad)
    }

    /// Andrew's monotone chain, counter-clockwise.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let pts = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard pts.count >= 3 else {
            return pts.isEmpty ? [] : [pts[0], pts[pts.count - 1] + SIMD2(1e-3, 0), pts[pts.count - 1] + SIMD2(0, 1e-3)]
        }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
        for p in pts {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in pts.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }
}

extension SIMD4 where Scalar == Float {
    init(_ xy: SIMD2<Float>, _ z: Float, _ w: Float) {
        self.init(xy.x, xy.y, z, w)
    }

    init(_ xy: SIMD2<Float>, _ zw: SIMD2<Float>) {
        self.init(xy.x, xy.y, zw.x, zw.y)
    }
}

/// The muscle regions of Tools/ExerciseAnimations/logitanim/anatomy.py: ellipsoids and patches in
/// the frames of the bones they belong to, so they move with them.
enum FigureAnatomy {
    struct Region {
        enum Shape {
            case ellipsoid(center: SIMD3<Float>, axes: [SIMD3<Float>], radii: SIMD3<Float>, normal: SIMD3<Float>?)
            case patch(points: [SIMD3<Float>], normal: SIMD3<Float>, rounding: Float)
        }

        let shape: Shape
        let part: String
    }

    private static func unit(_ v: SIMD3<Float>) -> SIMD3<Float> {
        FigureScene.normalized(v, fallback: v)
    }

    private static func frame(_ d: SIMD3<Float>, _ front: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let d = unit(d)
        var f = front - simd_dot(front, d) * d
        f = simd_length(f) > 1e-6 ? simd_normalize(f) : unit(simd_cross(d, SIMD3(0, 0, 1)))
        return (d, f, unit(simd_cross(d, f)))
    }

    static func regions(pose: ExerciseRig.Pose, names: [String]) -> [Region] {
        let want = Set(names)
        var out: [Region] = []
        let p = pose.joint("pelvis")
        let f = pose.vector("torsoF"), u = pose.vector("torsoU"), r = pose.vector("torsoR")
        let gf = pose.vector("pelvisF"), gu = pose.vector("pelvisU"), gr = pose.vector("pelvisR")
        func blob(_ c: SIMD3<Float>, _ axes: [SIMD3<Float>], _ radii: SIMD3<Float>, _ n: SIMD3<Float>?, _ part: String) {
            out.append(Region(shape: .ellipsoid(center: c, axes: axes.map(unit), radii: radii, normal: n.map(unit)),
                              part: part))
        }
        for (s, sgn) in [("L", Float(-1)), ("R", Float(1))] {
            let rs = r * sgn
            if want.contains("pecs") {
                blob(p + u * 33.5 + f * 10.0 + rs * 7.8, [rs, u, f], SIMD3(8.4, 6.4, 5.5), f + rs * 0.35, "torso")
            }
            if want.contains("obliques") {
                blob(p + u * 14.0 + rs * 11.0 + f * 4.0, [u, f, rs], SIMD3(8.5, 7.0, 5.0), rs + f * 0.3, "torso")
            }
            func t(_ a: Float, _ b: Float, _ c: Float) -> SIMD3<Float> { p + f * a + u * b + rs * c }
            if want.contains("lats") {
                out.append(Region(shape: .patch(points: [t(-2.0, 41.0, 16.5), t(-11.0, 37.0, 7.0), t(-12.0, 12.5, 3.2),
                                                         t(-6.0, 19.0, 14.5)],
                                                normal: unit(-f * 0.6 + rs * 0.8), rounding: 2.2), part: "torso"))
            }
            if want.contains("erectors") {
                out.append(Region(shape: .patch(points: [t(-7.5, 31.0, 2.2), t(-12.5, 31.0, 7.4), t(-12.5, 3.0, 7.2),
                                                         t(-7.5, 3.0, 2.2)], normal: -f, rounding: 2.6), part: "torso"))
            }
            if want.contains("glutes") {
                blob(p - gu * 1.5 - gf * 7.5 + gr * sgn * 7.0, [gr, gu, gf], SIMD3(7.6, 8.6, 6.0), -gf + gr * sgn * 0.3,
                     "hips")
            }

            // arms
            let sh = pose.joint("shoulder" + s), el = pose.joint("elbow" + s), hand = pose.joint("hand" + s)
            let biceps = pose.vector("biceps" + s)
            let lu = max(simd_length(el - sh), 1)
            let (d, fr, c) = frame(el - sh, biceps)
            if want.contains("delts") {
                blob(sh + d * 3.2 + u * 0.8, [d, fr, c], SIMD3(9.6, 7.6, 7.6), nil, "arm" + s)
            }
            if want.contains("biceps") {
                blob(sh + d * (0.56 * lu) + fr * 2.4, [d, fr, c], SIMD3(0.36 * lu, 4.4, 4.8), fr, "arm" + s)
            }
            if want.contains("triceps") {
                blob(sh + d * (0.5 * lu) - fr * 2.4, [d, fr, c], SIMD3(0.38 * lu, 4.4, 5.0), -fr, "arm" + s)
            }
            if want.contains("forearms") {
                let wrist = pose.joint("wrist" + s)
                let wr = simd_length(wrist - hand) > 1e-3 ? wrist : hand
                let lf = max(simd_length(wr - el), 1)
                let d2 = unit(wr - el)
                let fr2 = unit(simd_cross(simd_cross(d, fr), d2))
                let c2 = unit(simd_cross(d2, fr2))
                blob(el + d2 * (0.33 * lf) + fr2 * 1.9, [d2, fr2, c2], SIMD3(0.3 * lf, 4.0, 4.4), fr2, "fore" + s)
            }

            // legs
            let hip = pose.joint("hip" + s), knee = pose.joint("knee" + s), ankle = pose.joint("ankle" + s)
            let lt = max(simd_length(knee - hip), 1)
            let (dl, frl, cl) = frame(knee - hip, pose.vector("thighFront" + s))
            let latRaw = gr * sgn - simd_dot(gr * sgn, dl) * dl
            let lateral = unit(latRaw)
            if want.contains("quads") {
                blob(hip + dl * (0.54 * lt) + frl * 3.2, [dl, frl, cl], SIMD3(0.42 * lt, 6.0, 7.6), frl, "leg" + s)
            }
            if want.contains("hamstrings") {
                blob(hip + dl * (0.52 * lt) - frl * 3.0, [dl, frl, cl], SIMD3(0.4 * lt, 5.8, 7.2), -frl, "leg" + s)
            }
            if want.contains("adductors") {
                blob(hip + dl * (0.4 * lt) - lateral * 3.6, [dl, lateral, frl], SIMD3(0.33 * lt, 4.8, 5.6), -lateral,
                     "leg" + s)
            }
            if want.contains("abductors") {
                blob(hip + dl * (0.16 * lt) + lateral * 4.4, [dl, lateral, frl], SIMD3(0.24 * lt, 5.0, 6.0), lateral,
                     "leg" + s)
            }
            if want.contains("hipflexors") {
                blob(hip + dl * (0.14 * lt) + frl * 4.0, [dl, frl, cl], SIMD3(0.2 * lt, 4.4, 5.0), frl, "leg" + s)
            }
            if want.contains("calves") {
                let ls = max(simd_length(ankle - knee), 1)
                let (ds, frs, cs) = frame(ankle - knee, pose.vector("shankFront" + s))
                blob(knee + ds * (0.32 * ls) - frs * 2.8, [ds, frs, cs], SIMD3(0.27 * ls, 4.8, 5.8), -frs, "shin" + s)
            }
        }
        if want.contains("abs") {
            blob(p + u * 16.0 + f * 10.5, [u, r, f], SIMD3(10.5, 6.6, 5.5), f, "torso")
        }
        if want.contains("traps") {
            func t(_ a: Float, _ b: Float, _ c: Float) -> SIMD3<Float> { p + f * a + u * b + r * c }
            let girdle = (pose.joint("shoulderL") + pose.joint("shoulderR")) / 2 - p
            let shrug = simd_dot(girdle, u) - FigureScene.torsoLength
            let protract = simd_dot(girdle, f)
            let top = FigureScene.torsoLength + 5.5 + shrug
            out.append(Region(shape: .patch(points: [t(-6.0 + protract, top, -14.0), t(-6.0 + protract, top, 14.0),
                                                     t(-11.0, FigureScene.torsoLength - 20.0, 2.5),
                                                     t(-11.0, FigureScene.torsoLength - 20.0, -2.5)],
                                            normal: unit(-f + u * 0.25), rounding: 3.0), part: "torso"))
        }
        return out
    }
}
