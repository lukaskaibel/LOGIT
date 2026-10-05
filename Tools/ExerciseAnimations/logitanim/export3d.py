"""Bake an exercise for the app's real-time renderer (ExerciseFigure in LOGIT/SharedUI): per frame,
the solved skeleton and the equipment as 3D primitives. The app draws them from any camera the way
view3d does; the muscle regions it derives from the skeleton itself (anatomy.blobs, ported).

File layout (little endian):
  b'LGRG', u32 header length, header (UTF-8 JSON), u32 data length, data (raw deflate)
The data is int16, channel-major (every frame of channel 0, then channel 1, ...), each channel
delta-coded along time. Positions and lengths are in units of POS_STEP cm, directions of 1/DIR_ONE.
"""
import json
import struct
import zlib

import numpy as np

from .rig import solve
from .spec import PAL, MUSCLE, R_HEAD, R_THIGH, R_UPPER, R_SHANK, R_HAND, R_HEEL, R_TOE
from . import view3d

FPS = 30
POS_STEP = 0.02         # cm per unit: +-655 cm
DIR_ONE = 16384.0       # a unit vector component of 1.0
JOINTS = ['pelvis', 'head',
          'hipL', 'kneeL', 'ankleL', 'heelL', 'toeL', 'hipR', 'kneeR', 'ankleR', 'heelR', 'toeR',
          'shoulderL', 'elbowL', 'handL', 'wristL', 'shoulderR', 'elbowR', 'handR', 'wristR']
VECTORS = ['torsoF', 'torsoU', 'torsoR', 'pelvisF', 'pelvisU', 'pelvisR',
           'bicepsL', 'bicepsR', 'thighFrontL', 'thighFrontR', 'shankFrontL', 'shankFrontR',
           'footNL', 'footNR', 'palmL', 'palmR']
HAND = {'fist': 0, 'palm': 1, 'wrist': 2}
YAW = {'side': 0.0, 'front': 90.0, 'back': -90.0, 'top': 0.0}
PITCH = {'top': 90.0}
COLORS = ['fig', 'bg', 'plate', 'plate_rim', 'metal', 'pad', 'frame', 'floor', 'ghost', 'far', 'accent', 'water']


def _hex(c):
    return '#%02X%02X%02X' % tuple(int(round(float(x) * 255)) for x in c)


def _vectors(J):
    tf, pf = J.torso_frame, J.pelvis_frame
    v = {'torsoF': tf.f, 'torsoU': tf.u, 'torsoR': tf.r, 'pelvisF': pf.f, 'pelvisU': pf.u, 'pelvisR': pf.r}
    for s in 'LR':
        v['biceps' + s] = J.v['biceps' + s]
        v['thighFront' + s] = J.v['thigh_front' + s]
        v['shankFront' + s] = J.v['shank_front' + s]
        v['footN' + s] = J.v['foot_n' + s]
        v['palm' + s] = J.v.get('palm' + s, tf.f)
    return v


def _equip_params(e):
    """(structure, params, kinds of the params) of one 3D primitive spec."""
    kind, color = e[0], e[-2]
    mode = 2 if e[-1] == 'back' else (1 if e[-1] else 0)      # 0 no band, 1 knockout band, 2 backdrop
    if kind == 'cyl':
        _, c3, ax, r, half = e[:5]
        vals = list(c3) + list(ax) + [r, half]
        kinds = 'pppdddrr'
    elif kind == 'cap':
        _, a3, b3, r = e[:4]
        vals = list(a3) + list(b3) + [r]
        kinds = 'ppppppr'
    elif kind == 'cone':
        _, a3, b3, ra, rb = e[:5]
        vals = list(a3) + list(b3) + [ra, rb]
        kinds = 'pppppprr'
    elif kind == 'sph':
        _, c3, r = e[:3]
        vals = list(c3) + [r]
        kinds = 'pppr'
    elif kind == 'box':
        _, c3, axes, half, rnd = e[:5]
        vals = list(c3) + [x for a in axes for x in a] + list(half) + [rnd]
        kinds = 'ppp' + 'd' * 9 + 'rrrr'
    else:
        raise ValueError(kind)
    return (kind, color, mode), [float(x) for x in vals], kinds


# how far the body reaches past each joint (the torso's half depth about the pelvis and shoulders)
BODY_PAD = {'pelvis': 12.0, 'head': R_HEAD, 'hip': R_THIGH[0], 'knee': R_THIGH[1], 'ankle': R_SHANK[1],
            'heel': R_HEEL, 'toe': R_TOE, 'shoulder': 12.0, 'elbow': R_UPPER[0], 'hand': R_HAND + 1.0}


def body_extent_points(J):
    """Points that bound the drawn body (joints grown by the body's reach past them), for framing."""
    pts = []
    for k in JOINTS:
        if k.startswith('wrist') or k not in J.p:
            continue
        p = np.asarray(J.p[k], float)
        r = BODY_PAD[k.rstrip('LR')]
        pts += [p - r, p + r]
    return pts


def _extent_points(e):
    """Points that bound a 3D primitive spec (for the scene's bounds)."""
    kind = e[0]
    if kind == 'cyl':
        _, c3, ax, r, half = e[:5]
        c3, ax = np.asarray(c3, float), np.asarray(ax, float)
        return [c3 + ax * half * s + d * r for s in (-1, 1) for d in (np.eye(3)[0], -np.eye(3)[0], np.eye(3)[1],
                                                                      -np.eye(3)[1], np.eye(3)[2], -np.eye(3)[2])]
    if kind in ('cap', 'cone'):
        a3, b3, r = np.asarray(e[1], float), np.asarray(e[2], float), max(e[3:5] if kind == 'cone' else [e[3]])
        return [a3 + r, a3 - r, b3 + r, b3 - r]
    if kind == 'sph':
        _, c3, r = e[:3]
        return [np.asarray(c3, float) + r, np.asarray(c3, float) - r]
    _, c3, axes, half = e[:4]
    c3 = np.asarray(c3, float)
    return [c3 + sum(np.asarray(a, float) * h * sg for a, h, sg in zip(axes, half, signs))
            for signs in [(a, b, c) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]]


def bake(ex):
    """(header dict, int16 array frames x channels) for an exercise. Raises when its equipment
    exists only for one camera or changes its make-up during the loop."""
    n = max(1, int(round(ex.duration * FPS)))
    cam = view3d.Cam3(YAW.get(ex.camera, 0.0), PITCH.get(ex.camera, 0.0))
    view = view3d._View(cam)
    rows, kinds, structure, hand_styles = [], None, None, []
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    for i in range(n):
        t = ex.duration * i / n
        u = ex.phase(t)
        J = solve(ex.pose_fn(u))
        vals, ks = [], ''
        for k in JOINTS:
            p = J.p.get(k, J.p.get('hand' + k[-1]) if k.startswith('wrist') else None)
            vals += list(p)
            ks += 'ppp'
        for q in body_extent_points(J):
            lo, hi = np.minimum(lo, q), np.maximum(hi, q)
        vec = _vectors(J)
        for k in VECTORS:
            vals += list(vec[k])
            ks += 'ddd'
        hand_styles.append([HAND['palm'] if J.style['hand' + s] == 'palm' else
                            HAND['wrist'] if 'wrist' + s in J.p else HAND['fist'] for s in 'LR'])
        struct_i = []
        if ex.equip:
            items = ex.equip(J, view, u)
            gi = -1
            for it in items:
                spec = getattr(it, 'spec3d', None)
                if spec is None:
                    if it.shape is not None:
                        raise ValueError('equipment exists only for one camera')
                    continue
                if spec:
                    gi += 1         # one group per piece of equipment (the item that carries it)
                for e in spec:
                    st, pv, pk = _equip_params(e)
                    struct_i.append(st + (len(pv), gi))
                    vals += pv
                    ks += pk
                    if e[-1] == 'back' or not it.frame3d:     # backdrops (walls, water) and a thrown
                        continue                                 # ball may run off the picture
                    for q in _extent_points(e):
                        lo, hi = np.minimum(lo, q), np.maximum(hi, q)
        if structure is None:
            structure, kinds = struct_i, ks
        elif struct_i != structure:
            raise ValueError('equipment changes during the loop')
        rows.append(vals)
    data = np.array(rows, float)
    scale = np.array([1.0 / POS_STEP if k in 'pr' else DIR_ONE for k in kinds])
    q = np.round(data * scale)
    if np.abs(q).max() > 32767:
        raise ValueError('value out of int16 range')
    q = q.astype(np.int16)
    hands = sorted(set(map(tuple, hand_styles)))
    if len(hands) > 1:
        raise ValueError('hand styles change during the loop')
    frame = ex.frame()
    header = dict(
        version=1, key=ex.key, group=ex.group, muscles=list(ex.muscles),
        muscleColor=_hex(MUSCLE[ex.group]), palette={k: _hex(PAL[k]) for k in COLORS},
        camera=dict(yaw=YAW.get(ex.camera, 0.0), pitch=PITCH.get(ex.camera, 0.0)),
        duration=ex.duration, fps=FPS, frames=n, channels=len(kinds), kinds=kinds,
        posStep=POS_STEP, dirOne=DIR_ONE, joints=JOINTS, vectors=VECTORS, hands=list(hands[0]),
        equipment=[dict(kind=k, color=c, mode=g, count=m, group=gi) for k, c, g, m, gi in structure],
        floor=None, box2d=[float(x) for x in frame['box']],
        bounds=dict(min=[float(x) for x in lo], max=[float(x) for x in hi]),
    )
    if ex.floor:
        c, r = view3d.floor_disc(ex)
        header['floor'] = dict(center=[float(x) for x in c], radius=float(r))
    return header, q


def encode(header, q):
    d32 = np.diff(q.astype(np.int32), axis=0, prepend=0)                    # delta along time
    if np.abs(d32).max() > 32767:
        raise ValueError('a channel jumps too far between frames for int16 deltas')
    d = d32.astype(np.int16)
    raw = np.ascontiguousarray(d.T).astype('<i2').tobytes()                  # channel-major
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    body = co.compress(raw) + co.flush()
    h = json.dumps(header, separators=(',', ':')).encode()
    return b'LGRG' + struct.pack('<I', len(h)) + h + struct.pack('<I', len(body)) + body


def decode(blob):
    """The exact inverse of encode (for tests): (header, float frames x channels)."""
    assert blob[:4] == b'LGRG'
    hl = struct.unpack('<I', blob[4:8])[0]
    header = json.loads(blob[8:8 + hl])
    bl = struct.unpack('<I', blob[8 + hl:12 + hl])[0]
    raw = zlib.decompress(blob[12 + hl:12 + hl + bl], -15)
    d = np.frombuffer(raw, '<i2').reshape(header['channels'], header['frames']).T
    q = np.cumsum(d.astype(np.int32), axis=0)
    scale = np.array([header['posStep'] if k in 'pr' else 1.0 / header['dirOne'] for k in header['kinds']])
    return header, q * scale
