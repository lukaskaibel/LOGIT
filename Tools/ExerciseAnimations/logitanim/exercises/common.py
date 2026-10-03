"""Shared building blocks for exercise definitions: stances, holds, helpers."""
import math
import numpy as np

from ..spec import (SHANK, THIGH, TORSO, UPPER, FORE, FORE_WRIST, ANKLE_H, HIP_H, HIP_HALF,
                    SHOULDER_HALF, R_TOE)
from ..rig import v3, unit, ik2
from ..motion import (merge, keys, blend, rep, rep_down_first, Timeline, Cycle, smooth, lerp, ease)
from ..scene import exercise, Item
from ..sdf import V, Circle, Cone, RBox, Union, Poly, Ellipse, Subtract, Intersect
from .. import equipment as eq

X = np.array([1.0, 0, 0])
Y = np.array([0, 1.0, 0])
Z = np.array([0, 0, 1.0])
SH_Y = HIP_H + TORSO          # shoulder height standing tall
ARM = UPPER + FORE            # shoulder -> grip, straight


def reach_limit(make, lo, hi, tol=0.3, n=30):
    """The largest x in [lo, hi] at which the pose make(x) still gets every targeted hand and foot to
    its target (within tol cm), for make(lo) reaching and make(hi) possibly not. Use it where
    equipment sets the path (a lever's arc, a bar pivoting on the floor): the movement ends where
    the arms run out, so what's held never has to stretch or shrink to meet the hands."""
    from ..rig import solve
    from ..clip import reach_misses

    def ok(x):
        p = make(x)
        return max(reach_misses(p, solve(p)).values(), default=0.0) <= tol

    if ok(hi):
        return hi
    a, b = lo, hi
    for _ in range(n):
        m = (a + b) / 2
        a, b = (m, b) if ok(m) else (a, m)
    return a


def feet(x=0.0, half=11.0, toe_out=8.0, pitch=0.0, pole=None, y=ANKLE_H):
    """Both feet flat on the floor, ankles at x, half-stance apart."""
    out = {}
    for s, sg in (('L', -1), ('R', 1)):
        out['leg' + s] = {'foot': v3(x, y, sg * half), 'toe_out': toe_out, 'foot_pitch': pitch,
                          'pole': np.array(pole if pole is not None else [1.0, 0.0, 0.25 * sg])}
    return out


def arms_ik(hand_l, hand_r, pole_l=None, pole_r=None, palm=False, palm_dir=None):
    out = {}
    for s, h, p in (('L', hand_l, pole_l), ('R', hand_r, pole_r)):
        d = {'hand': np.asarray(h, float)}
        if p is not None:
            d['pole'] = np.asarray(p, float)
        if palm:
            d['palm'] = True
            d['palm_dir'] = np.asarray(palm_dir if palm_dir is not None else X, float)
        out['arm' + s] = d
    return out


def mirror(p3):
    p = np.array(p3, float)
    p[2] = -p[2]
    return p


def both(hand_r, pole_r=None, **kw):
    """Symmetric arms from the right-hand target."""
    pl = None if pole_r is None else mirror(pole_r)
    return arms_ik(mirror(hand_r), hand_r, pl, pole_r, **kw)


def standing(x=0.0, half=11.0, toe_out=8.0, bend=0.6, pitch=0.0, hands=None, arm_pole=None, **extra):
    """Standing tall over the ankles. hands: right-hand target (mirrored) or None for hanging."""
    pose = {'pelvis': v3(x + 0.5, HIP_H - bend, 0.0), 'pitch': pitch}
    pose.update(feet(x, half, toe_out))
    if hands is None:
        hands = v3(x + 2.0, SH_Y - ARM + 1.0, SHOULDER_HALF + 3.5)
        arm_pole = arm_pole if arm_pole is not None else [-1.0, 0.0, 0.3]
    pose.update(both(hands, arm_pole))
    pose.update(extra)
    return pose


def hip_hinge_pelvis(ankle_x, knee_deg, hip_back):
    """Pelvis position for a hinge: knees bent by `knee_deg` (shin forward), hips pushed back."""
    pass


def solve_torso_for(point_local, pelvis, target_x, lo=-60.0, hi=100.0):
    """Torso pitch (deg) so that the torso-local point (forward, up) lands at world x = target_x."""
    a, b = point_local
    for _ in range(60):
        mid = (lo + hi) / 2
        th = math.radians(mid)
        x = pelvis[0] + math.sin(th) * b + math.cos(th) * a
        if x < target_x:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def torso_point(pelvis, pitch, a, b):
    th = math.radians(pitch)
    u = v3(math.sin(th), math.cos(th))
    f = v3(math.cos(th), -math.sin(th))
    return np.asarray(pelvis, float) + f * a + u * b


def shoulder_at(pelvis, pitch):
    return torso_point(pelvis, pitch, 0.0, TORSO)


def bar_items(v, c3, **kw):
    return eq.barbell(v, c3, **kw)


# ---- postures -----------------------------------------------------------------------------

BENCH_H = 45.0       # flat bench pad top


def seated(x=0.0, seat_h=BENCH_H, hands=None, arm_pole=None, pitch=0.0, half=12.0, shin=0.0, **extra):
    """Sitting upright on a seat: thighs level, shins down to flat feet."""
    P = v3(x, seat_h + 9.0, 0.0)
    knee_x = x + THIGH * 0.99
    ank_x = knee_x + SHANK * math.sin(math.radians(shin))
    pose = {'pelvis': P, 'pitch': pitch}
    pose.update(feet(ank_x, half, 8.0))
    if hands is None:
        sh = shoulder_at(P, pitch)
        hands = v3(sh[0] + 8.0, sh[1] - ARM + 6.0, SHOULDER_HALF + 4.0)
        arm_pole = arm_pole if arm_pole is not None else [-1.0, 0.0, 0.3]
    pose.update(both(hands, arm_pole))
    pose.update(extra)
    return pose


def supine(x=0.0, back_y=BENCH_H, feet_x=None, feet_y=ANKLE_H, knee_up=True, hands=None, arm_pole=None,
           neck=0.0, **extra):
    """Lying on the back, head towards -x (left on screen), on a surface whose top is back_y."""
    P = v3(x, back_y + 11.5, 0.0)
    pose = {'pelvis': P, 'pitch': -90.0, 'neck': neck}
    fx = x + 50.0 if feet_x is None else feet_x
    for s, sg in (('L', -1), ('R', 1)):
        pose['leg' + s] = {'foot': v3(fx, feet_y, sg * 14.0), 'toe_out': 6.0,
                           'pole': v3(0.2, 1.0, 0.2 * sg) if knee_up else v3(1.0, 0.0, 0.0)}
    if hands is None:
        hands = v3(x - 49.0 + 20.0, back_y + 6.0, SHOULDER_HALF + 6.0)
    pose.update(both(hands, arm_pole if arm_pole is not None else [0.0, -1.0, 0.6]))
    pose.update(extra)
    return pose


def shoulder_world(pose, side='R'):
    from ..rig import solve
    return solve(pose).p['shoulder' + side]


# ---- gait ----------------------------------------------------------------------------------


class Gait:
    """Walking or running in place (treadmill style), phase in [0, 1)."""

    def __init__(self, stride=62.0, lift=9.0, duty=0.62, bob=1.6, lean=3.0, arm_swing=22.0, elbow=18.0,
                 knee_drive=0.0, drop=1.0, flight=0.0, half=9.0):
        self.stride, self.lift, self.duty = stride, lift, duty
        self.bob, self.lean, self.arm_swing, self.elbow = bob, lean, arm_swing, elbow
        self.knee_drive, self.drop, self.flight, self.half = knee_drive, drop, flight, half

    def foot(self, ph, x0):
        """Ankle position and foot pitch for one leg at phase ph (0 = heel strike)."""
        L, d = self.stride, self.duty
        if ph < d:                                  # stance: foot travels back on the ground
            t = ph / d
            x = x0 + L / 2 - L * t
            y = ANKLE_H
            pitch = lerp(8.0, 0.0, smooth(0.0, 0.25, t)) + lerp(0.0, -22.0, smooth(0.7, 1.0, t))
            if t > 0.7:
                y = ANKLE_H + 4.0 * smooth(0.7, 1.0, t)
        else:                                       # swing: foot comes through, lifted
            t = (ph - d) / (1 - d)
            e = 0.5 - 0.5 * math.cos(math.pi * t)
            x = x0 - L / 2 + L * e
            y = ANKLE_H + 4.0 * (1 - smooth(0.0, 0.3, t)) + self.lift * math.sin(math.pi * min(t * 1.15, 1.0))
            pitch = lerp(-22.0, 8.0, smooth(0.0, 0.9, t))
        return v3(x, y), pitch

    def pose(self, ph, x0=0.0, hands=None, arms=True, **extra):
        pr = ph % 1.0
        pl = (ph + 0.5) % 1.0
        pose = {'pelvis': v3(x0 + 2.0, HIP_H - self.drop - self.bob * (0.5 + 0.5 * math.cos(4 * math.pi * ph)), 0.0),
                'pitch': self.lean}
        for s, p, sg in (('R', pr, 1), ('L', pl, -1)):
            a, fp = self.foot(p, x0)
            pose['leg' + s] = {'foot': v3(a[0], a[1], sg * self.half), 'foot_pitch': fp,
                               'pole': v3(1.0, 0.0, 0.15 * sg)}
        if arms:
            for s, p, sg in (('R', pl, 1), ('L', pr, -1)):
                sw = self.arm_swing * math.cos(2 * math.pi * p)
                pose['arm' + s] = {'flex': sw, 'abd': 6.0, 'elbow': self.elbow + (8.0 * max(0, math.sin(2 * math.pi * p)))}
        pose.update(extra)
        return pose
