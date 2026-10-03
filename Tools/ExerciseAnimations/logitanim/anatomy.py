"""Muscle regions as small ellipsoids attached to the skeleton.

Each region lives in the frame of the bone (or torso) it belongs to, so it moves with it
continuously. A camera projects the ellipsoid to an exact 2D ellipse; regions whose surface
faces away from the camera shrink away smoothly instead of showing through. The painted
region is that ellipse clipped by the silhouette of the part that owns it.
"""
import math
import numpy as np

from .sdf import Ellipse
from .rig import unit
from .spec import TORSO

# Which regions each muscle group lights up by default. Exercises may override.
GROUP_REGIONS = {
    'chest': ['pecs'],
    'triceps': ['triceps'],
    'shoulders': ['delts'],
    'biceps': ['biceps'],
    'back': ['lats', 'traps'],
    'legs': ['quads', 'glutes'],
    'abdominals': ['abs', 'obliques'],
    'cardio': ['quads', 'calves'],
}

ALL_REGIONS = ['pecs', 'abs', 'obliques', 'lats', 'traps', 'erectors', 'glutes', 'delts', 'biceps', 'triceps',
               'forearms', 'quads', 'hamstrings', 'adductors', 'abductors', 'calves', 'hipflexors']


class Blob:
    """An ellipsoid: centre c, three orthogonal unit axes E (3x3 rows) with semi-axes a, and an
    outward normal n (None = visible from everywhere)."""

    def __init__(self, c, axes, radii, n, part):
        self.c = np.asarray(c, float)
        self.E = np.array([unit(e) for e in axes])
        self.a = np.asarray(radii, float)
        self.n = None if n is None else unit(n)
        self.part = part          # e.g. 'torso', 'armR', 'legL'


class Patch:
    """A flat region drawn on the body surface: 3D corner points (projected, then rounded)
    and an outward normal for visibility."""

    def __init__(self, pts, n, part, r=2.2):
        self.pts = [np.asarray(p, float) for p in pts]
        self.n = unit(n)
        self.part = part
        self.r = r


def _frame(d, front):
    d = unit(d)
    f = np.asarray(front, float) - np.dot(front, d) * d
    f = unit(f) if np.linalg.norm(f) > 1e-6 else unit(np.cross(d, [0, 0, 1.0]))
    c = unit(np.cross(d, f))
    return d, f, c


def blobs(J, names):
    """Ellipsoids for the requested region names."""
    out = []
    tf, pf = J.torso_frame, J.pelvis_frame
    P = J.p['pelvis']
    f, u, r = tf.f, tf.u, tf.r
    want = set(names)
    for s, sgn in (('L', -1.0), ('R', 1.0)):
        rs = r * sgn
        if 'pecs' in want:
            n = unit(f + rs * 0.35)
            out.append(Blob(P + u * 33.5 + f * 10.0 + rs * 7.8, [rs, u, f], [8.4, 6.4, 5.5], n, 'torso'))
        if 'obliques' in want:
            out.append(Blob(P + u * 14.0 + rs * 11.0 + f * 4.0, [u, f, rs], [8.5, 7.0, 5.0], unit(rs + f * 0.3), 'torso'))
        T = lambda a, b, c: P + f * a + u * b + rs * c
        if 'lats' in want:
            # armpit -> scapula tip -> lower back -> waist side: the V-wing seen from behind,
            # a band down the back seen from the side
            out.append(Patch([T(-2.0, 41.0, 16.5), T(-11.0, 37.0, 7.0), T(-12.0, 12.5, 3.2), T(-6.0, 19.0, 14.5)],
                             unit(-f * 0.6 + rs * 0.8), 'torso'))
        if 'erectors' in want:
            out.append(Patch([T(-7.5, 31.0, 2.2), T(-12.5, 31.0, 7.4), T(-12.5, 3.0, 7.2), T(-7.5, 3.0, 2.2)],
                             -f, 'torso', r=2.6))
        if 'glutes' in want:
            gp = pf
            n = unit(-gp.f + gp.r * sgn * 0.3)
            out.append(Blob(P - gp.u * 1.5 - gp.f * 7.5 + gp.r * sgn * 7.0, [gp.r, gp.u, gp.f], [7.6, 8.6, 6.0], n, 'hips'))

        # arms
        S, E, W = J.p['shoulder' + s], J.p['elbow' + s], J.p['hand' + s]
        b = J.v['biceps' + s]
        Lu = max(np.linalg.norm(E - S), 1.0)
        d, fr, c = _frame(E - S, b)
        if 'delts' in want:
            out.append(Blob(S + d * 3.2 + u * 0.8, [d, fr, c], [9.6, 7.6, 7.6], None, 'arm' + s))
        if 'biceps' in want:
            out.append(Blob(S + d * (0.56 * Lu) + fr * 2.4, [d, fr, c], [0.36 * Lu, 4.4, 4.8], fr, 'arm' + s))
        if 'triceps' in want:
            out.append(Blob(S + d * (0.5 * Lu) - fr * 2.4, [d, fr, c], [0.38 * Lu, 4.4, 5.0], -fr, 'arm' + s))
        if 'forearms' in want:
            Wr = J.p.get('wrist' + s, W)
            Lf = max(np.linalg.norm(Wr - E), 1.0)
            d2 = unit(Wr - E)
            # The elbow is a hinge, so the forearm's flexor face turns with it: from the biceps
            # side with the arm straight to facing the shoulder fully bent. Projecting the
            # biceps direction instead collapses at 90 degrees and flips the tint to the back.
            fr2 = unit(np.cross(np.cross(d, fr), d2))
            c2 = unit(np.cross(d2, fr2))
            out.append(Blob(E + d2 * (0.33 * Lf) + fr2 * 1.9, [d2, fr2, c2], [0.3 * Lf, 4.0, 4.4], fr2, 'fore' + s))

        # legs
        H, K, A = J.p['hip' + s], J.p['knee' + s], J.p['ankle' + s]
        a = J.v['thigh_front' + s]
        Lt = max(np.linalg.norm(K - H), 1.0)
        d, fr, c = _frame(K - H, a)
        lateral = unit(pf.r * sgn - np.dot(pf.r * sgn, d) * d)
        if 'quads' in want:
            out.append(Blob(H + d * (0.54 * Lt) + fr * 3.2, [d, fr, c], [0.42 * Lt, 6.0, 7.6], fr, 'leg' + s))
        if 'hamstrings' in want:
            out.append(Blob(H + d * (0.52 * Lt) - fr * 3.0, [d, fr, c], [0.4 * Lt, 5.8, 7.2], -fr, 'leg' + s))
        if 'adductors' in want:
            out.append(Blob(H + d * (0.4 * Lt) - lateral * 3.6, [d, lateral, fr], [0.33 * Lt, 4.8, 5.6], -lateral, 'leg' + s))
        if 'abductors' in want:
            out.append(Blob(H + d * (0.16 * Lt) + lateral * 4.4, [d, lateral, fr], [0.24 * Lt, 5.0, 6.0], lateral, 'leg' + s))
        if 'hipflexors' in want:
            out.append(Blob(H + d * (0.14 * Lt) + fr * 4.0, [d, fr, c], [0.2 * Lt, 4.4, 5.0], fr, 'leg' + s))
        if 'calves' in want:
            a_s = J.v['shank_front' + s]
            Ls = max(np.linalg.norm(A - K), 1.0)
            d, fr, c = _frame(A - K, a_s)
            out.append(Blob(K + d * (0.32 * Ls) - fr * 2.8, [d, fr, c], [0.27 * Ls, 4.8, 5.8], -fr, 'shin' + s))
    if 'abs' in want:
        out.append(Blob(P + u * 16.0 + f * 10.5, [u, r, f], [10.5, 6.6, 5.5], f, 'torso'))
    if 'traps' in want:
        T = lambda a, b, c: P + f * a + u * b + r * c
        # the upper edge rides on the shoulder girdle, so a shrug lifts it (the lower tip stays)
        girdle = (J.p['shoulderL'] + J.p['shoulderR']) / 2 - P
        shrug = float(np.dot(girdle, u)) - TORSO
        protract = float(np.dot(girdle, f))
        top = TORSO + 5.5 + shrug
        out.append(Patch([T(-6.0 + protract, top, -14.0), T(-6.0 + protract, top, 14.0), T(-11.0, TORSO - 20.0, 2.5),
                          T(-11.0, TORSO - 20.0, -2.5)], unit(-f + u * 0.25), 'torso', r=3.0))
    return out


def project_patch(patch, cam):
    from .sdf import Poly
    view = {'side': np.array([0, 0, 1.0]), 'front': np.array([1.0, 0, 0]),
            'back': np.array([-1.0, 0, 0]), 'top': np.array([0, 1.0, 0])}[cam.kind]
    nd = float(np.dot(patch.n, view))
    x = min(max((nd + 0.55) / 0.4, 0.0), 1.0)
    vis = x * x * (3 - 2 * x)
    if vis <= 0.02:
        return None
    pts = np.array([cam.p(p) for p in patch.pts])
    c = pts.mean(axis=0)
    pts = c + (pts - c) * vis
    return Poly(pts, r=patch.r * vis)


def project(blob, cam):
    """2D ellipse (centre, rx, ry, angle) scaled by visibility, or None when hidden."""
    if cam.kind == 'side':
        M = np.array([[1.0, 0, 0], [0, 1.0, 0]])
        view = np.array([0, 0, 1.0])
    elif cam.kind == 'front':
        M = np.array([[0, 0, -1.0], [0, 1.0, 0]])
        view = np.array([1.0, 0, 0])
    elif cam.kind == 'back':
        M = np.array([[0, 0, 1.0], [0, 1.0, 0]])
        view = np.array([-1.0, 0, 0])
    else:
        M = np.array([[1.0, 0, 0], [0, 0, -1.0]])
        view = np.array([0, 1.0, 0])
    vis = 1.0
    if blob.n is not None:
        nd = float(np.dot(blob.n, view))
        x = min(max((nd + 0.55) / 0.4, 0.0), 1.0)
        vis = x * x * (3 - 2 * x)
    if vis <= 0.02:
        return None
    ME = M @ (blob.E.T * blob.a)            # 2x3: columns = projected scaled axes
    Q = ME @ ME.T
    w, vecs = np.linalg.eigh(Q)
    w = np.maximum(w, 1e-6)
    c2 = M @ blob.c
    # eigh returns ascending eigenvalues
    rx, ry = math.sqrt(w[1]) * vis, math.sqrt(w[0]) * vis
    angle = math.atan2(vecs[1, 1], vecs[0, 1])
    return Ellipse(c2, max(rx, 0.05), max(ry, 0.05), angle)
