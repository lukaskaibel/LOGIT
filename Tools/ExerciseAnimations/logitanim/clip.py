"""3D checks: does any part of the figure pass through equipment, the floor or another part of
itself, and does the movement hold together?

The figure is modelled as capsules and spheres a little slimmer than it is drawn, so only real
overlaps count; equipment helpers attach the 3D volumes of what they draw (Item.collider). Hands
may close around anything marked grip=True (bars, handles). Contact is fine; what's reported is
penetration beyond a tolerance, per pair, at the frame where it's deepest. Besides:
  reach  a hand or foot that doesn't get to its target (the IK clamps an unreachable one: the limb
         goes straight and the hand hangs short of the bar)
  cross  a right limb on the left of its twin (left and right swapped or crossed over)
  slide  a foot, knee or hand resting on the floor that slides along it
  sunk   equipment reaching below the floor
"""
import math

import numpy as np

from .rig import unit

# (part a, part b) that are joined, so overlap between them is the joint itself
ADJACENT = {('torso', 'head'), ('torso', 'upperL'), ('torso', 'upperR'), ('torso', 'thighL'), ('torso', 'thighR'),
            ('upperL', 'foreL'), ('upperR', 'foreR'), ('foreL', 'handL'), ('foreR', 'handR'),
            ('thighL', 'shankL'), ('thighR', 'shankR'), ('shankL', 'footL'), ('shankR', 'footR'),
            ('thighL', 'thighR')}
TOL_SELF = 3.0      # cm a part may press into another (hands on hips, knees to chest)
TOL_EQUIP = 2.0     # cm a part may press into a pad or rest on a bar
TOL_FLOOR = 1.5
TOL_REACH = 1.0     # cm a hand or foot may miss its target
TOL_CROSS = 2.0     # cm a right joint may pass to the left of its twin (hands on one handle meet)
TOL_SLIDE = 0.8     # cm a resting contact may drift along the floor between samples (15 fps)
TOL_SUNK = 2.0      # cm equipment may reach below the floor (the drawn floor line starts 2 cm down)
REST = 2.5          # a contact point this close to the floor (cm, beyond its own radius) rests on it


def body(J):
    P = J.p
    up = unit(P['shoulder_c'] - P['pelvis'])
    parts = {'torso': ('capsule', P['pelvis'] + up * 6.0, P['shoulder_c'] - up * 8.0, 10.0),
             'head': ('sphere', P['head'], 10.5)}
    for s in 'LR':
        parts['upper' + s] = ('capsule', P['shoulder' + s], P['elbow' + s], 5.0)
        # the forearm stops at the wrist, so a bar closed in the fist doesn't count against it
        e, w = P['elbow' + s], P.get('wrist' + s, P['hand' + s])
        wrist = w - unit(w - e) * (0.0 if 'wrist' + s in P else 5.0)
        parts['fore' + s] = ('capsule', e, wrist, 4.2)
        parts['hand' + s] = ('sphere', P['hand' + s], 4.3)
        parts['thigh' + s] = ('capsule', P['hip' + s], P['knee' + s], 7.0)
        parts['shank' + s] = ('capsule', P['knee' + s], P['ankle' + s], 5.2)
        parts['foot' + s] = ('capsule', P['heel' + s], P['toe' + s], 3.2)
    return parts


# ---- signed distances ----------------------------------------------------------------------

def _seg_points(a, b, n=9):
    return [a + (b - a) * (i / (n - 1)) for i in range(n)]


def _pt_seg(p, a, b):
    ab = b - a
    t = float(np.clip(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12), 0, 1))
    return float(np.linalg.norm(p - (a + ab * t)))


def _seg_seg(a0, a1, b0, b1):
    """Closest distance between segments (a0,a1) and (b0,b1)."""
    d1, d2, r = a1 - a0, b1 - b0, a0 - b0
    a, e, f = np.dot(d1, d1), np.dot(d2, d2), np.dot(d2, r)
    if a < 1e-12 and e < 1e-12:
        return float(np.linalg.norm(r))
    if a < 1e-12:
        s, t = 0.0, np.clip(f / e, 0, 1)
    else:
        c = np.dot(d1, r)
        if e < 1e-12:
            t, s = 0.0, np.clip(-c / a, 0, 1)
        else:
            b = np.dot(d1, d2)
            den = a * e - b * b
            s = np.clip((b * f - c * e) / den, 0, 1) if den > 1e-12 else 0.0
            t = (b * s + f) / e
            if t < 0:
                t, s = 0.0, np.clip(-c / a, 0, 1)
            elif t > 1:
                t, s = 1.0, np.clip((b - c) / a, 0, 1)
    return float(np.linalg.norm((a0 + d1 * s) - (b0 + d2 * t)))


def _sdf(p, col):
    """Signed distance from point p to a collider's surface (negative inside)."""
    kind = col[0]
    if kind == 'sphere':
        return float(np.linalg.norm(p - col[1])) - col[2]
    if kind == 'capsule':
        return _pt_seg(p, col[1], col[2]) - col[3]
    if kind == 'cylinder':
        c, ax, r, h = col[1], unit(col[2]), col[3], col[4]
        v = p - c
        y = float(np.dot(v, ax))
        x = float(np.linalg.norm(v - ax * y))
        dx, dy = x - r, abs(y) - h
        return min(max(dx, dy), 0.0) + math.hypot(max(dx, 0.0), max(dy, 0.0))
    if kind == 'box':
        c, axes, half = col[1], col[2], col[3]
        v = p - c
        q = np.array([abs(float(np.dot(v, unit(a)))) - h for a, h in zip(axes, half)])
        return float(np.linalg.norm(np.maximum(q, 0.0))) + min(float(q.max()), 0.0)
    raise ValueError(kind)


def penetration(part, col):
    """How deep `part` (a body capsule/sphere) reaches into `col` (cm; <= 0: no overlap)."""
    if part[0] == 'sphere':
        return part[2] - _sdf(part[1], col)
    a, b, r = part[1], part[2], part[3]
    if col[0] == 'capsule':
        return (r + col[3]) - _seg_seg(a, b, col[1], col[2])
    if col[0] == 'sphere':
        return (r + col[2]) - _pt_seg(col[1], a, b)
    return r - min(_sdf(p, col) for p in _seg_points(a, b))


def colliders(item):
    col = getattr(item, 'collider', None)
    if col is None:
        return []
    return col if isinstance(col, list) else [col]


def check_frame(J, items, floor=True):
    """[(kind, a, b, depth_cm)] beyond tolerance in one frame."""
    parts = body(J)
    out = []
    names = sorted(parts)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if (a, b) in ADJACENT or (b, a) in ADJACENT:
                continue
            pa, pb = parts[a], parts[b]
            if pb[0] == 'capsule' and pa[0] != 'capsule':
                pa, pb = pb, pa
            d = penetration(pa, pb)
            if d > TOL_SELF:
                out.append(('self', a, b, d))
    for it in items:
        for col in colliders(it):
            for a, part in parts.items():
                if a.startswith('hand') and getattr(it, 'grip', False):
                    continue
                d = penetration(part, col)
                tol = TOL_EQUIP + (1.0 if a.startswith('hand') or a.startswith('fore') else 0.0)
                if d > tol:
                    out.append(('equip', a, col[0], d))
    if floor:
        for a, part in parts.items():
            if part[0] == 'sphere':
                low = part[1][1] - part[2]
            else:
                low = min(part[1][1], part[2][1]) - part[3]
            if low < -TOL_FLOOR:
                out.append(('floor', a, 'floor', -low))
    return out


def lowest(col):
    """The lowest point (y) of a collider."""
    kind = col[0]
    if kind == 'sphere':
        return col[1][1] - col[2]
    if kind == 'capsule':
        return min(col[1][1], col[2][1]) - col[3]
    if kind == 'cylinder':
        c, ax, r, h = col[1], unit(col[2]), col[3], col[4]
        return c[1] - h * abs(ax[1]) - r * math.sqrt(max(0.0, 1.0 - ax[1] ** 2))
    c, axes, half = col[1], col[2], col[3]
    return c[1] - sum(abs(unit(a)[1]) * h for a, h in zip(axes, half))


def reach_misses(pose, J):
    """{hand/foot: cm} how far each targeted hand or foot ends up from its target."""
    out = {}
    for s in 'LR':
        a = pose.get('arm' + s, {})
        if 'hand' in a:
            got = J.p['wrist' + s] if 'wrist_flex' in a else J.p['hand' + s]
            out['hand' + s] = float(np.linalg.norm(got - np.asarray(a['hand'], float)))
        lg = pose.get('leg' + s, {})
        if 'foot' in lg:
            out['foot' + s] = float(np.linalg.norm(J.p['ankle' + s] - np.asarray(lg['foot'], float)))
    return out


def crossings(J):
    """{joint: cm} how far each right joint lies on the left of its twin (arms judged across the
    torso, legs across the pelvis)."""
    out = {}
    for joints, frame in ((('elbow', 'hand'), J.torso_frame), (('knee', 'ankle', 'heel', 'toe'), J.pelvis_frame)):
        for j in joints:
            gap = float(np.dot(J.p[j + 'R'] - J.p[j + 'L'], frame.r))
            if gap < 0:
                out[j] = -gap
    return out


# contact points that may rest on the floor, with their radius in the body model
CONTACTS = [(k + s, r) for s in 'LR' for k, r in (('heel', 3.2), ('toe', 3.2), ('knee', 5.2), ('hand', 4.3))]


def check(ex, fps=15):
    """Worst finding per (kind, a, b) over the loop: {key: (cm, time)}."""
    worst = {}

    def note(key, d, t):
        if key not in worst or d > worst[key][0]:
            worst[key] = (d, t)

    n = max(1, int(round(ex.duration * fps)))
    prev = None
    for i in range(n + 1):                  # one sample past the end: the loop's seam slides too
        t = ex.duration * (i % n) / n
        J, v, items = ex.state(t)
        if i < n:
            for kind, a, b, d in check_frame(J, items, floor=ex.floor):
                note((kind, a, b), d, t)
            for limb, d in reach_misses(ex.pose_fn(ex.phase(t)), J).items():
                if d > TOL_REACH:
                    note(('reach', limb, 'target'), d, t)
            for j, d in crossings(J).items():
                if d > TOL_CROSS:
                    note(('cross', j + 'R', j + 'L'), d, t)
            if ex.floor:
                for it in items:
                    for col in colliders(it):
                        d = -lowest(col)
                        if d > TOL_SUNK:
                            note(('sunk', col[0], 'floor'), d, t)
        if ex.floor:
            now = {k: J.p[k] for k, r in CONTACTS if J.p[k][1] - r < REST}
            if prev is not None:
                for k, p in now.items():
                    if k in prev:
                        d = float(np.hypot(p[0] - prev[k][0], p[2] - prev[k][2]))
                        if d > TOL_SLIDE:
                            note(('slide', k, 'floor'), d, t)
            prev = now
    return worst
