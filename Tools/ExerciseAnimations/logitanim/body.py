"""Silhouettes for a solved skeleton, per camera, plus the muscle overlays for each layer.

Cameras: 'side' (from the figure's right, the figure faces screen-right), 'front', 'back'.
The silhouettes follow the SF Symbols figure language: detached round head, rounded limbs,
and a knockout gap wherever a part passes in front of another.
"""
import math
import numpy as np

from .sdf import V, Circle, Cone, Union, Intersect, Poly
from .spec import (R_THIGH, R_SHANK, R_UPPER, R_FORE, R_HAND, R_HEEL, R_TOE, R_HEAD,
                   R_THIGH_F, R_SHANK_F, GAP)
from . import anatomy

SIDES = ('L', 'R')


def unit2(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def perp(d):
    return V(-d[1], d[0])


class Camera:
    def __init__(self, kind):
        self.kind = kind

    def p(self, v):
        v = np.asarray(v, float)
        if self.kind == 'side':
            return V(v[0], v[1])
        if self.kind == 'front':
            return V(-v[2], v[1])
        if self.kind == 'back':
            return V(v[2], v[1])
        return V(v[0], -v[2])

    d = p

    def depth(self, v):
        v = np.asarray(v, float)
        return {'side': v[2], 'front': v[0], 'back': -v[0], 'top': v[1]}[self.kind]


class Layer:
    """One piece of the figure in the paint order. depth: how near the camera it is (cam.depth of a
    representative point), used to slot depth-sorted equipment in between. partner: for the second
    half of a limb, (the first half's layer name, s) where s is how far this half lies in front."""

    def __init__(self, name, shape, gap=0.0, anchor=None, r0=0.0, r1=0.0, depth=0.0, anchors=(), partner=None):
        self.name, self.shape, self.gap = name, shape, gap
        self.anchor, self.r0, self.r1 = anchor, r0, r1
        self.depth, self.anchors, self.partner = depth, list(anchors), partner


# A limb's two halves (upper arm / forearm+hand, thigh / shank+foot) are ordered by depth. The
# half that is this much nearer the camera starts to cover the other (s = 0) ... fully (s = 1).
# The range is short on purpose: in motion it's a fade over a few frames, and a pose held inside
# it would show the other half's highlight half-transparent through this one.
SPLIT_NEAR, SPLIT_FULL = 2.5, 4.0
# Front and back views: an arm whose forearm lies this much nearer or farther than the middle of
# the torso (cm, as the camera sees it: in front of the chest seen from behind, say) is drawn
# behind the torso. Exercise.behind_weights times the switches over the loop (see there).
BEHIND = 14.0


def smooth01(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def occlusion(lead):
    return smooth01((lead - SPLIT_NEAR) / (SPLIT_FULL - SPLIT_NEAR))


def limb_layers(cam, J, P, prox_name, dist_name, prox, dist, j0, j1, j2, gap=0.0, anchor=None, r0=0.0, r1=0.0,
                joint_r=(6.0, 11.0), dist_slot=None):
    """A limb as two layers in depth order: prox (upper arm, thigh) from joint j0 to j1, dist (forearm
    and hand, shank and foot) from j1 to j2. gap/anchor: the limb's own knockout against what lies
    behind it, as for a whole limb. Whichever half is nearer is painted second, cutting a band into
    the other only as far as it really lies in front (tapered away at the joint between them).

    Each layer's depth (where depth-sorted equipment slots in) is its midpoint's, except that
    dist_slot overrides the distal half's: an arm's is its hand, so a bar held in the fist slots
    in just behind the fist, however the forearm is angled."""
    a, b, c = J.p[j0], J.p[j1], J.p[j2]
    d_prox, d_dist = cam.depth((a + b) / 2), cam.depth((b + c) / 2)
    slot = {prox_name: d_prox, dist_name: d_dist if dist_slot is None else dist_slot}
    joint = (P(j1), joint_r[0], joint_r[1])
    if d_dist >= d_prox:
        first = Layer(prox_name, prox, gap, anchor, r0, r1, depth=slot[prox_name])
        second_name, second_shape, lead = dist_name, dist, d_dist - d_prox
    else:
        first = Layer(dist_name, dist, gap, anchor, r0, r1, depth=slot[dist_name])
        second_name, second_shape, lead = prox_name, prox, d_prox - d_dist
    s = occlusion(lead)
    # the nearer half cuts its band into anything behind it: the limb's own gap against the body,
    # and against its partner as far as s says (the partner restores the rest)
    g2 = max(gap, GAP * s) if gap > 0 else GAP * s
    anchors = [joint]
    if anchor is not None and gap > 0 and second_name == prox_name:
        anchors.append((anchor, r0, r1))        # the upper half still grows out of the body
    second = Layer(second_name, second_shape, g2, depth=max(first.depth, slot[second_name]), anchors=anchors,
                   partner=(first.name, s))
    return [first, second]


def by_depth(layers):
    """Limb halves from several limbs in one depth order (stable, so each limb's nearer half, whose
    depth is never below its partner's, still follows it)."""
    return sorted(layers, key=lambda layer: layer.depth)


class View:
    """Layers to paint back-to-front, the clip shape for each region owner, and 2D points."""

    def __init__(self, cam):
        self.cam = cam
        self.layers = []
        self.variants = None    # [(weight, layers)]: paint each and blend (a limb mid-way between orders)
        self.clip = {}          # region owner ('torso', 'hips', 'armL', ...) -> shape
        self.paint_on = {}      # region owner -> [layer names that carry its overlays]
        self.pts = {}
        self.silhouette = None

    def overlays(self, J, names, color):
        """{layer name: [(region shape, colour, alpha)]} for the requested regions."""
        out = {}
        if not names:
            return out
        for blob in anatomy.blobs(J, names):
            if isinstance(blob, anatomy.Patch):
                e = anatomy.project_patch(blob, self.cam)
            else:
                e = anatomy.project(blob, self.cam)
            if e is None or blob.part not in self.clip:
                continue
            reg = Intersect(e, self.clip[blob.part])
            for layer in self.paint_on.get(blob.part, []):
                out.setdefault(layer, []).append((reg, color, 1.0))
        return out


def _limbs(J, cam, P, frontal):
    rt, rs = (R_THIGH_F, R_SHANK_F) if frontal else (R_THIGH, R_SHANK)
    legs, arms = {}, {}
    for s in SIDES:
        thigh = Cone(P('hip' + s), P('knee' + s), *rt)
        shank = Cone(P('knee' + s), P('ankle' + s), *rs)
        if frontal:
            n = cam.d(J.v['foot_n' + s])
            ank = P('ankle' + s)
            fc = ank - unit2(n) * 2.4 if np.linalg.norm(n) > 0.3 else ank + V(0, -2.4)
            foot = Circle(fc, 4.9)
        else:
            foot = Cone(P('heel' + s), P('toe' + s), R_HEEL, R_TOE)
        legs[s] = (thigh, Union([shank, foot]), Union([thigh, shank, foot]))
        upper = Cone(P('shoulder' + s), P('elbow' + s), *R_UPPER)
        w = P('hand' + s)
        if J.style['hand' + s] == 'palm':
            fore = Cone(P('elbow' + s), w, R_FORE[0], 4.0)
            if frontal:
                hand = Circle(w + V(0, -1.2), 3.9)
            else:
                pd = unit2(cam.d(J.v['palm' + s]))
                hand = Cone(w + V(0, -1.3) + pd * 0.6, w + V(0, -2.3) + pd * 9.6, 3.1, 2.1)
        elif 'wrist' + s in J.p:
            wr = P('wrist' + s)
            fore = Cone(P('elbow' + s), wr, R_FORE[0], R_FORE[1])
            hand = Union([Cone(wr, w, R_FORE[1], R_HAND - 0.4), Circle(w, R_HAND - 0.4)])
        else:
            fore = Cone(P('elbow' + s), w, *R_FORE)
            hand = Circle(w, R_HAND)
        arms[s] = (upper, Union([fore, hand]), Union([upper, fore, hand]))
    return legs, arms


def arm_layers(cam, J, P, s, gap=0.0, anchor=None, r0=0.0, r1=0.0, arms=None):
    return limb_layers(cam, J, P, 'arm' + s, 'fore' + s, arms[s][0], arms[s][1],
                       'shoulder' + s, 'elbow' + s, 'hand' + s, gap, anchor, r0, r1, joint_r=(6.0, 11.0),
                       dist_slot=cam.depth(J.p['hand' + s]))


def leg_layers(cam, J, P, s, gap=0.0, anchor=None, r0=0.0, r1=0.0, legs=None):
    return limb_layers(cam, J, P, 'leg' + s, 'shin' + s, legs[s][0], legs[s][1],
                       'hip' + s, 'knee' + s, 'ankle' + s, gap, anchor, r0, r1, joint_r=(8.0, 13.0))


def side_view(J, near_arm_behind=False):
    """near_arm_behind: True puts the whole near arm behind the body and head (a hand tucked in
    behind the back); 'forearm' only its forearm and hand, behind the head (hands laced behind the
    head: the upper arm is on the camera side of the body, so it stays in front)."""
    cam = Camera('side')
    P = lambda k: cam.p(J.p[k])
    tf = J.torso_frame
    P2 = cam.p(J.p['pelvis'])
    u2 = unit2(cam.d(tf.u))
    if np.linalg.norm(cam.d(tf.u)) < 0.25:
        u2 = unit2(cam.d(tf.u) + cam.d(tf.f) * 0.01)
    f2 = V(u2[1], -u2[0])
    if np.dot(f2, cam.d(tf.f)) < 0:
        f2 = -f2
    T = lambda a, b: P2 + f2 * a + u2 * b

    # the side nearer the camera is drawn in front
    near, far = ('R', 'L') if cam.depth(J.p['shoulderR']) >= cam.depth(J.p['shoulderL']) else ('L', 'R')
    chest = Cone(T(1.2, 41.8), T(1.2, 24), 12.9, 11.6)
    belly = Cone(T(1.2, 24), T(0.4, 6.5), 11.6, 12.2)
    glute = Circle(T(-2.6, 1.0), 10.8)
    cap = Circle(P('shoulder' + near), R_UPPER[0])
    torso = Union([chest, belly, glute, cap], k=4.0)
    legs, arms = _limbs(J, cam, P, frontal=False)
    head = Circle(P('head'), R_HEAD)
    base = Union([torso, legs[near][2]], k=3.0)

    d_t = unit2(P('knee' + near) - P('hip' + near))
    flex = math.degrees(math.acos(float(np.clip(np.dot(d_t, -u2), -1, 1))))
    x = min(max((flex - 35.0) / 35.0, 0.0), 1.0)
    leg_gap = GAP * x * x * (3 - 2 * x)

    v = View(cam)
    v.T, v.u2, v.f2 = T, u2, f2
    Ls = v.layers
    dep = lambda k: cam.depth(J.p[k])
    Ls += arm_layers(cam, J, P, far, arms=arms)
    Ls.append(Layer('leg' + far, legs[far][2], GAP, P('hip' + far), 10.5, 15.0, depth=dep('knee' + far)))
    if near_arm_behind is True:
        Ls += arm_layers(cam, J, P, near, arms=arms)
    Ls.append(Layer('base', base, GAP, depth=cam.depth(J.p['pelvis'] + tf.u * 25)))
    Ls.append(Layer('leg' + near, legs[near][2], leg_gap, P('hip' + near), 10.5, 15.0, depth=dep('knee' + near)))
    if near_arm_behind == 'forearm':
        Ls.append(Layer('fore' + near, arms[near][1], depth=dep('hand' + near)))
    Ls.append(Layer('head', head, GAP, depth=dep('head')))
    if near_arm_behind == 'forearm':
        # the upper arm comes out from behind the head's edge at the elbow without a seam
        Ls.append(Layer('arm' + near, arms[near][0], GAP, P('shoulder' + near), 7.5, 12.0,
                        depth=cam.depth((J.p['shoulder' + near] + J.p['elbow' + near]) / 2),
                        anchors=[(P('elbow' + near), 6.0, 11.0)]))
    elif not near_arm_behind:
        Ls += arm_layers(cam, J, P, near, GAP, P('shoulder' + near), 7.5, 12.0, arms=arms)
    v.clip = {'torso': torso, 'hips': base}
    v.paint_on = {'torso': ['base'], 'hips': ['base', 'leg' + near]}
    for s in SIDES:
        # arms come in two halves; legs stay whole side-on (both halves swing in the same plane)
        v.clip['arm' + s], v.paint_on['arm' + s] = arms[s][0], ['arm' + s]
        v.clip['fore' + s], v.paint_on['fore' + s] = arms[s][1], ['fore' + s]
        legs_on = ['base', 'leg' + s] if s == near else ['leg' + s]
        v.clip['leg' + s], v.paint_on['leg' + s] = legs[s][2], legs_on
        v.clip['shin' + s], v.paint_on['shin' + s] = legs[s][2], legs_on
    v.silhouette = Union([base, legs[far][2], arms[near][2], arms[far][2], head])
    v.pts = {k: cam.p(p) for k, p in J.p.items()}
    return v


def behind_margins(J, cam):
    """Front and back views: how far each arm is from being drawn behind the torso (cm; negative =
    behind), from its forearm's middle."""
    tdepth = cam.depth(J.p['pelvis'] + J.torso_frame.u * 30)
    return {s: cam.depth((J.p['elbow' + s] + J.p['hand' + s]) / 2) - (tdepth - BEHIND) for s in SIDES}


def frontal_view(J, kind='front', behind=None):
    """behind: {side: weight} of each arm being drawn behind the torso (1 = behind). In between, the
    frame is painted both ways and blended (View.variants): an arm crossing over dissolves instead
    of popping. Default: behind when behind_margins says so."""
    cam = Camera(kind)
    P = lambda k: cam.p(J.p[k])
    tf = J.torso_frame
    P2 = cam.p(J.p['pelvis'])
    u2 = unit2(cam.d(tf.u))
    l2 = V(u2[1], -u2[0])
    if l2[0] < 0:
        l2 = -l2
    T = lambda a, b: P2 + l2 * a + u2 * b
    sl, sr = sorted([P('shoulderL'), P('shoulderR')], key=lambda p: float(np.dot(p - P2, l2)))
    top = float(np.dot((sl + sr) / 2 - P2, u2))
    yoke = Cone(sl + l2 * 1.5 + u2 * 0.3, sr - l2 * 1.5 + u2 * 0.3, 6.8, 6.8)
    core = Poly([T(-16.6, top - 2.0), T(16.6, top - 2.0), T(12.0, -5.5), T(-12.0, -5.5)], r=3.0)
    torso = Union([yoke, core], k=7.0)
    tdepth = cam.depth(J.p['pelvis'] + tf.u * 30)
    legs, arms = _limbs(J, cam, P, frontal=True)
    head = Circle(P('head'), R_HEAD)

    front_legs = [s for s in SIDES if cam.depth(J.p['knee' + s]) > tdepth + 18]
    base_legs = [legs[s][2] for s in SIDES if s not in front_legs]
    base = Union([torso, Union(base_legs)], k=4.0) if base_legs else torso

    v = View(cam)
    v.T, v.u2, v.l2 = T, u2, l2

    def layers_for(behind):
        Ls = by_depth([layer for s in behind for layer in arm_layers(cam, J, P, s, arms=arms)])
        Ls.append(Layer('base', base, GAP, depth=tdepth))
        for s in sorted(front_legs, key=lambda s: cam.depth(J.p['knee' + s])):
            Ls += leg_layers(cam, J, P, s, GAP, P('hip' + s), 10.5, 15.0, legs=legs)
        Ls.append(Layer('head', head, GAP, depth=cam.depth(J.p['head'])))
        Ls += by_depth([layer for s in SIDES if s not in behind
                        for layer in arm_layers(cam, J, P, s, GAP, P('shoulder' + s), 7.5, 12.0, arms=arms)])
        return Ls

    if behind is None:
        m = behind_margins(J, cam)
        behind = {s: 1.0 if m[s] < 0 else 0.0 for s in SIDES}
    options = []
    for s in SIDES:
        w = behind[s]
        options.append([(True, w), (False, 1.0 - w)] if 1e-3 < w < 1 - 1e-3 else [(w >= 0.5, 1.0)])
    variants = []
    for bl, wl in options[0]:
        for br, wr in options[1]:
            variants.append((wl * wr, layers_for([s for s, b in zip(SIDES, (bl, br)) if b])))
    v.layers = max(variants, key=lambda wv: wv[0])[1]
    v.variants = variants if len(variants) > 1 else None
    v.clip = {'torso': torso, 'hips': base}
    v.paint_on = {'torso': ['base'], 'hips': ['base']}
    for s in SIDES:
        v.clip['arm' + s], v.paint_on['arm' + s] = arms[s][0], ['arm' + s]
        v.clip['fore' + s], v.paint_on['fore' + s] = arms[s][1], ['fore' + s]
        if s in front_legs:
            v.clip['leg' + s], v.paint_on['leg' + s] = legs[s][0], ['leg' + s]
            v.clip['shin' + s], v.paint_on['shin' + s] = legs[s][1], ['shin' + s]
        else:
            v.clip['leg' + s], v.paint_on['leg' + s] = legs[s][2], ['base']
            v.clip['shin' + s], v.paint_on['shin' + s] = legs[s][2], ['base']
    v.silhouette = Union([base, head] + [arms[s][2] for s in SIDES] + [legs[s][2] for s in front_legs])
    v.pts = {k: cam.p(p) for k, p in J.p.items()}
    return v


def view(J, camera, **kw):
    if camera == 'side':
        return side_view(J, **kw)
    return frontal_view(J, camera, **kw)
