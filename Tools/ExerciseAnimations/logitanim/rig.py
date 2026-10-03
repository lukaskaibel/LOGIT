"""3D skeleton: a pose (pelvis, spine, limb targets or angles) -> joint positions.

World axes: x forward (where the figure faces in the side view), y up, z to the figure's right.
Poses are plain dicts so key poses can be interpolated key by key; see `motion.py`.
"""
import math
import numpy as np

from .spec import (SHANK, THIGH, TORSO, UPPER, FORE, FORE_WRIST, HIP_HALF, SHOULDER_HALF,
                   NECK_BASE, HEAD_UP, HEAD_FWD, HEEL, TOE)

X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


def v3(x, y, z=0.0):
    return np.array([x, y, z], float)


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def lerp(a, b, t):
    return a + (b - a) * t


class Frame:
    """Orthonormal body frame: f forward, u up, r right."""

    def __init__(self, f=X, u=Y, r=Z):
        self.f, self.u, self.r = np.array(f, float), np.array(u, float), np.array(r, float)

    def pitch(self, deg):
        """Lean forward (u tips towards f)."""
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return Frame(self.f * c - self.u * s, self.u * c + self.f * s, self.r)

    def roll(self, deg):
        """Bend towards the figure's right (u tips towards r)."""
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return Frame(self.f, self.u * c + self.r * s, self.r * c - self.u * s)

    def yaw(self, deg):
        """Turn to the figure's right (f swings towards r)."""
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        return Frame(self.f * c + self.r * s, self.u, self.r * c - self.f * s)

    def orient(self, pitch=0.0, roll=0.0, yaw=0.0):
        fr = self
        if pitch:
            fr = fr.pitch(pitch)
        if roll:
            fr = fr.roll(roll)
        if yaw:
            fr = fr.yaw(yaw)
        return fr


def ik2(root, target, l1, l2, pole):
    """Two-bone IK. Returns (mid, end); end stops short of an unreachable target."""
    root = np.asarray(root, float)
    target = np.asarray(target, float)
    d = target - root
    dist = np.linalg.norm(d)
    dirv = d / max(dist, 1e-9)
    dc = min(max(dist, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    a = (l1 * l1 - l2 * l2 + dc * dc) / (2 * dc)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = np.asarray(pole, float)
    p = p - np.dot(p, dirv) * dirv
    if np.linalg.norm(p) < 1e-6:
        p = np.cross(dirv, Z if abs(dirv[2]) < 0.9 else X)
    p = unit(p)
    return root + dirv * a + p * h, root + dirv * dc


class Joints:
    """Solved skeleton. Sides are 'L' and 'R'."""

    def __init__(self):
        self.p = {}         # name -> 3D point
        self.v = {}         # name -> 3D direction (anatomical sides for muscle regions)
        self.style = {}     # per-hand style


def rot_toward(d, toward, deg):
    """Rotate unit vector d towards unit vector `toward` (perpendicular part) by deg."""
    t = toward - np.dot(toward, d) * d
    if np.linalg.norm(t) < 1e-9:
        return d
    t = unit(t)
    a = math.radians(deg)
    return unit(d * math.cos(a) + t * math.sin(a))


def solve(pose):
    """pose: dict. Keys (all optional except pelvis):
      pelvis (3), pitch/roll/yaw (spine, deg), p_pitch/p_roll/p_yaw (pelvis, deg), neck (deg),
      shrug, protract (cm), and per side S in {L, R}:
      legS: {'foot': 3, 'pole': 3, 'foot_pitch': deg, 'toe_out': deg}
             or {'hip': deg, 'abd': deg, 'knee': deg, 'ankle': deg}
      armS: {'hand': 3, 'pole': 3, 'palm': bool}
             or {'flex': deg, 'abd': deg, 'elbow': deg}
    """
    J = Joints()
    P = np.asarray(pose['pelvis'], float)
    pf = Frame().orient(pose.get('p_pitch', 0.0), pose.get('p_roll', 0.0), pose.get('p_yaw', 0.0))
    tf = pf.orient(pose.get('pitch', 0.0), pose.get('roll', 0.0), pose.get('yaw', 0.0))
    J.pelvis_frame, J.torso_frame = pf, tf
    J.p['pelvis'] = P
    shrug = pose.get('shrug', 0.0)
    protract = pose.get('protract', 0.0)
    sc = P + tf.u * (TORSO + shrug) + tf.f * protract
    J.p['shoulder_c'] = sc
    J.p['neck'] = P + tf.u * NECK_BASE
    hf = tf.pitch(-pose.get('neck', 0.0))
    J.p['head'] = J.p['neck'] + hf.u * HEAD_UP + hf.f * HEAD_FWD
    for side, s in (('L', -1.0), ('R', 1.0)):
        hip = P + pf.r * (s * HIP_HALF)
        J.p['hip' + side] = hip
        leg = pose.get('leg' + side, {})
        if 'foot' in leg:
            ank_t = np.asarray(leg['foot'], float)
            knee, ank = ik2(hip, ank_t, THIGH, SHANK, leg.get('pole', pf.f))
            d_t, d_s = unit(knee - hip), unit(ank - knee)
            # foot on the ground: toes point along the pelvis' horizontal forward, turned out
            fwd = pf.f - np.dot(pf.f, Y) * Y
            fwd = unit(fwd) if np.linalg.norm(fwd) > 1e-6 else X
            side_h = unit(np.cross(fwd, Y))  # the figure's right, horizontal
            toe_out = math.radians(leg.get('toe_out', 0.0))
            th = unit(fwd * math.cos(toe_out) + side_h * s * math.sin(toe_out))
            fp = math.radians(leg.get('foot_pitch', 0.0))
            t = unit(th * math.cos(fp) + Y * math.sin(fp))
            n = unit(Y * math.cos(fp) - th * math.sin(fp))
        else:
            flex, abd = leg.get('hip', 0.0), leg.get('abd', 0.0)
            d_t = rot_toward(-pf.u, pf.f, flex)
            if abd:
                d_t = rot_toward(d_t, pf.r * s, abd)
            knee = hip + d_t * THIGH
            a_t = unit(np.cross(pf.r, d_t))
            d_s = rot_toward(d_t, -a_t, leg.get('knee', 0.0))
            ank = knee + d_s * SHANK
            a_s = unit(np.cross(pf.r, d_s))
            ang = leg.get('ankle', 0.0)          # + = toes pointed away (plantarflexion)
            t = rot_toward(a_s, d_s, ang)
            n = unit(-d_s * math.cos(math.radians(ang)) + a_s * math.sin(math.radians(ang)))
            n = unit(n - np.dot(n, t) * t)
        J.p['knee' + side], J.p['ankle' + side] = knee, ank
        J.p['heel' + side] = ank + n * HEEL[0] + t * HEEL[1]
        J.p['toe' + side] = ank + n * TOE[0] + t * TOE[1]
        J.v['thigh_front' + side] = unit(np.cross(pf.r, d_t))
        J.v['shank_front' + side] = unit(np.cross(pf.r, d_s))
        J.v['foot_n' + side] = n

        sh = sc + tf.r * (s * SHOULDER_HALF)
        J.p['shoulder' + side] = sh
        arm = pose.get('arm' + side, {})
        palm = arm.get('palm', False)
        wrist_flex = arm.get('wrist_flex')
        fore = FORE_WRIST if (palm or wrist_flex is not None) else FORE
        if 'hand' in arm:
            pole = np.asarray(arm.get('pole', -tf.f - tf.u * 0.3), float)
            elbow, hand = ik2(sh, arm['hand'], UPPER, fore, pole)
            d_u = unit(elbow - sh)
            pp = pole - np.dot(pole, d_u) * d_u
            flex_side = -unit(pp) if np.linalg.norm(pp) > 1e-6 else unit(np.cross(tf.r, d_u))
            if wrist_flex is not None:
                # 'hand' was the wrist: the grip swings around it (wrist curls)
                d_f = unit(hand - elbow)
                hand = hand + rot_toward(d_f, flex_side, wrist_flex) * (FORE - FORE_WRIST)
                J.p['wrist' + side] = elbow + d_f * FORE_WRIST
        else:
            d_u = rot_toward(-tf.u, tf.f, arm.get('flex', 0.0))
            if arm.get('abd', 0.0):
                d_u = rot_toward(d_u, tf.r * s, arm['abd'])
            elbow = sh + d_u * UPPER
            flex_side = unit(np.cross(tf.r, d_u))
            if np.linalg.norm(np.cross(tf.r, d_u)) < 0.2:
                flex_side = unit(tf.f - np.dot(tf.f, d_u) * d_u)
            d_f = rot_toward(d_u, flex_side, arm.get('elbow', 0.0))
            hand = elbow + d_f * fore
        J.p['elbow' + side], J.p['hand' + side] = elbow, hand
        J.v['biceps' + side] = flex_side
        J.style['hand' + side] = 'palm' if palm else 'fist'
        if palm:
            J.v['palm' + side] = unit(np.asarray(arm.get('palm_dir', tf.f), float))
    return J
