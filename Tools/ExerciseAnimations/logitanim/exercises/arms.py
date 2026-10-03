"""Arms: biceps curls (standing, seated, on benches, on cables) and triceps extensions."""
from .common import *
from ..sdf import Circle, Cone, Union
from ..rig import solve

PAD_T = eq.PAD_T


# ---- arm geometry ----------------------------------------------------------------------------

def arm_plane(S, down, fwd, a, e, fore=FORE, lu=UPPER):
    """An arm in the plane through shoulder S spanned by the unit vectors `down` and `fwd`.
    a: upper arm angle (deg) from `down` towards `fwd`; e: elbow flexion (deg), the forearm
    swinging towards the upper arm's front. Returns (IK dict, elbow, grip, forearm dir, front)."""
    ar, er = math.radians(a), math.radians(e)
    down, fwd = np.asarray(down, float), np.asarray(fwd, float)
    d_u = down * math.cos(ar) + fwd * math.sin(ar)
    b = fwd * math.cos(ar) - down * math.sin(ar)
    E = np.asarray(S, float) + d_u * lu
    d_f = d_u * math.cos(er) + b * math.sin(er)
    H = E + d_f * fore
    return {'hand': H, 'pole': -b}, E, H, d_f, b


def sag(S, a, e, fore=FORE, lu=UPPER):
    """Arm in the sagittal plane through S: a from straight down towards forward (+x)."""
    return arm_plane(S, -Y, X, a, e, fore, lu)


def arm_3d(S, a, e, elbow_z, hand_z, lu=UPPER, lf=FORE):
    """Arm planned in the side view (a, e as in `sag`) with the elbow and the grip moved to the
    given depths; the projected bone lengths shrink so the bones keep their length. The pole
    aims the IK at exactly this elbow."""
    S = np.asarray(S, float)
    dz_u, dz_f = elbow_z - S[2], hand_z - elbow_z
    pu = math.sqrt(max(lu ** 2 - dz_u ** 2, 1.0))
    pf = math.sqrt(max(lf ** 2 - dz_f ** 2, 1.0))
    ar, fr = math.radians(a), math.radians(a + e)
    E = S + v3(pu * math.sin(ar), -pu * math.cos(ar), dz_u)
    H = E + v3(pf * math.sin(fr), -pf * math.cos(fr), dz_f)
    return aim(S, E, H, v3(math.cos(ar), math.sin(ar)))


def aim(S, E, H, front_hint):
    """IK target that reproduces elbow E exactly (bones must fit), flexing towards the front."""
    d_u, d_f = unit(E - S), unit(H - E)
    b = d_f - np.dot(d_f, d_u) * d_u
    b = unit(b) if np.linalg.norm(b) > 1e-4 else unit(front_hint)
    return {'hand': H, 'pole': E - (S + H) / 2 - b}


def rot(axis, deg):
    """Rotation matrix about a unit axis (right-handed)."""
    a = math.radians(deg)
    x, y, z = unit(axis)
    c, s, C = math.cos(a), math.sin(a), 1.0 - math.cos(a)
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def opened(S, arm, sg, abd=0.0, turn=0.0):
    """A planned arm (arm_plane's return) opened out to its side (sg: +1 right, -1 left): turned out
    by `turn` (deg, about the vertical through the shoulder, so a forearm held in front swings out)
    and abducted by `abd` (deg, about the forward axis, so a hanging arm swings out). Bones and
    elbow angle stay as planned; the side view barely changes. Returns the IK target."""
    _, E, H, _, b = arm
    S = np.asarray(S, float)
    R = rot(X, -sg * abd) @ rot(Y, -sg * turn)
    return aim(S, S + R @ (E - S), S + R @ (H - S), R @ b)


def shoulders(pose):
    J = solve(pose)
    return J.p['shoulderL'], J.p['shoulderR']


def sag_both(pose, a, e, fore=FORE, abd=0.0, turn=0.0, **kw):
    """Both arms mirrored in their sagittal planes, opened out by abd/turn (see `opened`) where a
    held dumbbell's inner head has to clear the legs, the hips or the chest."""
    SL, SR = shoulders(pose)
    for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
        arm = sag(S, a, e, fore)
        arm = opened(S, arm, sg, abd, turn) if (abd or turn) else arm[0]
        arm.update(kw)
        pose['arm' + s] = arm
    return pose


def grip_pair(pose, hand_r, pole_r, **kw):
    """Both hands on one implement: right-hand target mirrored."""
    pose.update(both(hand_r, pole_r))
    for s in 'LR':
        pose['arm' + s].update(kw)
    return pose


def working_arm_only(v, side='R'):
    """One-arm exercises: tint only the working arm (the resting arm keeps its white)."""
    other = 'L' if side == 'R' else 'R'
    v.paint_on['arm' + other] = []
    v.paint_on['fore' + other] = []


# ---- implements ------------------------------------------------------------------------------

def hinge_axis(J, s):
    """Handle along the elbow's hinge (supinated or pronated grip)."""
    S, E, W = J.p['shoulder' + s], J.p['elbow' + s], J.p['hand' + s]
    h = np.cross(E - S, W - E)
    if np.linalg.norm(h) < 1e-6:
        return Z
    h = unit(h)
    return h if h[2] >= 0 else -h


def across(J, s):
    """A handle straight across the body (the hinge of the arm as planned in the side view): an arm
    opened or angled a little (see `opened`) still holds its dumbbell level and square to the body,
    the wrist giving, so the side view keeps both dumbbells end-on together."""
    return Z


def neutral_axis(J, s):
    """Handle across the forearm in the plane of the arm (neutral / hammer grip), pointing to
    the thumb side (the way the forearm flexes)."""
    E, W = J.p['elbow' + s], J.p['hand' + s]
    return unit(np.cross(hinge_axis(J, s), unit(W - E)))


def dumbbells(J, v, axis_fn, sides='LR', **kw):
    items = []
    for s in sides:
        items += eq.dumbbell(v, J.p['hand' + s], axis_fn(J, s), ('before', 'arm' + s), **kw)
    return items


def bar_end(J, v, plate_r=12.0):
    """A curl bar seen end-on between the hands, with small plates. eq.barbell orders them by
    depth: the camera-side plate covers the near hand and arm (with its knockout), as in 3D, where
    the bar is a curl bar's 1.2 m rather than an Olympic bar's 2.2 m."""
    B = (J.p['handL'] + J.p['handR']) / 2
    return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=plate_r, half3d=60.0)


def rope_items(v, hand3, clip3, thumb3, z):
    """Rope attachment: from the cable clip into the fist, the knotted end out of the little
    finger side."""
    cam = v.cam
    knob = hand3 - unit(thumb3) * 6.5
    rope = Union([Cone(cam.p(clip3), cam.p(hand3), 1.5), Cone(cam.p(hand3), cam.p(knob), 1.5),
                  Circle(cam.p(knob), 2.7)])
    # 3D: this half of the rope, from the clip through the fist, and its knotted end
    spec = (eq.rod3d(clip3, hand3, 1.5, 'metal', True) + eq.rod3d(hand3, knob, 1.5, 'metal', True)
            + eq.ball3d(knob, 2.7, 'metal', True))
    return [Item(rope, 'metal', z, True, spec3d=spec)]


# ---- benches (built from pads and posts) --------------------------------------------------------

def pad_part(cam, a3, b3, **kw):
    """A pad (see eq.pad) and its 3D box, so `build.py clip` sees the body resting on it."""
    return eq.pad(cam, a3, b3, **kw), eq.pad_box(a3, b3, **kw)


def frame_and_pads(frame, pads, z='back', pad_z=None, pad_gap=False, frame3d=None):
    """pads: [(shape, collider)] from pad_part; frame3d: the frame's 3D primitives (eq.post3d,
    eq.rod3d of the same points as `frame`). The bench is one piece in 3D: the frame and the pad
    boxes (the colliders, as eq.pad draws them) ride on the frame item."""
    spec = list(frame3d or []) + [('box',) + tuple(c[1:]) + (3.0, 'pad', pad_gap) for _, c in pads]
    return [Item(Union(frame), 'frame', z, spec3d=spec),
            Item(Union([p for p, _ in pads]), 'pad', pad_z or z, pad_gap, collider=[c for _, c in pads], spec3d=[])]


def post_part(cam, top3):
    """eq.post and its 3D form."""
    return eq.post(cam, top3), eq.post3d(top3)


def tube_part(cam, a3, b3, r):
    """A frame tube from a3 to b3: its 2D cone and its 3D capsule."""
    return [Cone(cam.p(a3), cam.p(b3), r)], eq.rod3d(a3, b3, r, 'frame')


def seat_with_back(v, hinge3, seat_len=42.0, back_deg=60.0, back_len=70.0, z='back'):
    """A seat whose back end meets a back rest raised `back_deg` from horizontal behind the
    sitter (towards -x). hinge3 = where the seat top meets the back rest's front."""
    cam = v.cam
    h = np.asarray(hinge3, float)
    a = math.radians(back_deg)
    d = v3(-math.cos(a), math.sin(a))          # up the back rest
    n = v3(math.sin(a), math.cos(a))           # its front, towards the sitter
    pads = [pad_part(cam, h - X * 2.0, h + X * seat_len),
            pad_part(cam, h, h + d * back_len, up3=n)]
    frame, frame3d = post_part(cam, h + X * (seat_len - 9.0) - Y * PAD_T)
    # rear leg: straight up from the floor into the back rest's underside
    rx = h[0] - min(16.0, back_len * math.cos(a) * 0.6) - 4.0
    t = (h[0] - rx) / max(math.cos(a), 1e-3)
    under = h + d * t - n * PAD_T
    for f2, f3 in (post_part(cam, v3(rx, min(under[1], h[1] + 30.0), 0.0)),
                   tube_part(cam, h - Y * PAD_T - X * 2.0, v3(rx, h[1] - PAD_T, 0.0), 1.8)):
        frame += f2
        frame3d += f3
    return frame_and_pads(frame, pads, z, frame3d=frame3d)


def flat_bench(v, x0, x1, top=BENCH_H, zc=0.0, z='back'):
    cam = v.cam
    pads = [pad_part(cam, v3(x0, top, zc), v3(x1, top, zc))]
    frame, frame3d = post_part(cam, v3(x0 + 12.0, top - PAD_T, zc))
    f2, f3 = post_part(cam, v3(x1 - 12.0, top - PAD_T, zc))
    return frame_and_pads(frame + f2, pads, z, frame3d=frame3d + f3)


# ---- standing curls ---------------------------------------------------------------------------

def curl_rep(concentric=1.3, eccentric=1.6, bottom_hold=0.35, top_hold=0.4):
    return rep(concentric, eccentric, top=bottom_hold, bottom=top_hold)


def standing_curl(u, a0=5.0, a1=10.0, e0=12.0, e1=145.0, lean=-1.5, abd=0.0):
    """abd: the arms hang that far open (deg) so the dumbbells' inner heads pass beside the thighs,
    closing as the elbows flex and the weights come up in front."""
    pose = standing(0.0, half=11.0, pitch=lean * u)
    e = lerp(e0, e1, u)
    return sag_both(pose, lerp(a0, a1, u), e, abd=abd * (1.0 - smooth(35.0, 65.0, e)))


def bar_curl(key, muscles, e1=145.0, a1=10.0, plate_r=12.0):
    @exercise(key, 'biceps', 'side', muscles=muscles)
    def build():
        def pose(u):
            return standing_curl(u, e1=e1, a1=a1)

        def equip(J, v, u):
            return bar_end(J, v, plate_r)

        return pose, curl_rep(), equip
    return build


bar_curl('barbellCurls', ['biceps'])
bar_curl('ezBarCurls', ['biceps'], e1=142.0)
bar_curl('reverseCurls', ['biceps', 'forearms'], e1=136.0, a1=8.0)


@exercise('dumbbellCurls', 'biceps', 'side', muscles=['biceps'])
def dumbbell_curls():
    def pose(u):
        return standing_curl(u, a0=2.0, e0=8.0, abd=13.0)

    def equip(J, v, u):
        return dumbbells(J, v, across)

    return pose, curl_rep(), equip


@exercise('hammerCurls', 'biceps', 'side', muscles=['biceps', 'forearms'])
def hammer_curls():
    def pose(u):
        return standing_curl(u, a0=2.0, e0=8.0, e1=130.0, abd=6.0)

    def equip(J, v, u):
        return dumbbells(J, v, neutral_axis)

    return pose, curl_rep(), equip


@exercise('zottmanCurls', 'biceps', 'side', muscles=['biceps', 'forearms'])
def zottman_curls():
    # phase: 0-1 curl up palms up, 1-2 turn the palms down at the top, 2-3 lower palms down,
    # 3-4 turn back at the bottom (4 == 0: the dumbbell has made two half turns)
    def split(u):
        if u <= 1.0:
            return u, 0.0
        if u <= 2.0:
            return 1.0, u - 1.0
        if u <= 3.0:
            return 3.0 - u, 1.0
        return 0.0, 1.0 + (u - 3.0)

    def pose(u):
        c, _ = split(u)
        return standing_curl(c, a0=2.0, e0=8.0, e1=126.0, abd=14.0)

    def equip(J, v, u):
        _, r = split(u)
        th = math.pi * r
        items = []
        for s in 'LR':
            ax = across(J, s) * math.cos(th) + neutral_axis(J, s) * math.sin(th)
            items += eq.dumbbell(v, J.p['hand' + s], ax, ('before', 'arm' + s))
        return items

    one = [(0.35, 0, 0), (1.3, 0, 1), (0.6, 1, 2), (1.6, 2, 3), (0.6, 3, 4)]
    return pose, Timeline(one * 2), equip


@exercise('dragCurls', 'biceps', 'side', muscles=['biceps'])
def drag_curls():
    y0, y1 = 82.8, 124.0

    def bar(u):
        y = lerp(y0, y1, u)
        x = lerp(12.6, 16.2, smooth(y0, y0 + 16.0, y))
        return v3(x, y, SHOULDER_HALF + 2.0)

    def pose(u):
        p = standing(0.0, half=11.0, pitch=-1.0 * u)
        return grip_pair(p, bar(u), [-1.0, -0.35, 0.1])

    def equip(J, v, u):
        return bar_end(J, v)

    return pose, curl_rep(1.4, 1.6), equip


# ---- cable curls (low pulley) ---------------------------------------------------------------------

TOWER_X = 62.0
LOW_PULLEY = v3(56.0, 15.0, 0.0)


@exercise('cableCurls', 'biceps', 'side', muscles=['biceps'])
def cable_curls():
    def pose(u):
        return standing_curl(u, a0=6.0, a1=10.0, e0=14.0, e1=142.0, lean=-3.0)

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.cable_stack(v, LOW_PULLEY, v3(B[0], B[1], 0.0), tower_x=TOWER_X)

    return pose, curl_rep(), equip


@exercise('cableHammerCurls', 'biceps', 'side', muscles=['biceps', 'forearms'])
def cable_hammer_curls():
    def pose(u):
        return standing_curl(u, a0=4.0, a1=10.0, e0=12.0, e1=132.0, lean=-3.0)

    def equip(J, v, u):
        H = J.p['handR']
        clip = H + unit(LOW_PULLEY - H) * 12.0
        clip[2] = 0.0
        items = eq.cable_stack(v, LOW_PULLEY, clip, tower_x=TOWER_X)
        for s in 'LR':
            items += rope_items(v, J.p['hand' + s], clip, neutral_axis(J, s), ('before', 'arm' + s))
        return items

    return pose, curl_rep(), equip


# ---- seated curls on benches -------------------------------------------------------------------------

def back_hinge(P, pitch, seat, back=-12.6):
    """Where a back rest lying along the back of a torso (pelvis P, pitch) meets the seat top."""
    th = math.radians(pitch)
    tu, tf = v3(math.sin(th), math.cos(th)), v3(math.cos(th), -math.sin(th))
    b = (seat - P[1] - tf[1] * back) / tu[1]
    h = P + tf * back + tu * b
    return v3(h[0], seat, 0.0)


def incline_curl(key, back_deg, e1=140.0):
    SEAT = BENCH_H
    PITCH = -(90.0 - back_deg)

    @exercise(key, 'biceps', 'side', muscles=['biceps'])
    def build():
        P = v3(0.0, SEAT + 10.0, 0.0)
        base = seated(0.0, seat_h=SEAT, pitch=PITCH, half=12.0)
        base['pelvis'] = P
        base['neck'] = -PITCH * 0.5          # the head rests on the back rest, not in it
        hinge = back_hinge(P, PITCH, SEAT)

        def pose(u):
            p = dict(base)
            e = lerp(6.0, e1, u)
            # the arms hang beside the back rest and the forearms come up outside the hips and
            # thighs, so the dumbbells' inner heads pass beside the body, not through the lap
            return sag_both(p, lerp(-2.0, 0.0, u), e, abd=10.0, turn=20.0 * smooth(10.0, 70.0, e))

        def equip(J, v, u):
            return seat_with_back(v, hinge, seat_len=46.0, back_deg=back_deg, back_len=78.0) + \
                dumbbells(J, v, across)

        return pose, curl_rep(), equip
    return build


incline_curl('inclineDumbbellCurls', 60.0)
incline_curl('seatedInclineCurls', 52.0, e1=138.0)


@exercise('preacherCurls', 'biceps', 'side', muscles=['biceps'])
def preacher_curls():
    SEAT = 50.0
    PITCH = 24.0
    P = v3(0.0, SEAT + 9.5, 0.0)
    base = seated(0.0, seat_h=SEAT, pitch=PITCH, half=12.0)
    base['pelvis'] = P
    base['protract'] = 5.0
    base['neck'] = -8.0
    _, SR = shoulders(base)
    A = 45.0                                   # upper arm down the pad
    d_u = v3(math.sin(math.radians(A)), -math.cos(math.radians(A)))
    b = v3(math.cos(math.radians(A)), math.sin(math.radians(A)))
    S2 = v3(SR[0], SR[1], 0.0)
    pad_a = S2 + d_u * 13.0 - b * 5.9
    pad_b = S2 + d_u * 38.0 - b * 5.9
    T = 9.0

    def pose(u):
        p = dict(base)
        return sag_both(p, A, lerp(10.0, 110.0, u))

    def equip(J, v, u):
        cam = v.cam
        arm_pad, arm_col = pad_part(cam, pad_a, pad_b, width=40.0, t=T)
        seat, seat_col = pad_part(cam, v3(P[0] - 16.0, SEAT, 0.0), v3(P[0] + 14.0, SEAT, 0.0))
        mid = pad_a + (pad_b - pad_a) * 0.6 - b * T
        frame, frame3d = tube_part(cam, mid, v3(mid[0], 1.2, 0.0), 2.2)
        for f2, f3 in (post_part(cam, v3(P[0] - 1.0, SEAT - PAD_T, 0.0)),
                       tube_part(cam, v3(P[0] - 9.0, 1.2, 0.0), v3(mid[0] + 9.0, 1.2, 0.0), 1.4)):
            frame += f2
            frame3d += f3
        # 3D: one piece, on the frame item: the column (between the knees), the seat post and the
        # floor rail, the seat, and the arm pad (it bands into the body). The pad is as wide as a
        # real preacher pad, 52 cm: the upper arms (at +-18, 6 cm thick) lie on it, not on its edges
        spec = frame3d + [('box',) + tuple(seat_col[1:]) + (3.0, 'pad', False)]
        spec += eq.pad3d(pad_a, pad_b, width=52.0, t=T, gap=True)
        return [Item(Union(frame), 'frame', 'back', spec3d=spec),
                Item(seat, 'pad', 'back', collider=seat_col, spec3d=[]),
                Item(arm_pad, 'pad', ('after', 'base'), True, collider=arm_col, spec3d=[])] + bar_end(J, v)

    return pose, curl_rep(), equip


@exercise('spiderCurls', 'biceps', 'side', muscles=['biceps'])
def spider_curls():
    PITCH = 46.0
    P = v3(0.0, 82.0, 0.0)
    th = math.radians(PITCH)
    tu, tf = v3(math.sin(th), math.cos(th)), v3(math.cos(th), -math.sin(th))
    base = {'pelvis': P, 'pitch': PITCH, 'protract': 3.5, 'neck': 26.0}
    for s, sg in (('L', -1), ('R', 1)):
        base['leg' + s] = {'foot': v3(-34.0, ANKLE_H, sg * 11.0), 'pole': v3(1.0, 0.0, 0.2 * sg),
                           'toe_out': 6.0}
    # chest-down pad: its top surface runs along the front of the torso
    pad_lo = P + tf * 14.2 + tu * (-8.0)
    pad_hi = P + tf * 14.2 + tu * 30.0
    T = 9.0

    def pose(u):
        p = dict(base)
        return sag_both(p, 0.0, lerp(5.0, 132.0, u))

    def equip(J, v, u):
        cam = v.cam
        pads = [pad_part(cam, pad_lo, pad_hi, up3=-tf, t=T)]
        under = pad_lo + (pad_hi - pad_lo) * 0.35 + tf * T
        frame, frame3d = post_part(cam, under)
        low = pad_lo + tf * 3.0
        for f2, f3 in (tube_part(cam, low, v3(low[0] - 14.0, 1.2, 0.0), 1.8),
                       tube_part(cam, v3(low[0] - 22.0, 1.2, 0.0), v3(under[0] + 8.0, 1.2, 0.0), 1.4)):
            frame += f2
            frame3d += f3
        # the pad is under the chest, nearer the camera than the torso's far half: draw it over
        # the body with a knockout (the near leg and arm still pass in front of it)
        return frame_and_pads(frame, pads, pad_z=('after', 'base'), pad_gap=True, frame3d=frame3d) + \
            dumbbells(J, v, hinge_axis)

    return pose, curl_rep(1.2, 1.6), equip


@exercise('concentrationCurls', 'biceps', 'front', muscles=['biceps'])
def concentration_curls():
    SEAT = BENCH_H
    PITCH = 44.0
    P = v3(0.0, SEAT + 9.5, 0.0)
    base = {'pelvis': P, 'pitch': PITCH, 'neck': 18.0}
    for s, sg in (('L', -1), ('R', 1)):
        base['leg' + s] = {'foot': v3(46.0, ANKLE_H, sg * 38.0), 'pole': v3(1.0, 0.4, 0.9 * sg),
                           'toe_out': 20.0}
    J0 = solve(base)
    SL, SR = J0.p['shoulderL'], J0.p['shoulderR']
    # working elbow braced on the inside of the right thigh: the back of the upper arm rests on the
    # thigh's upper inner side, two thirds of the way to the knee (nearer the knee, the hanging
    # dumbbell would meet the shin)
    hipR, kneeR = J0.p['hipR'], J0.p['kneeR']
    d_t = unit(kneeR - hipR)
    E = hipR + d_t * (THIGH * 0.65) + unit(np.cross(Y, d_t) + Y) * 13.0
    E = SR + unit(E - SR) * UPPER
    d_u = unit(E - SR)
    # the forearm curls up in front of the chest, 35 degrees across the body: straight across,
    # towards the other shoulder, the dumbbell would pass through the chest of this forward lean
    bdir = X * math.cos(math.radians(35.0)) - Z * math.sin(math.radians(35.0))
    bdir = unit(bdir - np.dot(bdir, d_u) * d_u)
    # resting forearm along the left thigh, hand at the knee
    hipL, kneeL = J0.p['hipL'], J0.p['kneeL']
    handL = kneeL + unit(kneeL - hipL) * 2.0 + Y * 11.0
    elbowL = hipL + (kneeL - hipL) * 0.35 + Y * 12.0

    def pose(u):
        p = dict(base)
        e = math.radians(lerp(6.0, 130.0, u))
        d_f = d_u * math.cos(e) + bdir * math.sin(e)
        p['armR'] = {'hand': E + d_f * FORE, 'pole': -bdir}
        p['armL'] = {'hand': handL, 'pole': elbowL - (SL + handL) / 2}
        return p

    def equip(J, v, u):
        working_arm_only(v, 'R')
        # hanging, the palm faces the other leg (handle front to back, the dumbbell clear of the
        # shin, which is nearer the camera); it turns up as the weight rises
        ax = unit(X * (1.0 - smooth(0.0, 0.6, u)) + hinge_axis(J, 'R') * smooth(0.0, 0.6, u))
        return eq.bench(v, v3(-50.0, SEAT, 0.0), length=110.0) + \
            eq.dumbbell(v, J.p['handR'], ax, ('before', 'armR'))

    return pose, curl_rep(), equip


def wrist_curl(key, flex0, flex1):
    SEAT = BENCH_H
    PITCH = 26.0

    @exercise(key, 'biceps', 'side', muscles=['forearms'])
    def build():
        P = v3(0.0, SEAT + 9.0, 0.0)
        base = seated(0.0, seat_h=SEAT, pitch=PITCH, half=12.0)
        base['pelvis'] = P
        base['neck'] = -10.0
        SL, SR = shoulders(base)
        arms = {}
        for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
            # elbow on the thigh, forearm along it (the thighs open towards the knees), wrist just
            # past the knee: the dumbbells hang one each side of a knee, well apart, instead of
            # meeting between the knees
            E = v3(26.0, 67.8, sg * 14.5)
            E = S + unit(E - S) * UPPER
            W = E + unit(v3(25.8, -3.4, sg * 6.2)) * FORE_WRIST
            arms[s] = aim(S, E, W, X)

        def pose(u):
            p = dict(base)
            wf = lerp(flex0, flex1, u)
            for s in 'LR':
                p['arm' + s] = dict(arms[s], wrist_flex=wf)
            return p

        def equip(J, v, u):
            return flat_bench(v, -86.0, 16.0) + dumbbells(J, v, across)

        return pose, rep(1.2, 1.4, top=0.3, bottom=0.35), equip
    return build


wrist_curl('wristCurls', -55.0, 45.0)
wrist_curl('reverseWristCurls', -50.0, 40.0)


# ---- triceps: cable pushdowns (high pulley) ----------------------------------------------------------

HIGH_PULLEY = v3(56.0, 206.0, 0.0)


def pushdown_pose(u, lean=9.0, a=-2.0, e0=96.0, e1=2.0, spread=0.0):
    pose = standing(0.0, half=11.0, pitch=lean)
    SL, SR = shoulders(pose)
    e = lerp(e0, e1, u)
    for s, S in (('L', SL), ('R', SR)):
        arm = sag(S, a, e)[0]
        if spread:
            arm['hand'] = arm['hand'] + Z * (spread * u * (1 if s == 'R' else -1))
        pose['arm' + s] = arm
    return pose


def pushdown(key, rope=False, lean=9.0):
    @exercise(key, 'triceps', 'side', muscles=['triceps'])
    def build():
        def pose(u):
            return pushdown_pose(u, lean=lean, spread=6.0 if rope else 0.0)

        def equip(J, v, u):
            B = (J.p['handL'] + J.p['handR']) / 2
            B = v3(B[0], B[1], 0.0)
            if not rope:
                return eq.cable_stack(v, HIGH_PULLEY, B, tower_x=TOWER_X)
            clip = B + unit(HIGH_PULLEY - B) * 12.0
            items = eq.cable_stack(v, HIGH_PULLEY, clip, tower_x=TOWER_X)
            for s in 'LR':
                items += rope_items(v, J.p['hand' + s], clip, neutral_axis(J, s), ('before', 'arm' + s))
            return items

        return pose, rep(1.2, 1.5, top=0.35, bottom=0.4), equip
    return build


pushdown('tricepPushdowns')
pushdown('reverseGripTricepPushdowns', lean=6.0)
pushdown('ropeTricepExtensions', rope=True)


# ---- triceps: overhead extensions --------------------------------------------------------------------

def cup_dumbbell(J, v, z='back'):
    """A dumbbell hanging vertically from its top plate, cupped in both palms: the plate rests on
    the hands (not around them)."""
    H = (J.p['handL'] + J.p['handR']) / 2
    top = H + Y * 7.5
    return eq.dumbbell(v, top - Y * 12.6, Y, z, gap=False)


def overhead_two_hands(pose_base, a, e0=4.0, e1=128.0, elbow_z=14.5, hand_z=10.0):
    """Both hands on one dumbbell overhead; elbows by the ears. Phase 0 = arms extended. The hands
    hold the top plate near its rim and the forearms rise outside it, so the plate passes between
    them (nearer together, the forearms would cut through the plates)."""
    SL, SR = shoulders(pose_base)

    def pose(u):
        p = dict(pose_base)
        e = lerp(e0, e1, u)
        for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
            p['arm' + s] = arm_3d(S, a, e, sg * elbow_z, sg * hand_z)
        return p
    return pose


@exercise('overheadTricepExtension', 'triceps', 'side', muscles=['triceps'])
def overhead_tricep_extension():
    pose = overhead_two_hands(standing(0.0, half=11.0), 179.0)

    def equip(J, v, u):
        return cup_dumbbell(J, v)

    return pose, rep_down_first(1.6, 1.2, top=0.4, bottom=0.3), equip


@exercise('seatedTricepPress', 'triceps', 'side', muscles=['triceps'])
def seated_tricep_press():
    SEAT = BENCH_H
    PITCH = -6.0
    P = v3(0.0, SEAT + 9.0, 0.0)
    base = seated(0.0, seat_h=SEAT, pitch=PITCH, half=12.0)
    base['pelvis'] = P
    pose = overhead_two_hands(base, 184.0)
    hinge = back_hinge(P, PITCH, SEAT, back=-12.4)

    def equip(J, v, u):
        return seat_with_back(v, hinge, seat_len=40.0, back_deg=90.0 + PITCH, back_len=40.0) + cup_dumbbell(J, v)

    return pose, rep_down_first(1.6, 1.2, top=0.4, bottom=0.3), equip


@exercise('oneArmTricepExtension', 'triceps', 'side', muscles=['triceps'])
def one_arm_tricep_extension():
    base = standing(0.0, half=11.0)
    _, SR = shoulders(base)

    def pose(u):
        p = dict(base)
        p['armR'] = arm_3d(SR, 178.0, lerp(4.0, 132.0, u), 14.0, 9.0)
        return p

    def equip(J, v, u):
        working_arm_only(v, 'R')
        # the handle points at the camera: its near head is in front of the hand, as in 3D
        return eq.dumbbell(v, J.p['handR'], Z, ('before', 'armR'))

    return pose, rep_down_first(1.6, 1.2, top=0.4, bottom=0.3), equip


# ---- triceps: kickbacks ---------------------------------------------------------------------------

@exercise('tricepKickbacks', 'triceps', 'side', muscles=['triceps'])
def tricep_kickbacks():
    PITCH = 78.0
    P = v3(0.0, 94.0, 0.0)
    base = {'pelvis': P, 'pitch': PITCH, 'neck': 24.0}
    # the standing leg under its hip, the working arm just outside it: the hand and the dumbbell
    # sweep past the thigh, not through it
    base['legR'] = {'foot': v3(8.0, ANKLE_H, 12.0), 'pole': v3(1.0, 0.0, 0.2), 'toe_out': 6.0}
    base['legL'] = {'foot': v3(-57.0, 53.0, -9.0), 'pole': v3(0.2, -1.0, 0.0), 'foot_pitch': -150.0}
    SL, SR = shoulders(base)
    base['armL'] = {'hand': v3(SL[0] + 3.0, BENCH_H + 4.4, -14.0), 'pole': v3(-1.0, 0.0, -0.3),
                    'palm': True, 'palm_dir': X}
    A = -(PITCH - 6.0)

    def pose(u):
        p = dict(base)
        p['armR'] = arm_3d(SR, A, lerp(96.0, 3.0, u), SR[2] + 3.0, SR[2] + 7.0)
        return p

    def equip(J, v, u):
        working_arm_only(v, 'R')
        return flat_bench(v, -60.0, 86.0, zc=-12.0) + \
            eq.dumbbell(v, J.p['handR'], neutral_axis(J, 'R'), ('before', 'armR'))

    return pose, rep(1.2, 1.5, top=0.35, bottom=0.4), equip
