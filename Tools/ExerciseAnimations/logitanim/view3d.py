"""Camera-free rendering: the figure and its equipment as 3D primitives, drawn from any orthographic
camera (yaw around the vertical, pitch above the horizon) in the same flat language as body.py.

body.py builds a fixed paint order for one of four cameras. Here every part is a 3D primitive with
a depth at each pixel, and each pixel is painted back to front, so the order follows the camera as
it turns and nothing pops. The knockout band a part cuts into what lies behind it grows with how
far in front it is (body.occlusion), exactly as between the two halves of a limb in body.py.

This is the reference for the app's Metal renderer (Tools/ExerciseAnimations/metal) and the source
of the baked rig data it plays.

Conventions (cm): yaw 0 is body.py's side camera (looking along -z), 90 the front camera, -90 the
back camera; pitch > 0 looks down from above.
"""
import math

import numpy as np

from .sdf import V, Circle, Cone, Poly, Union, Ellipse
from .spec import (PAL, MUSCLE, R_THIGH, R_SHANK, R_UPPER, R_FORE, R_HAND, R_HEEL, R_TOE, R_HEAD,
                   R_THIGH_F, R_SHANK_F, GAP)
from .rig import unit
from .body import SPLIT_NEAR, SPLIT_FULL
from . import anatomy


# ---- camera ---------------------------------------------------------------------------------------

class Cam3:
    """Orthographic camera. R, U: screen right and up; Vd: towards the camera (depth grows with it)."""

    def __init__(self, yaw=0.0, pitch=0.0):
        th, ph = math.radians(yaw), math.radians(pitch)
        self.yaw, self.pitch = yaw, pitch
        self.Vd = np.array([math.sin(th) * math.cos(ph), math.sin(ph), math.cos(th) * math.cos(ph)])
        self.R = np.array([math.cos(th), 0.0, -math.sin(th)])
        self.U = np.cross(self.Vd, self.R)
        self.kind = 'generic'

    def p(self, v):
        v = np.asarray(v, float)
        return V(float(np.dot(self.R, v)), float(np.dot(self.U, v)))

    d = p

    def depth(self, v):
        return float(np.dot(self.Vd, np.asarray(v, float)))

    def lift(self, e2):
        """A screen direction as a 3D vector."""
        return self.R * e2[0] + self.U * e2[1]


# ---- primitives -----------------------------------------------------------------------------------

class Prim:
    """One drawable: a 2D shape on the screen plane, its depth at any pixel, a colour, the knockout
    band it cuts into what lies behind (gap, tapered near `anchors`), muscle overlays (2D shapes in
    colour), and a group: parts of one group never band against each other (forearm and hand)."""

    def __init__(self, shape, depth_fn, color, gap=0.0, anchors=(), overlays=(), group=None, name=''):
        self.shape, self.depth_fn, self.color = shape, depth_fn, color
        self.gap, self.anchors, self.overlays = gap, list(anchors), list(overlays)
        self.group, self.name = group, name


def _seg_param(X, Y, a, b):
    ab = b - a
    L2 = max(float(ab @ ab), 1e-9)
    t = ((X - a[0]) * ab[0] + (Y - a[1]) * ab[1]) / L2
    t = np.clip(t, 0.0, 1.0)
    px = a[0] + ab[0] * t
    py = a[1] + ab[1] * t
    return t, np.hypot(X - px, Y - py)


def cone_depth(cam, a3, b3, ra_v, rb_v, ra_s, rb_s):
    """Depth over the screen of a round cone a3 -> b3: the axis depth at the nearest axis point plus
    the bulge of its cross-section towards the camera (ra_v/rb_v: extent towards the camera,
    ra_s/rb_s: the half-width on screen)."""
    a2, b2 = cam.p(a3), cam.p(b3)
    za, zb = cam.depth(a3), cam.depth(b3)

    def fn(X, Y):
        t, dperp = _seg_param(X, Y, a2, b2)
        rv = ra_v + (rb_v - ra_v) * t
        rs = np.maximum(ra_s + (rb_s - ra_s) * t, 1e-3)
        bulge = rv * np.sqrt(np.clip(1.0 - (dperp / rs) ** 2, 0.0, 1.0))
        return za + (zb - za) * t + bulge
    return fn


def sphere_depth(cam, c3, r):
    c2, zc = cam.p(c3), cam.depth(c3)

    def fn(X, Y):
        d = np.hypot(X - c2[0], Y - c2[1])
        return zc + np.sqrt(np.clip(r * r - d * d, 0.0, None))
    return fn


def ellipse_support(a, b, e1, e2, dirv):
    """Half-extent along dirv of an ellipse with semi-axes a (along e1) and b (along e2)."""
    return math.sqrt((a * float(np.dot(dirv, e1))) ** 2 + (b * float(np.dot(dirv, e2))) ** 2)


def limb(cam, a3, b3, ra, rb, lat3=None, ra_lat=None, rb_lat=None):
    """A limb segment as a round cone. With lat3 (the limb's lateral direction) and lateral radii, the
    cross-section is an ellipse: (ra, rb) front-to-back, (ra_lat, rb_lat) side to side, so a leg reads
    slimmer from the front than side-on (body.py's R_THIGH_F). Returns (shape, depth_fn)."""
    a3, b3 = np.asarray(a3, float), np.asarray(b3, float)
    a2, b2 = cam.p(a3), cam.p(b3)
    axis = unit(b3 - a3)
    if lat3 is None:
        sh = Cone(a2, b2, ra, rb)
        return sh, cone_depth(cam, a3, b3, ra, rb, ra, rb)
    lat = unit(np.asarray(lat3, float) - np.dot(lat3, axis) * axis)
    sag = unit(np.cross(axis, lat))
    d2 = b2 - a2
    if float(np.hypot(*d2)) > 1e-3:
        e2 = V(-d2[1], d2[0]) / float(np.hypot(*d2))          # screen direction across the limb
    else:
        e2 = V(1.0, 0.0)
    E3 = cam.lift(e2)
    E3 = E3 - np.dot(E3, axis) * axis
    E3 = unit(E3) if np.linalg.norm(E3) > 1e-6 else lat
    Vc = cam.Vd - np.dot(cam.Vd, axis) * axis
    Vc = unit(Vc) if np.linalg.norm(Vc) > 1e-6 else sag
    ra_s = ellipse_support(ra_lat, ra, lat, sag, E3)
    rb_s = ellipse_support(rb_lat, rb, lat, sag, E3)
    ra_v = ellipse_support(ra_lat, ra, lat, sag, Vc)
    rb_v = ellipse_support(rb_lat, rb, lat, sag, Vc)
    return Cone(a2, b2, ra_s, rb_s), cone_depth(cam, a3, b3, ra_v, rb_v, ra_s, rb_s)


# ---- the torso: a loft of elliptical sections ------------------------------------------------------

# (height along the spine from the hip joints, forward offset, half-width side to side, half-depth
# front to back), outer extents in cm. Fitted so that side-on the loft is body.py's chest, belly and
# glute profile and from the front its tapering core; the shoulder yoke and caps are added on top.
TORSO_SECTIONS = [
    (51.0, 1.2, 13.0, 9.0),
    (47.0, 1.2, 19.6, 11.8),
    (41.8, 1.2, 19.15, 12.9),
    (33.0, 1.2, 18.4, 12.26),
    (24.0, 1.2, 17.6, 11.6),
    (15.0, 0.79, 16.8, 11.91),
    (6.5, 0.4, 16.05, 12.2),
    (1.0, -1.05, 15.6, 12.35),
    (-5.5, -4.3, 15.0, 6.9),
    (-8.0, -2.6, 13.0, 5.97),
]
TORSO_ROUND = 3.0           # the loft is drawn this much inside its outline and then rounded out
TORSO_DEPTH_SCALE = 0.5     # how much of its real bulge the torso uses when ordered against the
                            # parts around it: the head and a near limb stay in front of it


def _hull(pts):
    pts = sorted(set((round(float(p[0]), 5), round(float(p[1]), 5)) for p in pts))
    if len(pts) < 3:
        p = np.array(pts)
        return np.array([p[0], p[-1] + [1e-3, 0], p[-1] + [0, 1e-3]])

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])


def torso_sections_3d(J, n=16):
    """The loft's sections as rings of 3D points (inside the rounding)."""
    tf = J.torso_frame
    P = J.p['pelvis']
    rings = []
    for h, c, A, S in TORSO_SECTIONS:
        a, s = max(A - TORSO_ROUND, 0.5), max(S - TORSO_ROUND, 0.5)
        ctr = P + tf.u * h + tf.f * c
        ring = [ctr + tf.r * (a * math.cos(2 * math.pi * k / n)) + tf.f * (s * math.sin(2 * math.pi * k / n))
                for k in range(n)]
        rings.append((ctr, a, s, ring))
    return rings


def torso(J, cam):
    """The torso's 2D shape and depth from this camera."""
    tf = J.torso_frame
    rings = torso_sections_3d(J)
    hulls = []
    for (c0, _, _, r0), (c1, _, _, r1) in zip(rings, rings[1:]):
        hulls.append(Poly(_hull([cam.p(q) for q in r0 + r1]), r=TORSO_ROUND))
    loft = Union(hulls)
    sl, sr = J.p['shoulderL'], J.p['shoulderR']
    inward = unit(sr - sl)
    ya, yb = sl + inward * 1.5 + tf.u * 0.3, sr - inward * 1.5 + tf.u * 0.3
    yoke = Cone(cam.p(ya), cam.p(yb), 6.8, 6.8)
    caps = [Circle(cam.p(sl), R_UPPER[0]), Circle(cam.p(sr), R_UPPER[0])]
    shape = Union([loft, Union([yoke] + caps)], k=6.0)

    # depth: the section at the pixel's height along the spine, its centre's depth plus (a share of)
    # its bulge towards the camera, rounded across the width
    P = J.p['pelvis']
    hs = np.array([s[0] for s in TORSO_SECTIONS])
    cs = np.array([s[1] for s in TORSO_SECTIONS])
    As = np.array([s[2] for s in TORSO_SECTIONS])
    Ss = np.array([s[3] for s in TORSO_SECTIONS])
    Vc = cam.Vd - np.dot(cam.Vd, tf.u) * tf.u
    vn = float(np.linalg.norm(Vc))
    Vc = Vc / vn if vn > 1e-6 else tf.f
    ext_v = np.sqrt((As * float(np.dot(Vc, tf.r))) ** 2 + (Ss * float(np.dot(Vc, tf.f))) ** 2)
    Rc = cam.R - np.dot(cam.R, tf.u) * tf.u
    rn = float(np.linalg.norm(Rc))
    Rc = Rc / rn if rn > 1e-6 else tf.r
    ext_r = np.sqrt((As * float(np.dot(Rc, tf.r))) ** 2 + (Ss * float(np.dot(Rc, tf.f))) ** 2)
    bottom, top = P + tf.u * hs[-1], P + tf.u * hs[0]
    b2, t2 = cam.p(bottom), cam.p(top)
    zb, zt = cam.depth(bottom), cam.depth(top)
    axis2 = t2 - b2
    L2 = max(float(axis2 @ axis2), 1e-9)
    order = np.argsort(hs)
    hs_o, cs_o, ev_o, er_o = hs[order], cs[order], ext_v[order], ext_r[order]
    fwd_off = float(np.dot(cam.Vd, tf.f))
    fwd2 = cam.p(tf.f)

    def depth(X, Y):
        t = ((X - b2[0]) * axis2[0] + (Y - b2[1]) * axis2[1]) / L2
        t = np.clip(t, 0.0, 1.0)
        h = hs[-1] + (hs[0] - hs[-1]) * t
        c = np.interp(h, hs_o, cs_o)
        ev = np.interp(h, hs_o, ev_o)
        er = np.maximum(np.interp(h, hs_o, er_o), 1e-3)
        cx = b2[0] + axis2[0] * t + fwd2[0] * c
        cy = b2[1] + axis2[1] * t + fwd2[1] * c
        off = np.hypot(X - cx, Y - cy)
        prof = np.sqrt(np.clip(1.0 - (off / er) ** 2, 0.0, 1.0))
        return zb + (zt - zb) * t + c * fwd_off + TORSO_DEPTH_SCALE * ev * prof
    return shape, depth


# ---- muscle overlays ------------------------------------------------------------------------------

def _visibility(n, cam):
    if n is None:
        return 1.0
    nd = float(np.dot(n, cam.Vd))
    x = min(max((nd + 0.55) / 0.4, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def project_blob(blob, cam):
    vis = _visibility(blob.n, cam)
    if vis <= 0.02:
        return None
    M = np.array([cam.R, cam.U])
    ME = M @ (blob.E.T * blob.a)
    w, vecs = np.linalg.eigh(ME @ ME.T)
    w = np.maximum(w, 1e-6)
    c2 = M @ blob.c
    angle = math.atan2(vecs[1, 1], vecs[0, 1])
    return Ellipse(c2, max(math.sqrt(w[1]) * vis, 0.05), max(math.sqrt(w[0]) * vis, 0.05), angle)


def project_patch(patch, cam):
    vis = _visibility(patch.n, cam)
    if vis <= 0.02:
        return None
    pts = np.array([cam.p(p) for p in patch.pts])
    c = pts.mean(axis=0)
    return Poly(c + (pts - c) * vis, r=patch.r * vis)


# ---- the figure -----------------------------------------------------------------------------------

def figure(J, cam, muscles, color, pal=PAL):
    """The figure's parts as prims, with the muscle overlays on the parts that own them."""
    fig = pal['fig']
    parts = {}

    sh, dfn = torso(J, cam)
    parts['torso'] = Prim(sh, dfn, fig, GAP, group='torso', name='torso')
    hc = J.p['head']
    parts['head'] = Prim(Circle(cam.p(hc), R_HEAD), sphere_depth(cam, hc, R_HEAD), fig, GAP, group='head',
                         name='head')
    pf = J.pelvis_frame
    for s, sg in (('L', -1.0), ('R', 1.0)):
        P = lambda k: J.p[k + s]
        lat = pf.r * sg
        sh, dfn = limb(cam, P('hip'), P('knee'), R_THIGH[0], R_THIGH[1], lat, R_THIGH_F[0], R_THIGH_F[1])
        parts['leg' + s] = Prim(sh, dfn, fig, GAP, anchors=[(cam.p(P('hip')), 10.5, 15.0), (cam.p(P('knee')), 8.0, 13.0)],
                                group='leg' + s, name='leg' + s)
        sh, dfn = limb(cam, P('knee'), P('ankle'), R_SHANK[0], R_SHANK[1], lat, R_SHANK_F[0], R_SHANK_F[1])
        foot = Cone(cam.p(P('heel')), cam.p(P('toe')), R_HEEL, R_TOE)
        fdfn = cone_depth(cam, P('heel'), P('toe'), R_HEEL, R_TOE, R_HEEL, R_TOE)
        parts['shin' + s] = Prim(sh, dfn, fig, GAP, anchors=[(cam.p(P('knee')), 8.0, 13.0)], group='shin' + s,
                                 name='shin' + s)
        parts['foot' + s] = Prim(foot, fdfn, fig, GAP, group='shin' + s, name='foot' + s)

        sh, dfn = limb(cam, P('shoulder'), P('elbow'), R_UPPER[0], R_UPPER[1])
        parts['arm' + s] = Prim(sh, dfn, fig, GAP, anchors=[(cam.p(P('shoulder')), 7.5, 12.0),
                                                            (cam.p(P('elbow')), 6.0, 11.0)],
                                group='arm' + s, name='arm' + s)
        w = P('hand')
        if J.style['hand' + s] == 'palm':
            sh, dfn = limb(cam, P('elbow'), w, R_FORE[0], 4.0)
            pd = unit(J.v['palm' + s])
            down = unit(np.cross(pd, np.cross(np.array([0, 1.0, 0]), pd))) if abs(pd[1]) < 0.9 else np.array([0, 0, 1.0])
            ha, hb = w - np.array([0, 1.3, 0]) + pd * 0.6, w - np.array([0, 2.3, 0]) + pd * 9.6
            hand = Cone(cam.p(ha), cam.p(hb), 3.1, 2.1)
            hdfn = cone_depth(cam, ha, hb, 3.1, 2.1, 3.1, 2.1)
        elif 'wrist' + s in J.p:
            wr = P('wrist')
            sh, dfn = limb(cam, P('elbow'), wr, R_FORE[0], R_FORE[1])
            hand = Union([Cone(cam.p(wr), cam.p(w), R_FORE[1], R_HAND - 0.4), Circle(cam.p(w), R_HAND - 0.4)])
            hdfn = sphere_depth(cam, w, R_HAND - 0.4)
        else:
            sh, dfn = limb(cam, P('elbow'), w, R_FORE[0], R_FORE[1])
            hand = Circle(cam.p(w), R_HAND)
            hdfn = sphere_depth(cam, w, R_HAND)
        parts['fore' + s] = Prim(sh, dfn, fig, GAP, anchors=[(cam.p(P('elbow')), 6.0, 11.0)], group='fore' + s,
                                 name='fore' + s)
        parts['hand' + s] = Prim(hand, hdfn, fig, GAP, group='fore' + s, name='hand' + s)

    owner = {'torso': 'torso', 'hips': 'torso'}
    for s in 'LR':
        owner.update({'arm' + s: 'arm' + s, 'fore' + s: 'fore' + s, 'leg' + s: 'leg' + s, 'shin' + s: 'shin' + s})
    for blob in anatomy.blobs(J, muscles):
        e = project_patch(blob, cam) if isinstance(blob, anatomy.Patch) else project_blob(blob, cam)
        if e is not None and owner.get(blob.part) in parts:
            parts[owner[blob.part]].overlays.append((e, color, 1.0))
    return list(parts.values())


# ---- equipment ---------------------------------------------------------------------------------------

FAR = 1000.0    # rays start this far in front of the scene


def _ray(cam, X, Y):
    """Ray origins (H, W, 3) on a plane in front of the scene and the shared direction."""
    O = (cam.R[None, None, :] * X[..., None] + cam.U[None, None, :] * Y[..., None]
         + cam.Vd[None, None, :] * FAR)
    return O, -cam.Vd


def _smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def cylinder_depth(cam, c3, ax, r, half):
    """Exact depth of a capped cylinder's front surface. Off it (its anti-aliased edge and knockout
    band) the depth of its outline there: the axis point nearest the pixel, or the near cap's centre
    when the axis points at the camera. So a band never stands nearer than the cylinder's own edge."""
    c3, ax = np.asarray(c3, float), unit(ax)
    cz, az = cam.depth(c3), float(np.dot(cam.Vd, ax))
    zc = cz + abs(az) * half
    cx, cy = float(np.dot(cam.R, c3)), float(np.dot(cam.U, c3))
    axx, axy = float(np.dot(cam.R, ax)), float(np.dot(cam.U, ax))
    s2 = axx * axx + axy * axy
    side_on = float(_smoothstep(0.2, 0.5, math.sqrt(s2)))

    def fn(X, Y):
        O, D = _ray(cam, X, Y)
        w = O - c3
        wa = w @ ax
        da = float(D @ ax)
        wp = w - wa[..., None] * ax
        dp = D - da * ax
        A = float(dp @ dp)
        best = np.full(X.shape, np.inf)
        if A > 1e-9:
            B = 2.0 * (wp @ dp)
            C = np.einsum('...i,...i->...', wp, wp) - r * r
            disc = B * B - 4 * A * C
            ok = disc >= 0
            t = (-B - np.sqrt(np.where(ok, disc, 0.0))) / (2 * A)
            along = wa + t * da
            hit = ok & (np.abs(along) <= half)
            best = np.where(hit, t, best)
        if abs(da) > 1e-9:
            for sgn in (-1.0, 1.0):
                t = (sgn * half - wa) / da
                q = w + t[..., None] * D - (sgn * half) * ax
                hit = np.einsum('...i,...i->...', q, q) <= r * r
                best = np.where(hit & (t < best), t, best)
        t = np.clip(((X - cx) * axx + (Y - cy) * axy) / max(s2, 1e-9), -half, half)
        outline = zc + (cz + t * az - zc) * side_on
        return np.where(np.isfinite(best), FAR - best, outline)
    return fn


def _nearest_on_poly(X, Y, poly):
    """The point of a closed polygon's outline nearest each pixel."""
    best = np.full(X.shape, np.inf)
    QX, QY = np.zeros(X.shape), np.zeros(X.shape)
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        e = b - a
        t = np.clip(((X - a[0]) * e[0] + (Y - a[1]) * e[1]) / max(float(e @ e), 1e-12), 0.0, 1.0)
        qx, qy = a[0] + t * e[0], a[1] + t * e[1]
        d = (X - qx) ** 2 + (Y - qy) ** 2
        m = d < best
        best, QX, QY = np.where(m, d, best), np.where(m, qx, QX), np.where(m, qy, QY)
    return QX, QY


def box_depth(cam, c3, axes, half, rounding=0.0):
    """Exact depth of a box's front face (slab test). Off it (its anti-aliased edge and knockout band)
    the front face's depth at the nearest point of its outline's inner hull, so a band never stands
    nearer than the box's own edge."""
    from .equipment import _hull as hull2
    c3 = np.asarray(c3, float)
    axes = [unit(a) for a in axes]
    zc = cam.depth(c3) + sum(abs(float(np.dot(cam.Vd, a))) * h for a, h in zip(axes, half))
    inner = [h - rounding for h in half]          # the corners eq.box3 rounds (its hull is the same)
    hull = hull2(np.array([cam.p(c3 + axes[0] * sx * inner[0] + axes[1] * sy * inner[1] + axes[2] * sz * inner[2])
                           for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]))
    c2 = cam.p(c3)

    def slab(X, Y):
        O, D = _ray(cam, X, Y)
        w = O - c3
        tn = np.full(X.shape, -np.inf)
        tf_ = np.full(X.shape, np.inf)
        for a, h in zip(axes, half):
            wa = w @ a
            da = float(D @ a)
            if abs(da) < 1e-9:
                inside = np.abs(wa) <= h
                tn = np.where(inside, tn, np.inf)
                continue
            t1, t2 = (-h - wa) / da, (h - wa) / da
            tn = np.maximum(tn, np.minimum(t1, t2))
            tf_ = np.minimum(tf_, np.maximum(t1, t2))
        return (tn <= tf_) & np.isfinite(tn), tn

    def fn(X, Y):
        hit, tn = slab(X, Y)
        if hit.all():
            return FAR - tn
        QX, QY = _nearest_on_poly(X, Y, hull)
        hit2, tn2 = slab(QX + (c2[0] - QX) * 0.01, QY + (c2[1] - QY) * 0.01)
        return np.where(hit, FAR - tn, np.where(hit2, FAR - tn2, zc))
    return fn


def equipment(items, cam, pal=PAL):
    """Prims for the items' 3D specs; returns (prims, number of items that exist only in 2D)."""
    from . import equipment as eq
    prims, missing = [], 0
    for k, it in enumerate(items):
        spec = getattr(it, 'spec3d', None)
        if spec is None:
            if it.shape is not None:
                missing += 1
            continue
        for e in spec:
            backdrop = e[-1] == 'back'
            kind, col, gap = e[0], pal[e[-2]], GAP if (e[-1] and not backdrop) else 0.0
            if kind == 'cyl':
                _, c3, ax, r, half = e[:5]
                sh = eq.cyl(cam, c3, ax, r, half)
                dfn = cylinder_depth(cam, c3, ax, r, half)
            elif kind == 'cap':
                _, a3, b3, r = e[:4]
                sh = Cone(cam.p(a3), cam.p(b3), r, r)
                dfn = cone_depth(cam, a3, b3, r, r, r, r)
            elif kind == 'cone':
                _, a3, b3, ra, rb = e[:5]
                sh = Cone(cam.p(a3), cam.p(b3), ra, rb)
                dfn = cone_depth(cam, a3, b3, ra, rb, ra, rb)
            elif kind == 'sph':
                _, c3, r = e[:3]
                sh = Circle(cam.p(c3), r)
                dfn = sphere_depth(cam, c3, r)
            elif kind == 'box':
                _, c3, axes, half, rnd = e[:5]
                sh = eq.box3(cam, c3, unit(axes[0]), unit(axes[1]), unit(axes[2]), half[0], half[1], half[2], rnd)
                dfn = box_depth(cam, c3, axes, half, rnd)
            else:
                raise ValueError(kind)
            if backdrop:
                # behind every other part from any side, in its own depth order among backdrops
                dfn = (lambda f: (lambda X, Y: f(X, Y) - BACKDROP))(dfn)
            prims.append(Prim(sh, dfn, col, gap, group=f'eq{k}', name=f'eq{k}:{kind}'))
    return prims, missing


BACKDROP = 1.0e5     # how far a backdrop is pushed behind everything else


def floor_prim(center3, radius, cam, pal=PAL):
    """The floor line: a thin disc under the figure, an ellipse once the camera looks down on it."""
    c = np.asarray(center3, float)
    s = abs(math.sin(math.radians(cam.pitch)))
    sh = Ellipse(cam.p(c), radius, max(radius * s, 0.85), 0.0) if s > 0.02 else None
    if sh is None:
        from .sdf import RBox
        sh = RBox(cam.p(c), radius, 0.85, 0.85)
    return Prim(sh, lambda X, Y: np.full(X.shape, -1e6), pal['floor'], 0.0, group='floor', name='floor')


# ---- per-pixel depth compositing --------------------------------------------------------------------

def composite(cv, prims, knock):
    """Paint prims onto canvas cv back to front per pixel. Each prim cuts its knockout band into
    whatever is on top so far by how far in front of it it lies (body.occlusion of the lead); a
    prim of the same group never cuts one. Where a part is not yet clearly in front, the highlight
    of the part behind shows through it (body.py's partner rule)."""
    H, W = cv.h, cv.w
    X = ((np.arange(W, dtype=np.float64) + 0.5 - cv.ox) / cv.s)[None, :].repeat(H, 0)
    Y = ((cv.oy - (np.arange(H, dtype=np.float64) + 0.5)) / cv.s)[:, None].repeat(W, 1)
    n = len(prims)
    if n == 0:
        return
    D = np.full((n, H, W), np.inf)
    Z = np.full((n, H, W), -np.inf)
    G = np.zeros((n, H, W))
    OA = np.zeros((n, H, W))
    OC = np.zeros((n, H, W, 3), np.float32)
    for i, pr in enumerate(prims):
        b = pr.shape.bbox()
        pad = pr.gap + 2.0 / cv.s
        j0 = max(int(math.floor(cv.ox + (b[0] - pad) * cv.s)) - 1, 0)
        j1 = min(int(math.ceil(cv.ox + (b[2] + pad) * cv.s)) + 1, W)
        i0 = max(int(math.floor(cv.oy - (b[3] + pad) * cv.s)) - 1, 0)
        i1 = min(int(math.ceil(cv.oy - (b[1] - pad) * cv.s)) + 1, H)
        if j1 <= j0 or i1 <= i0:
            continue
        x, y = X[i0:i1, j0:j1], Y[i0:i1, j0:j1]
        D[i, i0:i1, j0:j1] = pr.shape.sdf(x, y)
        Z[i, i0:i1, j0:j1] = pr.depth_fn(x, y)
        g = np.full(x.shape, float(pr.gap))
        for pt, a0, a1 in pr.anchors:
            tt = np.clip((np.hypot(x - pt[0], y - pt[1]) - a0) / (a1 - a0), 0, 1)
            g = g * (tt * tt * (3 - 2 * tt))
        G[i, i0:i1, j0:j1] = g
        if pr.overlays:
            oa = np.zeros(x.shape)
            oc = np.zeros(x.shape + (3,), np.float32)
            for osh, ocol, oal in pr.overlays:
                a = np.clip(0.5 - osh.sdf(x, y) * cv.s, 0, 1) * oal
                oc += (np.asarray(ocol, np.float32) - oc) * a[..., None]
                oa = oa + (1 - oa) * a
            OA[i, i0:i1, j0:j1] = oa
            OC[i, i0:i1, j0:j1] = np.where(oa[..., None] > 1e-6, oc / np.maximum(oa[..., None], 1e-6), 0)

    C = np.clip(0.5 - D * cv.s, 0, 1)
    CG = np.maximum(np.clip(0.5 - (D - G) * cv.s, 0, 1), C)
    active = CG > 0
    Zs = np.where(active, Z, -np.inf)
    order = np.argsort(Zs, axis=0)                     # back to front
    groups = [pr.group for pr in prims]
    gid = {g: k for k, g in enumerate(sorted(set(str(g) for g in groups)))}
    GI = np.array([gid[str(g)] for g in groups])
    cols = np.array([np.asarray(pr.color, np.float32) for pr in prims])

    img = cv.img
    k_col = np.asarray(knock, np.float32)
    top_z = np.full((H, W), -np.inf)
    top_g = np.full((H, W), -1)
    top_oa = np.zeros((H, W))
    top_oc = np.zeros((H, W, 3), np.float32)
    ii, jj = np.meshgrid(np.arange(H), np.arange(W), indexing='ij')
    for k in range(n):
        idx = order[k]
        c = C[idx, ii, jj]
        cg = CG[idx, ii, jj]
        on = cg > 0
        if not on.any():
            continue
        z = Z[idx, ii, jj]
        g = GI[idx]
        lead = np.where(np.isfinite(top_z), z - top_z, 99.0)
        s = np.clip((lead - SPLIT_NEAR) / (SPLIT_FULL - SPLIT_NEAR), 0.0, 1.0)
        s = s * s * (3 - 2 * s)                     # body.occlusion, per pixel
        s = np.where(top_g == g, 0.0, s)
        band = (cg - c) * s
        col = cols[idx]
        oa = OA[idx, ii, jj]
        oc = OC[idx, ii, jj]
        fill = col + (oc - col) * oa[..., None]
        # the highlight of the part behind shows through where this one isn't clearly in front
        through = top_oa * (1.0 - s)
        fill = fill + (top_oc - fill) * through[..., None]
        img[:] = img * (1 - c - band)[..., None] + k_col * band[..., None] + fill * c[..., None]
        covered = c > 0.5
        top_z = np.where(covered, z, top_z)
        top_g = np.where(covered, g, top_g)
        top_oa = np.where(covered, np.maximum(oa, through), top_oa)
        top_oc = np.where(covered[..., None], np.where((oa > 0)[..., None], oc, top_oc), top_oc)


# ---- an exercise from any camera ------------------------------------------------------------------

class _View:
    """What the exercises' equipment functions need from a view: a camera (and layer names)."""

    def __init__(self, cam):
        self.cam = cam
        self.layers = []
        self.paint_on = {}


def floor_disc(ex):
    """Centre and radius of the floor disc: under everything the exercise sweeps through, with the
    margin the side view's floor line has."""
    from .rig import solve
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    for i in range(24):
        J = solve(ex.pose_fn(ex.phase(ex.duration * i / 24)))
        pts = np.array(list(J.p.values()))
        lo, hi = np.minimum(lo, pts.min(0)), np.maximum(hi, pts.max(0))
    c = (lo + hi) / 2
    return np.array([c[0], -2.9, c[2]]), max(hi[0] - lo[0], hi[2] - lo[2]) / 2 + 24.0


def scene(ex, t, cam, pal=PAL, muscles=True, equip=True, floor=None):
    """(J, prims, missing) for exercise ex at time t seen from cam; missing counts equipment that
    exists only for one camera. floor: (centre, radius) of the floor disc, or None for none."""
    from .rig import solve
    u = ex.phase(t)
    J = solve(ex.pose_fn(u))
    prims = figure(J, cam, ex.muscles if muscles else [], MUSCLE[ex.group], pal)
    missing = 0
    if equip and ex.equip:
        eprims, missing = equipment(ex.equip(J, _View(cam), u), cam, pal)
        prims += eprims
    if floor is not None:
        prims.insert(0, floor_prim(floor[0], floor[1], cam, pal))
    return J, prims, missing


def bounds3d(ex, samples=24):
    """(lo, hi) of everything the exercise sweeps through: the body and its equipment's 3D specs (as the
    app frames it from the rig's bounds)."""
    from .rig import solve
    from .export3d import _extent_points, body_extent_points
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    cam = Cam3(0.0, 0.0)
    for i in range(samples):
        u = ex.phase(ex.duration * i / samples)
        J = solve(ex.pose_fn(u))
        pts = body_extent_points(J)
        if ex.equip:
            for it in ex.equip(J, _View(cam), u):
                for e in getattr(it, 'spec3d', None) or []:
                    if e[-1] != 'back' and it.frame3d:   # backdrops (walls, water), a thrown ball may
                        pts += _extent_points(e)         # run off the picture
        pts = np.array(pts)
        lo, hi = np.minimum(lo, pts.min(0)), np.maximum(hi, pts.max(0))
    return lo, hi


def turn_canvas(bounds, cam, px, pal=PAL):
    """A canvas that keeps everything in frame at any yaw (and this pitch), as the app frames it."""
    from .sdf import Canvas
    lo, hi = bounds
    c = (lo + hi) / 2
    half = (hi - lo) / 2
    radius = math.hypot(half[0], half[2])
    ph = math.radians(abs(cam.pitch))
    half_h = half[1] * math.cos(ph) + radius * math.sin(ph)
    scale = min(px / (2 * radius * 1.04), px / (2 * half_h * 1.06))
    c2 = cam.p(c)
    return Canvas(px, px, scale, (px / 2 - c2[0] * scale, px / 2 + c2[1] * scale), pal['bg'])


def render(ex, t, cam, px=300, canvas=None, pal=PAL):
    cv = canvas if canvas is not None else ex.canvas_for(px, 'full', pal)
    J, prims, _ = scene(ex, t, cam, pal, floor=floor_disc(ex) if ex.floor else None)
    composite(cv, prims, pal['bg'])
    return cv.to_uint8()
