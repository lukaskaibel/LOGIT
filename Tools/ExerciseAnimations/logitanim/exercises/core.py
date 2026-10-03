"""Core: floor work on the back, planks and holds, hanging raises, rotations, carries and the
Turkish get-up.

Supine work is side-on with the head to the left. The rig's torso is one rigid piece, so a curl
pivots the whole trunk: a body on the floor is settled every frame so that its lowest point rests
on the floor (curls roll onto the glutes, reverse curls onto the upper back), and a resting head
is solved onto the floor through the neck angle.
"""
from .common import *
from functools import lru_cache

from ..rig import solve
from ..body import side_view, view
from ..spec import R_HEAD, HEAD_UP, HEAD_FWD, R_HAND, TOE, HEEL, R_HEEL, R_SHANK, R_FORE
from ..sdf import V, Circle, Cone, RBox, Union

SINK = 0.4                  # soft contacts settle this far into the floor (cm)
WRIST_FLOOR = 4.4 - SINK    # wrist height of a flat palm on the floor
FIST_FLOOR = R_HAND - SINK  # grip centre of a fist resting on the floor
TOE_FLOOR = R_TOE - SINK    # toe centre of a foot standing on its toes
KNEE_FLOOR = R_SHANK[0] - SINK
ELBOW_FLOOR = R_FORE[0] - SINK


# ---- contacts ---------------------------------------------------------------------------------

def low_y(shape):
    """Lowest point of a union of circles and round cones (their end circles bound them)."""
    if isinstance(shape, Circle):
        return shape.c[1] - shape.r
    if isinstance(shape, Cone):
        return min(shape.a[1] - shape.ra, shape.b[1] - shape.rb)
    if isinstance(shape, Union):
        return min(low_y(s) for s in shape.shapes)
    return shape.bbox()[1]


def settle(pose, floor=0.0, anchor=None):
    """Shift the pelvis so the trunk's lowest point rests on the floor. anchor=(joint, x) also
    slides the body so that joint stays at x (the pivot that must not skid)."""
    J = solve(pose)
    dy = floor - SINK - low_y(side_view(J).clip['torso'])
    dx = 0.0 if anchor is None else anchor[1] - J.p[anchor[0]][0]
    p = dict(pose)
    p['pelvis'] = np.asarray(pose['pelvis'], float) + v3(dx, dy, 0.0)
    return p


def head_frame(tf, neck):
    n = math.radians(neck)
    return tf.u * math.cos(n) - tf.f * math.sin(n), tf.f * math.cos(n) + tf.u * math.sin(n)


def neck_on_floor(pose, floor=0.0):
    """The neck angle (deg) that rests the back of the head on the floor, or None."""
    J = solve(pose)
    tf = J.torso_frame
    nb = J.p['neck']
    A = HEAD_UP * tf.u[1] + HEAD_FWD * tf.f[1]
    B = -HEAD_UP * tf.f[1] + HEAD_FWD * tf.u[1]
    C = floor - SINK + R_HEAD - nb[1]
    R = math.hypot(A, B)
    if abs(C) > R:
        return None
    d = math.atan2(B, A)
    sols = [(math.degrees(d + s * math.acos(C / R)) + 180.0) % 360.0 - 180.0 for s in (1, -1)]
    return min(sols, key=abs)


def rest_head(pose, neck=None, floor=0.0):
    """neck=None rests the head on the floor; otherwise use `neck` unless the head would sink."""
    p = dict(pose)
    nf = neck_on_floor(pose, floor)
    if neck is None:
        p['neck'] = nf if nf is not None else 0.0
        return p
    p['neck'] = neck
    if nf is not None:
        J = solve(p)
        if J.p['head'][1] - R_HEAD < floor - SINK:
            p['neck'] = nf
    return p


# ---- lying on the back --------------------------------------------------------------------------

def lying(curl=0.0, tilt=0.0, x=0.0, twist=0.0, bend=0.0, legs=None):
    """Supine, head to the left. curl: trunk raised off the floor (deg, spine pitch over the pelvis);
    tilt: pelvis rolled hips-up (deg); twist: trunk rotation about the spine (+ = left shoulder up)."""
    p = {'pelvis': v3(x, 13.0, 0.0), 'p_pitch': -90.0 - tilt, 'pitch': curl, 'roll': bend,
         'yaw': twist, 'neck': 0.0}
    for s in 'LR':
        p['leg' + s] = dict((legs or {}).get(s, {'hip': 0.0, 'knee': 0.0, 'ankle': 30.0}))
    return p


def feet_flat(x, half=13.0):
    """Knees up, feet flat on the floor at x (the knees point at the ceiling)."""
    return {s: {'foot': v3(x, ANKLE_H, sg * half), 'toe_out': 6.0, 'pole': v3(0.2, 1.0, 0.18 * sg)}
            for s, sg in (('L', -1), ('R', 1))}


def fk_legs(hip, knee=0.0, ankle=30.0, abd=0.0, hip_l=None, knee_l=None, ankle_l=None, abd_l=None):
    return {'R': {'hip': hip, 'knee': knee, 'ankle': ankle, 'abd': abd},
            'L': {'hip': hip if hip_l is None else hip_l, 'knee': knee if knee_l is None else knee_l,
                  'ankle': ankle if ankle_l is None else ankle_l, 'abd': abd if abd_l is None else abd_l}}


def palms_down(pose, half=26.0):
    """Arms by the sides, palms flat on the floor next to the hips, fingers towards the feet. The
    wrist sits nearly an arm's length from the shoulder so the arm lies straight."""
    S = solve(pose).p['shoulderR']
    reach = UPPER + FORE_WRIST - 0.6
    dz = half - S[2]
    dy = S[1] - WRIST_FLOOR
    x = S[0] + math.sqrt(max(reach ** 2 - dz ** 2 - dy ** 2, 1.0))
    return both(v3(x, WRIST_FLOOR, half), [0.0, 0.3, 1.0], palm=True, palm_dir=X)


HEAD_ON_HANDS = 5.0         # lying on hands laced behind the head, the head rests this high


def hands_behind_head(pose, spread=9.0, back=11.5, pole=(0.35, 1.0, 0.9)):
    """Fingers laced behind the head, elbows up and open. pole = (sideways, world up, towards the
    head). The palms cup the back of the head on either side, just behind the ears: resting against
    it, not inside it (lying down, the head rests on them: see HEAD_ON_HANDS). Drawn with
    near_arm_behind='forearm': the near forearm and hand tuck in behind the head (they reach behind
    it, close to the midline) while the upper arm, on the camera side of the body, stays in front
    and shows the elbow wing; the pole is in world 'up' so a twisted trunk never drops an elbow
    below itself."""
    J = solve(pose)
    tf = J.torso_frame
    hu, hfw = head_frame(tf, pose.get('neck', 0.0))
    H = J.p['head']
    out = {}
    for s, sg in (('L', -1), ('R', 1)):
        hand = H - hfw * back - hu * 1.5 + tf.r * (sg * spread)
        out['arm' + s] = {'hand': hand, 'pole': Z * (sg * pole[0]) + Y * pole[1] + tf.u * pole[2]}
    return out


def curl_up(curl, legs, x=0.0, neck=None, twist=0.0, bend=0.0, anchor=None, tilt=0.0, lift=None, head_floor=0.0):
    """A settled supine pose with the head resting (neck=None) or held (neck=deg). lift=(neck, w)
    raises the head off the floor by blending from the resting neck angle to `neck` by w.
    head_floor: what a resting head lies on (HEAD_ON_HANDS with the hands laced under it)."""
    p = settle(lying(curl, tilt, x, twist, bend, legs), anchor=anchor)
    if lift is not None:
        nf = neck_on_floor(p, head_floor)
        return rest_head(p, lerp(nf if nf is not None else 0.0, lift[0], lift[1]), head_floor)
    return rest_head(p, neck, head_floor)


# ---- supine exercises ---------------------------------------------------------------------------

@exercise('situps', 'abdominals', 'side', muscles=['abs', 'hipflexors'], near_arm_behind='forearm')
def situps():
    legs = feet_flat(42.0)

    def pose(u):
        c = lerp(0.0, 84.0, u)
        p = curl_up(c, legs, neck=lerp(4.0, -18.0, smooth(0.0, 0.35, u)), head_floor=HEAD_ON_HANDS)
        p.update(hands_behind_head(p))
        return p

    return pose, rep(1.35, 1.55, top=0.35, bottom=0.25), None


@exercise('crunches', 'abdominals', 'side', muscles=['abs'], near_arm_behind='forearm')
def crunches():
    legs = feet_flat(42.0)

    def pose(u):
        c = lerp(3.0, 30.0, u)
        p = curl_up(c, legs, neck=lerp(-4.0, -20.0, u), head_floor=HEAD_ON_HANDS)
        p.update(hands_behind_head(p))
        return p

    return pose, rep(1.0, 1.4, top=0.3, bottom=0.45), None


@exercise('reverseCrunches', 'abdominals', 'side', muscles=['abs'])
def reverse_crunches():
    def pose(u):
        tilt = lerp(0.0, 34.0, u)
        legs = fk_legs(lerp(90.0, 128.0, u), lerp(92.0, 104.0, u), 25.0)
        p = settle(lying(0.0, tilt, 0.0, legs=legs), anchor=('shoulder_c', -49.0))
        p = rest_head(p)
        p.update(palms_down(p))
        return p

    return pose, rep(1.25, 1.5, top=0.35, bottom=0.25), None


@exercise('legRaises', 'abdominals', 'side', muscles=['abs', 'hipflexors'])
def leg_raises():
    def pose(u):
        legs = fk_legs(lerp(7.0, 90.0, u), 0.0, lerp(38.0, 20.0, u))
        p = rest_head(settle(lying(0.0, lerp(0.0, 5.0, smooth(0.6, 1.0, u)), legs=legs)))
        p.update(palms_down(p))
        return p

    return pose, rep(1.45, 1.6, top=0.3, bottom=0.3), None


def alternate(hold0, out, hold1, back, sides=2):
    """Phase 0 -> 1 -> 0 on one side, then 2 -> 3 -> 2 on the other (u in [0, 2*sides))."""
    segs = []
    for k in range(sides):
        a = 2.0 * k
        segs += [(hold0, a, a), (out, a, a + 1), (hold1, a + 1, a + 1), (back, a + 1, a + 2)]
    return Timeline(segs)


def side_phase(u, sides=2):
    """(side index, 0..1 extension) from an `alternate` phase."""
    k = int(math.floor(u / 2.0)) % sides
    w = u - 2.0 * math.floor(u / 2.0)
    return k, (w if w <= 1.0 else 2.0 - w)


def cycles(period, n):
    """A linear phase that runs 0 -> 1 once per period (for continuous, cyclic movement)."""
    return Timeline([(period, 0.0, 1.0)] * n, linear=True)


@exercise('obliqueCrunches', 'abdominals', 'side', muscles=['obliques', 'abs'], near_arm_behind='forearm')
def oblique_crunches():
    legs = feet_flat(42.0)

    def pose(u):
        p = curl_up(lerp(3.0, 36.0, u), legs, neck=lerp(-4.0, -18.0, u), twist=lerp(0.0, -34.0, u),
                    head_floor=HEAD_ON_HANDS)
        # elbows open enough that the forearm swinging across stays beside the head, not in it
        p.update(hands_behind_head(p, pole=(0.8, 1.0, 0.25)))
        return p

    return pose, rep(1.1, 1.4, top=0.3, bottom=0.4), None


@exercise('bicycles', 'abdominals', 'side', muscles=['obliques', 'abs', 'hipflexors'], near_arm_behind='forearm')
def bicycles():
    def leg(th):
        # th = 0: knee pulled in to the chest; th = pi: leg long and low. The knee leads the hip a
        # little so each foot runs round a pedal loop instead of both legs meeting mid-stroke.
        ch = 0.5 + 0.5 * math.cos(th)
        ck = 0.5 + 0.5 * math.cos(th - 0.5)
        return {'hip': lerp(26.0, 100.0, ch), 'knee': lerp(6.0, 112.0, ck), 'ankle': lerp(40.0, 20.0, ck)}

    def pose(u):
        th = 2 * math.pi * u
        legs = {'R': leg(th), 'L': leg(th + math.pi)}
        # the right knee in brings the left elbow across: left shoulder up (+ twist), and vice versa
        p = curl_up(24.0 + 3.0 * abs(math.cos(th)), legs, neck=-16.0, twist=30.0 * math.cos(th),
                    head_floor=HEAD_ON_HANDS)
        # elbows open enough that the forearm swinging across stays beside the head, not in it
        p.update(hands_behind_head(p, pole=(0.8, 1.0, 0.25)))
        return p

    return pose, cycles(2.6, 2), None


@exercise('vUps', 'abdominals', 'side', muscles=['abs', 'hipflexors'])
def v_ups():
    def pose(u):
        q = lerp(5.0, 60.0, u)
        h = lerp(6.0, 70.0, u)
        p = curl_up(q, fk_legs(h, 0.0, 40.0), neck=lerp(-6.0, -14.0, u))
        for s in 'LR':
            p['arm' + s] = {'flex': lerp(184.0, 104.0, u), 'abd': 6.0, 'elbow': 4.0}
        return p

    return pose, rep(1.05, 1.35, top=0.3, bottom=0.25), None


def hands_under_hips(pose):
    P = pose['pelvis']
    return both(v3(P[0] - 3.0, WRIST_FLOOR, 11.0), [0.0, 0.4, 1.0], palm=True, palm_dir=X)


@exercise('flutterKicks', 'abdominals', 'side', muscles=['abs', 'hipflexors'])
def flutter_kicks():
    def pose(u):
        s = math.sin(2 * math.pi * u)
        p = curl_up(0.0, fk_legs(13.0 + 8.0 * s, 0.0, 45.0, hip_l=13.0 - 8.0 * s))
        p.update(hands_under_hips(p))
        return p

    return pose, cycles(1.0, 4), None


@exercise('scissorKicks', 'abdominals', 'side', muscles=['abs', 'hipflexors', 'adductors'])
def scissor_kicks():
    def pose(u):
        s = math.sin(2 * math.pi * u)
        abd = 2.0 + 11.0 * math.cos(4 * math.pi * u)      # open at 0 and 1/2, crossed in between
        # crossed, the top leg is a leg's width above the other, so it passes over it (not through)
        p = curl_up(0.0, fk_legs(16.0 + 6.0 * s, 0.0, 45.0, abd=abd, hip_l=16.0 - 6.0 * s))
        p.update(hands_under_hips(p))
        return p

    return pose, cycles(1.7, 2), None


@exercise('deadBug', 'abdominals', 'side', muscles=['abs'])
def dead_bug():
    table = {'hip': 90.0, 'knee': 90.0, 'ankle': 15.0}
    long = {'hip': 14.0, 'knee': 4.0, 'ankle': 30.0}

    def pose(u):
        k, e = side_phase(u)
        # side 0: right arm + left leg reach long; side 1: left arm + right leg
        arm_side, leg_side = ('R', 'L') if k == 0 else ('L', 'R')
        legs = {leg_side: blend(table, long, e), {'L': 'R', 'R': 'L'}[leg_side]: dict(table)}
        p = curl_up(0.0, legs)
        for s in 'LR':
            p['arm' + s] = {'flex': lerp(90.0, 178.0, e) if s == arm_side else 90.0, 'abd': 4.0, 'elbow': 3.0}
        return p

    return pose, alternate(0.35, 1.4, 0.3, 1.3), None


@exercise('hollowBodyHold', 'abdominals', 'side', muscles=['abs', 'hipflexors'])
def hollow_body_hold():
    def body(u):
        return curl_up(lerp(0.0, 15.0, u), fk_legs(lerp(0.0, 14.0, u), 0.0, lerp(30.0, 45.0, u)),
                       lift=(-16.0, u))

    def arms(p, flex):
        q = dict(p)
        for s in 'LR':
            q['arm' + s] = {'flex': flex, 'abd': 5.0, 'elbow': 2.0}
        return q

    # lying: the arms overhead rest on the floor
    flat = body(0.0)
    rest = bisect(lambda fl: solve(arms(flat, fl)).p['handR'][1] - FIST_FLOOR, 170.0, 200.0)

    def pose(u):
        return arms(body(u), lerp(rest, 176.0, u))

    return pose, Timeline([(0.5, 0, 0), (1.1, 0, 1), (2.2, 1, 1), (1.1, 1, 0)]), None


# ---- prone, kneeling and on all fours -----------------------------------------------------------
# Face-down work keeps the pelvis frame upright and pitches the spine (+90 = level, head right), so
# IK feet read their toe direction from +x. A foot on its toes is solved about the toe contact.

def dir2(deg):
    a = math.radians(deg)
    return v3(math.cos(a), math.sin(a))


def toe_offset(fp):
    """Toe centre relative to the ankle for an IK foot pitched fp (deg) about +x."""
    a = math.radians(fp)
    t = v3(math.cos(a), math.sin(a))
    n = v3(-math.sin(a), math.cos(a))
    return n * TOE[0] + t * TOE[1]


TOE_ANGLE = math.degrees(math.atan2(TOE[0], TOE[1]))    # toe direction relative to the foot axis


def pitch_to_toe(A, T):
    """Foot pitch that puts the toe centre at T from the ankle A."""
    d = np.asarray(T, float) - np.asarray(A, float)
    return math.degrees(math.atan2(d[1], d[0])) - TOE_ANGLE


def circles(c0, r0, c1, r1, up=True):
    """Intersection of two circles in the xy plane (the upper or the lower one)."""
    c0, c1 = v3(c0[0], c0[1]), v3(c1[0], c1[1])
    dd = np.linalg.norm(c1 - c0)
    e = (c1 - c0) / max(dd, 1e-9)
    d = min(max(dd, abs(r0 - r1) + 1e-6), r0 + r1 - 1e-6)
    a = (r0 * r0 - r1 * r1 + d * d) / (2 * d)
    h = math.sqrt(max(r0 * r0 - a * a, 0.0))
    n = v3(-e[1], e[0])
    p1, p2 = c0 + e * a + n * h, c0 + e * a - n * h
    return max(p1, p2, key=lambda p: p[1]) if up else min(p1, p2, key=lambda p: p[1])


def bisect(f, lo, hi, n=50):
    """Root of a monotonic f on [lo, hi]."""
    neg = f(lo) < 0
    for _ in range(n):
        mid = (lo + hi) / 2
        if (f(mid) < 0) == neg:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def toe_leg(toe, fp, z, pole=(0.0, -1.0, 0.0)):
    """IK leg standing on its toes at `toe` (xy), the foot pitched fp: the ankle follows."""
    A = v3(toe[0], toe[1]) - toe_offset(fp)
    return {'foot': v3(A[0], A[1], z), 'foot_pitch': fp, 'pole': np.array(pole, float)}


def kneel_leg(H, z, fp=-100.0, fwd=1.0):
    """IK leg kneeling: knee on the floor below (fwd=0) or ahead of the hip H, shin back, toes
    tucked under."""
    dy = H[1] - KNEE_FLOOR
    kx = H[0] + fwd * math.sqrt(max(THIGH ** 2 - dy * dy, 0.0))
    K = v3(kx, KNEE_FLOOR)
    ay = TOE_FLOOR - toe_offset(fp)[1]
    A = v3(kx - math.sqrt(SHANK ** 2 - (ay - KNEE_FLOOR) ** 2), ay)
    mid = (v3(H[0], H[1]) + A) / 2
    return {'foot': v3(A[0], A[1], z), 'foot_pitch': fp, 'pole': K - mid}


def kneel_leg_at(H, K, z, fp=-100.0):
    """IK leg kneeling on a fixed knee point K (on the floor) with the hip at H (|H-K| = THIGH):
    the shin lies back along the floor, toes tucked. Unlike kneel_leg, the knee stays put however
    far the hips travel over it."""
    ay = TOE_FLOOR - toe_offset(fp)[1]
    A = v3(K[0] - math.sqrt(SHANK ** 2 - (ay - KNEE_FLOOR) ** 2), ay)
    mid = (v3(H[0], H[1]) + A) / 2
    return {'foot': v3(A[0], A[1], z), 'foot_pitch': fp, 'pole': v3(K[0], K[1]) - mid}


def trunk(H, S):
    """Pelvis and spine pitch that put the shoulder line at S with the hips at H (|S-H| = TORSO)."""
    d = np.asarray(S, float) - np.asarray(H, float)
    return {'pelvis': v3(H[0], H[1], 0.0), 'pitch': math.degrees(math.atan2(d[0], d[1]))}


def line_on_toes(S, L=SHANK + THIGH + TORSO):
    """A straight body from the toes (on the floor) to the shoulder line at S: (pitch g of the
    line in deg, toe contact T)."""
    def s_y(g):
        A = -toe_offset(g - 90.0)
        return TOE_FLOOR + A[1] + L * math.sin(math.radians(g)) - S[1]
    g = bisect(s_y, 0.0, 60.0)
    A = -toe_offset(g - 90.0)
    return g, v3(S[0] - A[0] - L * math.cos(math.radians(g)), TOE_FLOOR)


class ForearmPlank:
    """Forearms on the floor, elbows under the shoulders, a rigid line to the toes. The kneeling
    version shares the shoulders and the toe contact, so rising onto the toes only lifts the knees."""

    def __init__(self, xs=0.0):
        self.S = v3(xs, ELBOW_FLOOR + UPPER)
        self.g, self.T = line_on_toes(self.S)
        dk = THIGH + TORSO
        K = v3(xs - math.sqrt(dk * dk - (self.S[1] - KNEE_FLOOR) ** 2), KNEE_FLOOR)
        A = circles(K, SHANK, self.T, float(np.hypot(*TOE)), up=True)
        self.fp_k = pitch_to_toe(A, self.T)
        self.beta_k = math.degrees(math.atan2(self.S[1] - K[1], self.S[0] - K[0]))
        self.fp_p = self.g - 90.0

    def pose(self, u, neck=10.0):
        beta = lerp(self.beta_k, self.g, u)
        H = self.S - dir2(beta) * TORSO
        p = trunk(H, self.S)
        p['neck'] = neck
        fp = lerp(self.fp_k, self.fp_p, u)
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = toe_leg(self.T, fp, sg * 9.0)
            sh = v3(self.S[0], self.S[1], sg * SHOULDER_HALF)
            E = v3(self.S[0], ELBOW_FLOOR, sg * 16.0)
            hand = v3(self.S[0] + FORE - 0.3, FIST_FLOOR, sg * 11.0)
            p['arm' + s] = {'hand': hand, 'pole': E - (sh + hand) / 2}
        return p


@exercise('plank', 'abdominals', 'side', muscles=['abs'])
def plank():
    pl = ForearmPlank()
    return pl.pose, Timeline([(0.6, 0, 0), (1.1, 0, 1), (2.2, 1, 1), (1.1, 1, 0)]), None


class HighPlank:
    """Straight arms, palms under the shoulders, a rigid line to the toes."""

    def __init__(self, xs=0.0, hand_z=20.0):
        self.hand_z = hand_z
        reach = math.sqrt((UPPER + FORE_WRIST - 0.4) ** 2 - (hand_z - SHOULDER_HALF) ** 2)
        self.S = v3(xs, WRIST_FLOOR + reach)
        self.g, self.T = line_on_toes(self.S)
        self.fp = self.g - 90.0
        self.H = self.S - dir2(self.g) * TORSO


@exercise('mountainClimbers', 'abdominals', 'side', muscles=['abs', 'hipflexors', 'quads'])
def mountain_climbers():
    pl = HighPlank()
    A0 = v3(pl.T[0], pl.T[1]) - toe_offset(pl.fp)
    back = math.degrees(math.atan2(A0[1] - pl.H[1], A0[0] - pl.H[0]))    # hip -> ankle in the plank

    def drive(ph):
        # 0 = back on the toes, 1 = knee in; a running rhythm: the legs swap quickly and dwell at
        # the ends instead of meeting half-way
        k = 1.8
        return 0.5 - 0.5 * math.tanh(k * math.cos(2 * math.pi * ph)) / math.tanh(k)

    fp_in = -96.0                                        # toes tucked under the hips
    T_in = v3(pl.H[0] - 4.0, TOE_FLOOR)
    A_in = T_in - toe_offset(fp_in)
    POLE = v3(1.0, -0.7, 0.0)                            # knee drives forward towards the chest

    def planted(H):
        # on the toes behind: pivot the foot so a straight leg still reaches
        A = circles(v3(H[0], H[1]), SHANK + THIGH - 0.3, pl.T, float(np.hypot(*TOE)), up=True)
        return A, pitch_to_toe(A, pl.T)

    def foot(H, c):
        """Ankle target and foot pitch at drive c: off the toes behind, forward on a low arc with
        the foot pointed, onto the toes under the hips."""
        A0, fp0 = planted(H)
        A = A0 + (A_in - A0) * c + v3(0.0, 9.0 * math.sin(math.pi * c))
        return A, lerp(fp0, fp_in, c) + 55.0 * math.sin(math.pi * c)

    def hips(rise):
        th = math.asin(min((pl.S[1] - (pl.H[1] + rise)) / TORSO, 1.0))
        return pl.S - dir2(math.degrees(th)) * TORSO

    def pose(u):
        cs = {s: drive(u + ph) for s, ph in (('R', 0.0), ('L', 0.5))}
        # the hips lift just enough for a knee swinging through under them to clear the floor
        rise = 0.0
        for _ in range(3):
            H = hips(rise)
            low = 1e9
            for s, sg in (('L', -1), ('R', 1)):
                A, _ = foot(H, cs[s])
                K, _ = ik2(v3(H[0], H[1], sg * HIP_HALF), v3(A[0], A[1], sg * 9.0), THIGH, SHANK, POLE)
                low = min(low, K[1])
            rise = max(0.0, rise + KNEE_FLOOR + 2.0 - low)
        H = hips(rise)
        p = trunk(H, pl.S)
        p['neck'] = 12.0
        p.update(both(v3(pl.S[0], WRIST_FLOOR, pl.hand_z), [-1.0, 0.1, 0.3], palm=True, palm_dir=X))
        for s, sg in (('L', -1), ('R', 1)):
            A, fp = foot(H, cs[s])
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 9.0), 'foot_pitch': fp, 'pole': POLE}
        return p

    return pose, cycles(1.3, 3), None


@exercise('birdDog', 'abdominals', 'side', muscles=['abs', 'erectors', 'glutes'])
def bird_dog():
    H = v3(0.0, KNEE_FLOOR + THIGH - 0.01)
    reach = UPPER + FORE_WRIST - 0.6
    sy = WRIST_FLOOR + reach
    S = v3(math.sqrt(TORSO ** 2 - (sy - H[1]) ** 2), sy)
    base = trunk(H, S)
    base['neck'] = 14.0

    def pose(u):
        k, e = side_phase(u)
        arm_s, leg_s = ('R', 'L') if k == 0 else ('L', 'R')
        p = dict(base)
        for s, sg in (('L', -1), ('R', 1)):
            kneel = kneel_leg(H, sg * 10.0, fwd=0.0)
            if s == leg_s:
                A = kneel['foot']
                long = v3(H[0] - 84.0, H[1] + 2.0, sg * 9.0)
                p['leg' + s] = {'foot': A + (long - A) * e, 'foot_pitch': lerp(kneel['foot_pitch'], -90.0, e),
                                'pole': v3(0.3, -1.0, 0.0)}
            else:
                p['leg' + s] = kneel
            wr = v3(S[0], WRIST_FLOOR, sg * 18.0)
            if s == arm_s:
                # the straight arm swings forward about the shoulder, up to level
                th = math.radians(lerp(0.0, 94.0, e))
                wr = v3(S[0] + reach * math.sin(th), S[1] - reach * math.cos(th), sg * lerp(18.0, 14.0, e))
            p['arm' + s] = {'hand': wr, 'pole': v3(-1.0, 0.1, 0.25 * sg), 'palm': True, 'palm_dir': X}
        return p

    return pose, alternate(0.4, 1.2, 0.6, 1.1), None


WHEEL_R = 12.0
WHEEL_HALF = 3.0        # 3D: half the tyre's width; the hub stands a little proud of it
GRIP_END = 14.0         # 3D: the handles run out along the axle into the fists (at +-11), ending inside them


def wheel3d(c3, ang):
    """3D: the ab wheel on its axle across the hands (z): the tyre, its face, three spokes turned
    by the rolling angle `ang` (thin slabs through the wheel, a hair proud of the face on both
    sides), the hub and the handles."""
    spec = eq.cyl3d(c3, Z, WHEEL_R, WHEEL_HALF, 'plate_rim') + eq.cyl3d(c3, Z, WHEEL_R - 3.0, WHEEL_HALF + 0.06, 'plate')
    for k in range(3):
        a = ang + k * 2 * math.pi / 3
        d = v3(math.cos(a), math.sin(a), 0.0)
        # what the 2D's spoke covers: from the hub out to WHEEL_R - 3.4, 1.1 round it
        spec += eq.box3d(c3 + d * ((WHEEL_R - 3.4) / 2), d, np.cross(Z, d), Z, (WHEEL_R - 3.4) / 2 + 1.1, 1.1,
                         WHEEL_HALF + 0.15, 1.1, 'plate_rim')
    return spec + eq.cyl3d(c3, Z, 3.2, WHEEL_HALF + 1.0, 'metal') + eq.cyl3d(c3, Z, 1.8, GRIP_END, 'metal')


@exercise('abWheelRollout', 'abdominals', 'side', muscles=['abs', 'lats'])
def ab_wheel_rollout():
    K = v3(0.0, KNEE_FLOOR)
    grip_z = 11.0
    arm = math.sqrt((ARM - 0.4) ** 2 - (grip_z - SHOULDER_HALF) ** 2)

    def body(u):
        a = lerp(-8.0, 66.0, u)          # thigh lean from vertical
        b = lerp(71.0, 74.0, u)          # trunk lean from vertical
        H = K + THIGH * v3(math.sin(math.radians(a)), math.cos(math.radians(a)))
        S = H + TORSO * v3(math.sin(math.radians(b)), math.cos(math.radians(b)))
        G = v3(S[0] + math.sqrt(max(arm ** 2 - (S[1] - WHEEL_R) ** 2, 0.0)), WHEEL_R)
        return H, S, G

    def pose(u):
        H, S, G = body(u)
        p = trunk(H, S)
        p['neck'] = lerp(28.0, 18.0, u)
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = kneel_leg_at(H, K, sg * 10.0)       # knees stay planted; only the body rolls
        p.update(both(v3(G[0], G[1], grip_z), [-0.3, -1.0, 0.4]))
        return p

    x0 = body(0.0)[2][0]

    def equip(J, v, u):
        G = (J.p['handL'] + J.p['handR']) / 2
        c = v.cam.p(v3(G[0], WHEEL_R, 0.0))
        ang = -(G[0] - x0) / WHEEL_R          # rolling without slipping
        z = ('before', 'armR')
        items = [Item(Circle(c, WHEEL_R), 'plate_rim', z, spec3d=wheel3d(v3(G[0], WHEEL_R, 0.0), ang)),
                 Item(Circle(c, WHEEL_R - 3.0), 'plate', z, spec3d=[])]
        for k in range(3):              # three spokes turn with the wheel
            a = ang + k * 2 * math.pi / 3
            items.append(Item(Cone(c, c + V(math.cos(a), math.sin(a)) * (WHEEL_R - 3.4), 1.1), 'plate_rim', z,
                              spec3d=[]))
        return items + [Item(Circle(c, 3.2), 'metal', z, spec3d=[])]

    return pose, rep(1.6, 1.5, top=0.4, bottom=0.25), equip


# ---- dragon flag --------------------------------------------------------------------------------

@exercise('dragonFlags', 'abdominals', 'side', muscles=['abs'], near_arm_behind='forearm')
def dragon_flags():
    XS = 0.0                    # shoulder line: the pivot on the upper back
    end = XS - 44.0             # head end of the bench, gripped behind the head

    def pose(u):
        g = lerp(68.0, 13.0, u)             # body line above level: straight from shoulders to toes
        p = lying(0.0, g, legs=fk_legs(0.0, 0.0, 42.0))
        p = settle(p, floor=BENCH_H, anchor=('shoulder_c', XS))
        p = rest_head(p, floor=BENCH_H)
        # the fists close around the head end of the pad, behind the head and close to its midline
        # (so the near forearm is drawn behind the head; the upper arm, out at the shoulder, passes
        # in front of it); they used to sit inside the pad
        p.update(both(v3(end - 2.5, BENCH_H + 1.0, 8.0), [0.4, 1.0, 0.5]))
        return p

    def equip(J, v, u):
        return eq.bench(v, v3(end + 62.0, BENCH_H, 0.0), length=124.0)

    return pose, rep_down_first(2.0, 1.4, top=0.45, bottom=0.25), equip


# ---- hanging from a bar (seen end-on) ------------------------------------------------------------

BAR_Y = 232.0

MASS = [('head', 0.08), ('trunk', 0.46)] + [(k + s, m) for s in 'LR' for k, m in
                                            (('upper', 0.03), ('fore', 0.025), ('thigh', 0.10),
                                             ('shank', 0.045), ('foot', 0.015))]


def com(J):
    """Whole-body centre of mass from segment midpoints."""
    pt = {'head': J.p['head'], 'trunk': (J.p['pelvis'] + J.p['shoulder_c']) / 2}
    for s in 'LR':
        pt['upper' + s] = (J.p['shoulder' + s] + J.p['elbow' + s]) / 2
        pt['fore' + s] = (J.p['elbow' + s] + J.p['hand' + s]) / 2
        pt['thigh' + s] = (J.p['hip' + s] + J.p['knee' + s]) / 2
        pt['shank' + s] = (J.p['knee' + s] + J.p['ankle' + s]) / 2
        pt['foot' + s] = (J.p['heel' + s] + J.p['toe' + s]) / 2
    tot = sum(m for _, m in MASS)
    return sum(pt[k] * m for k, m in MASS) / tot


def hang(hip, knee, ankle=25.0, tilt=0.0, extend=0.0, grip=24.0, bar_x=0.0, neck=0.0, com_dx=0.0):
    """Hanging from the bar at (bar_x, BAR_Y): straight arms, and the whole body swung about the
    grip so its centre of mass sits under the bar (or com_dx ahead of it, for a kipping swing).
    hip/knee: leg flexion (FK); tilt: pelvis curled under (deg); extend: trunk pulled back from the
    arm line by the lats (deg)."""
    lp = math.sqrt((ARM - 0.35) ** 2 - (grip - SHOULDER_HALF) ** 2)

    def build(psi):
        a = math.radians(psi)               # arm angle from vertical, + = shoulders behind the bar
        S = v3(bar_x - lp * math.sin(a), BAR_Y - lp * math.cos(a))
        phi = psi + extend                  # trunk lean, + = shoulders ahead of the hips
        P = S - TORSO * v3(math.sin(math.radians(phi)), math.cos(math.radians(phi)))
        p = {'pelvis': P, 'p_pitch': phi - tilt, 'pitch': tilt, 'neck': neck}
        for s in 'LR':
            p['leg' + s] = {'hip': hip, 'abd': 1.5, 'knee': knee, 'ankle': ankle}
        p.update(both(v3(bar_x, BAR_Y, grip), [0.3, -1.0, 0.8]))
        return p

    psi = bisect(lambda a: com(solve(build(a)))[0] - (bar_x + com_dx), -40.0, 70.0, n=32)
    return build(psi)


def bar_end(J, v, u):
    return eq.fixed_bar(v, v3(0.0, BAR_Y, 0.0))


@exercise('hangingKneeRaises', 'abdominals', 'side', muscles=['abs', 'hipflexors'], floor=False)
def hanging_knee_raises():
    def pose(u):
        return hang(lerp(0.0, 116.0, u), lerp(2.0, 112.0, smooth(0.0, 0.8, u)), lerp(20.0, 30.0, u),
                    tilt=lerp(0.0, 16.0, u))

    return pose, rep(1.25, 1.55, top=0.45, bottom=0.35), bar_end


@exercise('hangingLegRaises', 'abdominals', 'side', muscles=['abs', 'hipflexors'], floor=False)
def hanging_leg_raises():
    def pose(u):
        return hang(lerp(0.0, 98.0, u), lerp(2.0, 3.0, u), lerp(22.0, 40.0, u), tilt=lerp(0.0, 12.0, u))

    return pose, rep(1.4, 1.7, top=0.45, bottom=0.3), bar_end


@exercise('toesToBar', 'abdominals', 'side', muscles=['abs', 'hipflexors', 'lats'], floor=False)
def toes_to_bar():
    # hang -> a small swing through (chest forward, legs back) -> pike until the toes touch the
    # bar between the hands at the back of the swing -> down under control
    k_hang = dict(hip=0.0, knee=2.0, ankle=22.0, tilt=0.0, extend=0.0, com_dx=0.0)
    k_arch = dict(hip=-14.0, knee=8.0, ankle=30.0, tilt=-6.0, extend=12.0, com_dx=7.0)
    # the toes touch the bar's front edge (at 135 degrees they went into it)
    k_top = dict(hip=132.5, knee=6.0, ankle=45.0, tilt=20.0, extend=-43.0, com_dx=-24.0)
    f = keys(k_hang, k_arch, k_top, k_hang, spans=[0.2, 0.4, 0.4])

    def pose(u):
        return hang(**f(u))

    tl = Timeline([(0.45, 0, 0), (0.55, 0, 0.2), (1.05, 0.2, 0.6), (0.25, 0.6, 0.6), (1.4, 0.6, 1.0)] * 2)
    return pose, tl, bar_end


# ---- L-sit on parallettes -------------------------------------------------------------------------
# Side-on, the grips sit at hip height, so the near parallette is drawn where it is: in front of the
# body, gripped by the near hand (drawn behind the body it read as a stool under the seat).

PBAR_Y = 20.0               # parallette grip height
PBAR_Z = 24.0
PBAR_FOOT = 6.0             # 3D: half the length of a parallette's feet across it


def parallette(v, x, z3, top=PBAR_Y, half=16.0, z='back', gap=False):
    """One low bar on two splayed legs, running front to back."""
    cam = v.cam
    frame = []
    # 3D: the whole parallette in one piece, on the frame's item. Both cut a knockout band, as the
    # near one does side-on (the far one's 'back' needs none there): turned round, the far one is
    # the one in front of the body
    spec = []
    for e in (-1, 1):
        a = v3(x + e * (half - 5.0), top, z3)
        b = v3(x + e * (half + 1.0), 1.2, z3)
        frame.append(Cone(cam.p(a), cam.p(b), 1.6))
        frame.append(Cone(cam.p(b + v3(-e * 5.0, 0, 0)), cam.p(b + v3(e * 4.0, 0, 0)), 1.2))
        spec += (eq.rod3d(a, b, 1.6, 'frame', True)
                 + eq.rod3d(b + v3(-e * 5.0, 0, 0), b + v3(e * 4.0, 0, 0), 1.2, 'frame', True)
                 # and a foot across, so it stands (end-on side-on, inside the foot drawn)
                 + eq.rod3d(b - Z * PBAR_FOOT, b + Z * PBAR_FOOT, 1.2, 'frame', True))
    bar = Cone(cam.p(v3(x - half, top, z3)), cam.p(v3(x + half, top, z3)), 1.9)
    spec += eq.rod3d(v3(x - half, top, z3), v3(x + half, top, z3), 1.9, 'metal', True)
    return [Item(Union(frame), 'frame', z, gap, spec3d=spec), Item(bar, 'metal', z, gap, spec3d=[])]


@exercise('lSit', 'abdominals', 'side', muscles=['abs', 'hipflexors', 'quads'])
def l_sit():
    lp = math.sqrt((ARM - 0.4) ** 2 - (PBAR_Z - SHOULDER_HALF) ** 2)

    def body(px, py, phi, shrug, hip):
        p = {'pelvis': v3(px, py, 0.0), 'p_pitch': phi, 'pitch': 0.0, 'shrug': shrug, 'neck': -4.0}
        for s in 'LR':
            p['leg' + s] = {'hip': hip, 'abd': 1.0, 'knee': 0.0, 'ankle': 40.0}
        return p

    # the hold: arms locked, shoulders pressed down (lifting the trunk), legs level; the grips sit
    # beside the hips under the centre of mass, so the arms slant a little forward
    px, phi, shrug = 0.0, 10.0, -5.0
    S0 = v3(px, 0.0) + (TORSO + shrug) * v3(math.sin(math.radians(phi)), math.cos(math.radians(phi)))

    def top_at(gx):
        dx = S0[0] - gx
        py = PBAR_Y + math.sqrt(lp * lp - dx * dx) - S0[1]
        p = body(px, py, phi, shrug, 90.0 + phi)
        p.update(both(v3(gx, PBAR_Y, PBAR_Z), [-1.0, -0.2, 0.2]))
        return p

    gx = S0[0]
    for _ in range(4):
        gx = com(solve(top_at(gx)))[0]
    top = top_at(gx)
    # sitting between the bars: seat and legs on the floor, elbows bent
    seat = settle(body(px, 13.0, 4.0, 0.0, 90.0 + 4.0 + 3.2))
    seat.update(both(v3(gx, PBAR_Y, PBAR_Z), [-1.0, -0.2, 0.2]))

    def pose(u):
        return blend(seat, top, u)

    def equip(J, v, u):
        return parallette(v, gx, -PBAR_Z) + parallette(v, gx, PBAR_Z, z=('before', 'armR'), gap=True)

    return pose, Timeline([(0.5, 0, 0), (1.0, 0, 1), (2.2, 1, 1), (1.0, 1, 0)]), equip


# ---- side plank (front view) -----------------------------------------------------------------------
# The figure faces the camera, rolled onto its right forearm: head up to the screen's left. The
# lower foot and the elbow stay put; the hips lift, so the legs and trunk form a one-degree linkage:
# for each leg angle the trunk roll is solved to keep the shoulder an upper arm above the elbow.

@exercise('sidePlank', 'abdominals', 'front', muscles=['obliques', 'abs'])
def side_plank():
    Z_FOOT = -78.0

    def raw(rho, sig):
        p = {'pelvis': v3(0.0, 0.0, 0.0), 'p_roll': rho, 'roll': sig, 'neck': 4.0}
        # feet stacked: the legs close in just enough to rest the top ankle on the bottom one (their
        # centres a leg's width apart); closing them further passed one leg through the other
        for s in 'LR':
            p['leg' + s] = {'hip': 0.0, 'abd': -2.9, 'knee': 0.0, 'ankle': 10.0}
        return p

    @lru_cache(maxsize=4096)
    def placement(rho):
        # the lower foot's contact depends on the legs only: stand it on the floor at Z_FOOT
        J = solve(raw(rho, 0.0))
        foot = view(J, 'front').clip['legR'].shapes[-1]
        return v3(0.0, -SINK - low_y(foot), Z_FOOT - J.p['ankleR'][2])

    def body(rho, sig):
        p = raw(rho, sig)
        p['pelvis'] = placement(float(rho))
        return p

    def shoulder(rho, sig):
        return solve(body(rho, sig)).p['shoulderR']

    rho_top = bisect(lambda r: shoulder(r, 0.0)[1] - (ELBOW_FLOOR + UPPER), 50.0, 89.0)
    E = shoulder(rho_top, 0.0) - v3(0.0, UPPER, 0.0)

    def sig_for(rho):
        return bisect(lambda s: np.linalg.norm(shoulder(rho, s) - E) - UPPER, -60.0, 0.0, n=30)

    def hip_low(rho):
        p = body(rho, sig_for(rho))
        J = solve(p)
        v = view(J, 'front')
        thigh = J.p['hipR'][1] - 7.9
        return min(low_y(v.clip['torso']), thigh) + SINK

    rho_bot = bisect(hip_low, rho_top, 89.5)

    def pose(u):
        rho = lerp(rho_bot, rho_top, u)
        p = body(rho, sig_for(rho))
        J = solve(p)
        S = J.p['shoulderR']
        hand = v3(E[0] + FORE - 0.3, FIST_FLOOR, E[2])
        p['armR'] = {'hand': hand, 'pole': E - (S + hand) / 2}
        # the top hand rests on the hip, then reaches for the ceiling in the hold
        SL = J.p['shoulderL']
        rest = J.p['hipL'] + J.torso_frame.u * 8.0 - J.pelvis_frame.r * 6.0 + X * 9.0
        up = SL + v3(3.0, ARM - 2.0, 0.0)
        w = smooth(0.1, 1.0, u)
        p['armL'] = {'hand': rest + (up - rest) * w, 'pole': v3(1.0, -0.3, 0.6)}
        return p

    return pose, Timeline([(0.5, 0, 0), (1.1, 0, 1), (2.2, 1, 1), (1.1, 1, 0)]), None


# ---- seated and standing rotation (front view) ----------------------------------------------------

BALL_R = 11.0


@exercise('russianTwists', 'abdominals', 'front', muscles=['obliques', 'abs'])
def russian_twists():
    """Seated facing the camera, leaning back, feet flat; a medicine ball swings from one hip to the
    other as the trunk turns about the spine: from in front of the chest down to the floor beside
    the hip, outside the thigh (it used to sink into the thigh)."""
    TW = 42.0                                   # trunk turn at each side (deg)
    SIDE = v3(-4.0, 14.0, 36.0)                 # the ball beside the right hip, just off the floor

    def body(tw):
        p = {'pelvis': v3(0.0, 13.0, 0.0), 'p_pitch': -30.0, 'pitch': -8.0, 'yaw': tw, 'neck': -8.0}
        # knees open so the trunk shows between them from the front
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(60.0, ANKLE_H, sg * 17.0), 'toe_out': 14.0, 'pole': v3(0.2, 1.0, 0.75 * sg)}
        return settle(p)

    # the side position in the trunk's own frame at the full turn: the trunk carries the ball round
    J1 = solve(body(TW))
    W = SIDE - J1.p['pelvis']
    f1, u1, r1 = (float(W @ J1.torso_frame.f), float(W @ J1.torso_frame.u), float(W @ J1.torso_frame.r))

    def ball_at(tf, P, a, sg):
        # a: 0 in front of the chest (low enough to clear the chin), 1 beside the hip; on the way
        # it arcs over the thigh
        return (P + tf.f * lerp(38.0, f1, a) + tf.u * (lerp(19.0, u1, a) + 6.0 * math.sin(math.pi * a))
                + tf.r * (sg * r1 * a))

    def phase(u):
        th = 2 * math.pi * u
        return TW * math.sin(th), abs(math.sin(th)) ** 1.5      # turn (+ = to the figure's right), a

    def pose(u):
        tw, a = phase(u)
        p = body(tw)
        J = solve(p)
        tf = J.torso_frame
        B = ball_at(tf, J.p['pelvis'], a, 1.0 if tw >= 0 else -1.0)
        # palms on the ball: on its sides in front of the chest, over its top as it goes down
        side = unit(tf.r - Y * float(tf.r @ Y))
        up = math.radians(45.0 * a)
        for s, sg in (('L', -1), ('R', 1)):
            hand = B + (side * (sg * math.cos(up)) + Y * math.sin(up)) * (BALL_R + 2.5)
            p['arm' + s] = {'hand': hand, 'pole': tf.r * sg - tf.u * 0.8 + tf.f * 0.2}
        return p

    def equip(J, v, u):
        tw, a = phase(u)
        B = ball_at(J.torso_frame, J.p['pelvis'], a, 1.0 if tw >= 0 else -1.0)
        items = eq.medball(v, B, ('after', 'head'), r=BALL_R)
        for it in items:
            it.depth = v.cam.depth(B)     # beside the hip the ball is behind the raised knee and shin
        return items

    # a sine through both sides: the ball dwells at each hip, sweeps quickly through the middle
    return pose, cycles(2.8, 2), equip


TOWER_SET = 1.5         # 3D: the column's front face this far behind the pulley's middle


def cable_items(v, pulley3, handle3, hands=(), tower_z=None, ahead=0.0):
    """A cable tower seen from the front/back: the column beside the figure, the pulley, the cable.
    The cable runs from the pulley at the figure's side straight to the handle held out in front, so
    it passes in front of the body and the arms: it is drawn in front of them and ends where it
    reaches the first of the `hands` (3D grip points) holding the handle. ahead: 3D only, the tower
    stands this much further forward (along the front camera's line of sight, unseen in the 2D)."""
    cam = v.cam
    p3 = np.asarray(pulley3, float)
    h3 = np.asarray(handle3, float)
    tz = p3[2] + (8.0 if p3[2] > 0 else -8.0) if tower_z is None else tower_z
    top = max(p3[1] + 16.0, 205.0)
    col = RBox(cam.p(v3(p3[0], top / 2, tz)), 5.0, top / 2, 3.0)
    a, b = cam.p(p3), cam.p(h3)
    d = b - a
    t_end = 1.0
    for h in hands:
        # where the cable, seen from this camera, enters the fist's disc
        f = a - cam.p(h)
        r = R_HAND - 0.2
        A, B, C = float(d @ d), 2.0 * float(f @ d), float(f @ f) - r * r
        disc = B * B - 4 * A * C
        if A > 1e-9 and disc >= 0:
            t = (-B - math.sqrt(disc)) / (2 * A)
            if 0.0 <= t < t_end:
                t_end = t
    # 3D: a square column on a square base plate, set back so the pulley at its inner front edge
    # stands just in front of it (the 2D draws the wheel over the column); the wheel faces the
    # camera, turning in the plane the cable leaves it in, its axle on a bracket from the column
    # (behind the wheel). The cable runs on to the handle, inside the fists
    q3 = p3 + X * ahead
    cx = q3[0] - 5.0 - TOWER_SET
    back = q3 - X * (TOWER_SET + 1.1)
    tower3 = (eq.box3d(v3(cx, top / 2, tz), X, Y, Z, 5.0, top / 2, 5.0, 3.0, 'frame')
              + eq.box3d(v3(cx, 1.5, tz), X, Y, Z, 16.0, 1.5, 16.0, 1.4, 'frame')
              + eq.cyl3d(q3, X, 5.2, 1.2, 'metal') + eq.cyl3d(q3, X, 1.8, 1.5, 'frame')
              + eq.rod3d(back, v3(back[0], back[1], tz), 1.0, 'frame'))
    items = [Item(col, 'frame', 'back', spec3d=tower3),
             Item(RBox(cam.p(v3(p3[0], 1.5, tz)), 16.0, 1.5, 1.4), 'frame', 'back', spec3d=[]),
             Item(Circle(cam.p(p3), 5.2), 'metal', 'back', spec3d=[]), Item(Circle(cam.p(p3), 1.8), 'frame', 'back', spec3d=[]),
             Item(Cone(a, a + d * t_end, 0.6), 'metal', 'front', collider=('capsule', p3, h3, 0.4), grip=True,
                  spec3d=eq.rod3d(q3, h3, 0.6, 'metal'))]
    return items


@exercise('paloffPress', 'abdominals', 'front', muscles=['obliques', 'abs'])
def paloff_press():
    """Standing side-on to a chest-high cable (the tower at the figure's right), the handle pressed
    straight out from the sternum and back while the trunk stays square."""
    pulley = v3(34.0, 126.0, 96.0)

    def pose(u):
        hx = lerp(20.0, 58.0, u)
        p = standing(0.0, half=15.0, toe_out=10.0, bend=4.0, pitch=2.0,
                     hands=v3(hx, 126.0, 4.5), arm_pole=[-0.3, -1.0, 0.9])
        p['armL']['hand'] = v3(hx, 126.0, -4.5)
        # the cable's pull is resisted: the trunk stays square, a slight brace away from the tower
        p['roll'] = -1.5
        return p

    def equip(J, v, u):
        H = (J.p['handL'] + J.p['handR']) / 2
        # 3D: the handle runs across between the fists, the cable clipped to its middle
        return (cable_items(v, pulley, H, hands=(J.p['handL'], J.p['handR'])) +
                [Item(RBox(v.cam.p(H), 6.5, 2.2, 2.0), 'metal', ('after', 'head'),
                      spec3d=eq.rod3d(H - Z * 4.3, H + Z * 4.3, 2.2, 'metal'))])

    return pose, rep(1.1, 1.25, top=0.4, bottom=0.7), equip


@exercise('woodchops', 'abdominals', 'front', muscles=['obliques', 'abs'])
def woodchops():
    """Facing the camera, a high cable at the figure's right: both hands pull the handle from above
    the right shoulder diagonally down across the body to the left hip, the trunk turning and the
    back foot pivoting."""
    pulley = v3(10.0, 214.0, 92.0)
    H0 = v3(30.0, 166.0, 20.0)          # just outside and above the right shoulder
    H1 = v3(34.0, 92.0, -24.0)          # just outside the left hip

    def pose(u):
        H = H0 + (H1 - H0) * u
        yaw = lerp(36.0, -40.0, u)
        # (leaning further in at the bottom brought the right shoulder into the cable's line)
        p = standing(0.0, half=19.0, toe_out=12.0, bend=lerp(2.0, 7.0, u), pitch=lerp(0.0, 10.0, u),
                     hands=v3(0, 0, 0))
        p['p_yaw'] = 0.45 * yaw
        p['yaw'] = 0.55 * yaw
        p['roll'] = lerp(-6.0, 5.0, u)
        # the right (back) foot pivots onto its toes as the hips turn away from the tower
        heel = smooth(0.35, 1.0, u)
        fp = lerp(0.0, -24.0, heel)
        toe = v3(p['legR']['foot'][0], ANKLE_H) + toe_offset(0.0)        # toe of the flat foot
        A = toe - toe_offset(fp)
        p['legR'] = {'foot': v3(A[0], A[1], 19.0), 'foot_pitch': fp,
                     'toe_out': lerp(12.0, -8.0, heel), 'pole': v3(1.0, 0.0, 0.1)}
        p['legL']['toe_out'] = 12.0 - p['p_yaw']
        # both hands on the one handle, side by side along the shoulder line: each forearm comes in
        # from its own side (stacked front to back, the left forearm ran through the right fist)
        J = solve(p)
        d = unit(pulley - H)
        side = J.p['shoulderR'] - J.p['shoulderL']
        side = unit(side - d * float(side @ d))
        p['armR'] = {'hand': H + side * 4.0, 'pole': v3(-0.2, -1.0, 0.7)}
        p['armL'] = {'hand': H - side * 4.0, 'pole': v3(-0.2, -1.0, -0.7)}
        return p

    def equip(J, v, u):
        H = (J.p['handL'] + J.p['handR']) / 2
        # 3D: the tower 10 cm further forward than the pulley's x: from x = 10 the cable ran 2 cm
        # inside the right shoulder at the bottom of the chop, hidden there (the 2D draws it over it)
        return cable_items(v, pulley, H, hands=(J.p['handL'], J.p['handR']), ahead=10.0)

    return pose, rep(0.95, 1.45, top=0.35, bottom=0.3), equip


# ---- windshield wipers ---------------------------------------------------------------------------
# Lying on the back, legs straight up, swept down to either side. Seen from the head end ('back'):
# the legs sweep across the picture like a wiper. From the feet ('front') the renderer draws the
# head over the legs and trunk, the wrong way round for a body lying away from the camera.

def settle_views(pose, cams, floor=0.0):
    """Like `settle`, but the lowest point of the body over several views: a pelvis rolled onto
    its side (seen end-on) must rest on the floor as well as the trunk seen side-on."""
    p = settle(pose, floor)
    J = solve(p)
    dy = max(0.0, max(floor - SINK - low_y(view(J, c).clip['hips']) for c in cams))
    p['pelvis'] = np.asarray(p['pelvis'], float) + v3(0.0, dy, 0.0)
    return p


@exercise('windshieldWipers', 'abdominals', 'back', muscles=['obliques', 'abs', 'hipflexors'])
def windshield_wipers():
    reach = UPPER + FORE_WRIST - 0.6

    def pose(u):
        k, e = side_phase(u)
        sweep = (60.0 if k == 0 else -60.0) * e          # pelvis turned about the spine
        p = {'pelvis': v3(0.0, 13.0, 0.0), 'p_pitch': -86.0, 'p_yaw': sweep, 'pitch': 0.0,
             'yaw': -0.85 * sweep, 'neck': 0.0}
        for s in 'LR':
            p['leg' + s] = {'hip': 90.0, 'abd': -3.0, 'knee': 0.0, 'ankle': 30.0}
        p = rest_head(settle_views(p, ('back',)))
        # arms out to the sides, palms pressed flat on the floor
        J = solve(p)
        wy = 1.2 + 3.9 - SINK               # a flat hand seen end-on is a disc just below the wrist
        for s, sg in (('L', -1), ('R', 1)):
            S = J.p['shoulder' + s]
            out = math.sqrt(max(reach ** 2 - (S[1] - wy) ** 2, 1.0))
            p['arm' + s] = {'hand': v3(S[0] + 2.0, wy, S[2] + sg * out), 'pole': v3(0.0, 1.0, 0.0),
                            'palm': True, 'palm_dir': v3(0.3, 0.0, sg)}
        return p

    return pose, alternate(0.3, 1.2, 0.3, 1.2), None


# ---- kneeling cable crunch ---------------------------------------------------------------------------

@exercise('cableCrunches', 'abdominals', 'side', muscles=['abs'])
def cable_crunches():
    """Kneeling facing a high pulley, rope ends at the sides of the head; the hips stay put while
    the trunk crunches down, elbows towards the thighs. The cable ends at the rope's middle, above
    the head, and the two strands run past the head to the fists by the ears (the cable used to run
    straight into the head, to the point between the hands)."""
    H = v3(-3.0, KNEE_FLOOR + THIGH * math.cos(math.radians(5.0)))
    pulley = v3(112.0, 206.0, 0.0)
    KNOT = 26.0         # the rope's middle, this far from between the fists towards the pulley

    def pose(u):
        p = {'pelvis': v3(H[0], H[1], 0.0), 'pitch': lerp(14.0, 76.0, u), 'neck': lerp(-4.0, -24.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = kneel_leg(H, sg * 10.0, fwd=1.0)     # the hips stay put, so the knees do
        J = solve(p)
        tf = J.torso_frame
        for s, sg in (('L', -1), ('R', 1)):
            # the fists by the ears, wide enough that the strands rising from them pass the head
            hand = J.p['head'] + tf.r * (sg * 14.5)
            p['arm' + s] = {'hand': hand, 'pole': tf.f * 1.0 - tf.u * 0.9 + tf.r * (sg * 0.3)}
        return p

    def rope_end(v, hand3, knot3, z):
        """One strand from the rope's middle into the fist, its knotted end out of the bottom."""
        cam = v.cam
        knob = hand3 + unit(hand3 - knot3) * 6.5
        shape = Union([Cone(cam.p(knot3), cam.p(hand3), 1.5), Cone(cam.p(hand3), cam.p(knob), 1.5),
                       Circle(cam.p(knob), 2.7)])
        # 3D: the strand runs straight on through the fist to its end. The knotted end's ball is
        # left out: crunched, the strand's line runs on down the forearm, and the ball sank into
        # it (a grey spot on the forearm from every side; the 2D draws it behind the forearm)
        return [Item(shape, 'metal', z, True, collider=('capsule', knot3, hand3, 1.0), grip=True,
                     spec3d=eq.rod3d(knot3, knob, 1.5, 'metal', True))]

    def equip(J, v, u):
        mid = (J.p['handL'] + J.p['handR']) / 2
        knot = mid + unit(pulley - mid) * KNOT
        items = eq.cable_stack(v, pulley, knot, z='back', tower_x=pulley[0] + 9.0)
        # the near strand passes in front of the head, the far one behind it
        for s in 'LR':
            items += rope_end(v, J.p['hand' + s], knot, ('before', 'arm' + s))
        return items

    return pose, rep(1.2, 1.5, top=0.35, bottom=0.45), equip


# ---- medicine ball slam ---------------------------------------------------------------------------

@exercise('medicineBallSlams', 'abdominals', 'side', muscles=['abs', 'lats'])
def medicine_ball_slams():
    """Ball overhead -> slammed down in front of the feet (released at hip height, it drops to the
    floor) -> squat to pick it up -> stand -> up past the face to overhead again."""
    R = BALL_R + 1.0
    # thrown down from the hands, the ball lands a little ahead of the release (not back towards
    # the feet), so the squat reaches it in front of the knees: arms dropped between the knees
    # passed through them
    land = v3(50.0, R - SINK)

    def key(px, py, pitch, hx, hy, pole, neck=0.0):
        p = {'pelvis': v3(px, py, 0.0), 'pitch': pitch, 'neck': neck}
        p.update(feet(0.0, 13.0, 8.0))
        p.update(both(v3(hx, hy, 14.0), list(pole)))        # palms on the ball's sides
        return p

    k_over = key(0.5, HIP_H - 0.8, -3.0, 5.0, SH_Y + 58.0, (0.4, 0.2, 1.0), neck=6.0)
    # the straight arms swing down in an arc in front (not through the shoulders)
    k_arc = key(-3.0, HIP_H - 3.0, 14.0, 63.0, SH_Y + 2.0, (0.0, -0.3, 1.0), neck=0.0)
    k_rel = key(-7.0, HIP_H - 9.0, 38.0, 42.0, 70.0, (-0.6, -0.2, 1.0), neck=-6.0)
    k_follow = key(-11.0, HIP_H - 16.0, 50.0, 38.0, 50.0, (-0.6, -0.4, 1.0), neck=-10.0)
    k_pick = key(-14.0, 52.0, 67.0, land[0], land[1], (-0.3, -0.6, 1.0), neck=-6.0)
    k_chest = key(0.5, HIP_H - 1.0, 2.0, 24.0, SH_Y - 22.0, (-0.2, -1.0, 0.8))
    # from the chest the ball goes up in front of the face, then overhead (not through the face)
    k_face = key(0.5, HIP_H - 0.9, 0.0, 38.0, SH_Y + 26.0, (-0.2, -0.6, 1.0), neck=3.0)
    f = keys(k_over, k_arc, k_rel, k_follow, k_pick, k_chest, k_face, k_over,
             spans=[0.1, 0.1, 0.2, 0.2, 0.2, 0.1, 0.1])
    FLY = 0.07                                   # of the phase: release -> floor

    def pose(u):
        return f(u - math.floor(u))

    def equip(J, v, u):
        w = u - math.floor(u)
        held = (J.p['handL'] + J.p['handR']) / 2
        if 0.2 < w < 0.6:
            rel = f(0.2)
            r0 = (rel['armL']['hand'] + rel['armR']['hand']) / 2
            s = min((w - 0.2) / FLY, 1.0) ** 2          # falling, speeding up
            c = r0 + (v3(land[0], land[1], 0.0) - r0) * s
        else:
            c = held
        return eq.medball(v, v3(c[0], c[1], 0.0), ('before', 'armR'), r=R)

    one = [(0.3, 0.0, 0.0), (0.45, 0.0, 0.2), (0.3, 0.2, 0.4), (0.5, 0.4, 0.6), (0.15, 0.6, 0.6),
           (0.7, 0.6, 0.8), (0.5, 0.8, 1.0)]
    tl = Timeline(one + [(d, a + 1, b + 1) for d, a, b in one])
    return pose, tl, equip


# ---- suitcase carry -------------------------------------------------------------------------------

def keep_foot_up(leg):
    """Raise an IK foot whose heel or toe would dip below the floor (the shared gait's toe-off
    pitches the toes about a centimetre into it)."""
    if 'foot' not in leg:
        return leg
    fp = math.radians(leg.get('foot_pitch', 0.0))
    ty, ny = math.sin(fp), math.cos(fp)
    A = np.asarray(leg['foot'], float)
    heel = A[1] + ny * HEEL[0] + ty * HEEL[1] - R_HEEL
    toe = A[1] + ny * TOE[0] + ty * TOE[1] - R_TOE
    low = min(heel, toe)
    if low >= -SINK:
        return leg
    leg = dict(leg)
    leg['foot'] = A + v3(0.0, -SINK - low, 0.0)
    return leg


@exercise('suitcaseCarry', 'abdominals', 'side', muscles=['obliques', 'abs'])
def suitcase_carry():
    """Walking tall with a kettlebell in the near hand; that arm hangs still, the trunk does not lean
    towards the weight, the free arm swings."""
    # a slightly shorter stride and lower hips than the default walk keep the knee off full lock at
    # heel strike (where the IK knee would snap)
    g = Gait(stride=52.0, lift=8.0, bob=1.3, lean=1.0, arm_swing=18.0, elbow=14.0, drop=2.5)

    def pose(u):
        p = g.pose(u)
        for s in 'LR':
            p['leg' + s] = keep_foot_up(p['leg' + s])
        p['armR'] = {'flex': 1.5 * math.sin(2 * math.pi * u), 'abd': 9.0, 'elbow': 3.0}
        p['shrug'] = -1.0
        return p

    def equip(J, v, u):
        sway = math.radians(3.0 * math.sin(2 * math.pi * u - 0.6))
        down = v3(math.sin(sway), -math.cos(sway), 0.0)
        return eq.kettlebell(v, J.p['handR'], down, ('before', 'armR'))

    return pose, cycles(1.1, 3), equip


# ---- Turkish get-up -------------------------------------------------------------------------------
# Side view, kettlebell in the near (right) hand. Key poses from lying to standing; every frame the
# bell arm is locked vertically over its shoulder. The right foot stays planted from the floor to
# the stand; the left hand stays planted from the sit-up to the kneel.

TGU_RF = v3(40.0, ANKLE_H, 13.0)            # right foot, planted
TGU_LH = v3(-18.0, WRIST_FLOOR, -42.0)      # left palm, planted from 'hand' to 'kneel'
TGU_KX = TGU_RF[0] - THIGH                  # left knee x when half-kneeling (right shin vertical)
TGU_K = v3(TGU_KX, KNEE_FLOOR)              # left knee on the floor, planted from the sweep to the stand


def tgu_keys():
    LA = v3(84.0, 8.7, -26.0)               # left heel resting on the floor, leg long
    r_leg = {'foot': TGU_RF, 'toe_out': 6.0, 'pole': v3(0.25, 1.0, 0.2), 'foot_pitch': 0.0}
    l_long = {'foot': LA, 'foot_pitch': 72.0, 'toe_out': 0.0, 'pole': v3(0.0, 1.0, -0.3)}

    def base(px, py, p_pitch, pitch, twist, neck, legL, legR=None, armL=None):
        p = {'pelvis': v3(px, py, 0.0), 'p_pitch': p_pitch, 'pitch': pitch, 'yaw': twist, 'roll': 0.0,
             'neck': neck, 'legL': dict(legL), 'legR': dict(legR or r_leg)}
        p['armL'] = dict(armL) if armL else {'hand': TGU_LH, 'pole': v3(-0.6, 0.2, -1.0), 'palm': True,
                                             'palm_dir': X}
        return p

    # lying: left arm out on the floor at 45 degrees
    k_lie = base(0.0, 13.0, -90.0, 0.0, 0.0, 0.0, l_long,
                 armL={'hand': v3(-14.0, WRIST_FLOOR, -54.0), 'pole': v3(0.0, 1.0, -0.8), 'palm': True,
                       'palm_dir': unit(v3(1.0, 0.0, -1.0))})
    k_lie = rest_head(settle(k_lie))
    # up onto the left elbow: trunk raised and turned, the forearm flat on the floor
    k_elbow = base(0.0, 13.0, -90.0, 30.0, -24.0, -8.0, l_long,
                   armL={'hand': v3(-14.0, WRIST_FLOOR, -46.0), 'pole': v3(-0.4, -1.0, -0.3), 'palm': True,
                         'palm_dir': unit(v3(1.0, 0.0, -0.6))})
    k_elbow = settle(k_elbow)
    # up onto the left hand: sitting tall
    k_hand = settle(base(0.0, 13.0, -90.0, 62.0, -16.0, -4.0, l_long))

    reach = UPPER + FORE_WRIST - 1.0

    def lean(p, roll, pelvis_too=False):
        """Lean the trunk back (world pitch) until the straight left arm reaches the planted hand."""
        def d(a):
            q = dict(p)
            q['roll'] = roll
            if pelvis_too:
                q['p_pitch'], q['pitch'] = a, 0.0
            else:
                q['pitch'] = a - q['p_pitch']
            return np.linalg.norm(solve(q).p['shoulderL'] - TGU_LH) - reach
        a = bisect(d, -88.0, 10.0) if d(-88.0) < 0 else -88.0
        q = dict(p)
        q['roll'] = roll
        if pelvis_too:
            q['p_pitch'], q['pitch'] = a, 0.0
        else:
            q['pitch'] = a - q['p_pitch']
        return q

    r_bent = {'foot': TGU_RF, 'toe_out': 6.0, 'pole': v3(1.0, 0.4, 0.2), 'foot_pitch': 0.0}
    # high bridge: hips up in a line from the shoulders to the left heel
    k_bridge = lean(base(6.0, 41.0, -80.0, 0.0, -8.0, 0.0, dict(l_long, pole=v3(1.0, 0.4, -0.2)),
                         legR=r_bent), 0.0, pelvis_too=True)
    # the left leg sweeps back under the hips along the floor, knee leading, the hand still planted
    k_tuck = lean(base(3.0, 46.0, 0.0, 0.0, -6.0, 0.0,
                       {'foot': v3(18.0, 10.5, -18.0), 'foot_pitch': 25.0, 'pole': v3(1.0, 0.2, 0.0)},
                       legR=r_bent), -25.0)

    def on_knee(H):
        """Hips a thigh's length from the planted knee (so the knee stays exactly on its spot)."""
        return TGU_K + unit(v3(H[0], H[1]) - TGU_K) * THIGH

    # ... and sets the knee down on its spot, shin still raised behind: from here to the stand the
    # knee stays planted (it used to land in front of the hips and slide 14 cm back along the floor)
    hb = on_knee(v3(0.5, 49.5))
    shin = TGU_K + dir2(157.8) * SHANK
    k_back = lean(base(hb[0], hb[1], 0.0, 0.0, -5.0, 0.0,
                       {'foot': v3(shin[0], shin[1], -14.0), 'foot_pitch': -60.0,
                        'pole': TGU_K - (hb + shin) / 2},
                       legR=r_bent), -40.0)
    # kneeling on the left knee, leaning sideways over the left hand
    kp = on_knee(v3(TGU_KX + 2.0, KNEE_FLOOR + THIGH))
    k_kneel = lean(base(kp[0], kp[1], 0.0, 0.0, -4.0, 4.0, kneel_leg_at(kp, TGU_K, -12.0), legR=r_bent), -48.0)
    # half-kneeling, trunk upright, the free hand off the floor
    hk = on_knee(v3(TGU_KX, KNEE_FLOOR + THIGH))
    k_half = base(hk[0], hk[1], 0.0, 0.0, 0.0, 4.0, kneel_leg_at(hk, TGU_K, -12.0),
                  legR={'foot': TGU_RF, 'toe_out': 6.0, 'pole': v3(1.0, 0.1, 0.2), 'foot_pitch': 0.0},
                  armL={'hand': v3(hk[0] + 6.0, hk[1] + 4.0, -27.0), 'pole': v3(-1.0, 0.0, -0.3), 'palm': True,
                        'palm_dir': -Y})
    # standing (the right foot stays on its spot; the left one steps up beside it)
    k_stand = base(TGU_RF[0] + 0.5, HIP_H - 0.6, 0.0, 0.0, 0.0, 4.0,
                   {'foot': v3(TGU_RF[0], ANKLE_H, -TGU_RF[2]), 'foot_pitch': 0.0, 'toe_out': 6.0,
                    'pole': v3(1.0, 0.0, -0.25)},
                   legR={'foot': TGU_RF, 'toe_out': 6.0, 'pole': v3(1.0, 0.0, 0.25), 'foot_pitch': 0.0},
                   armL={'hand': v3(TGU_RF[0] + 3.0, HIP_H - 7.0, -26.0), 'pole': v3(-1.0, 0.0, -0.3),
                         'palm': True, 'palm_dir': -Y})
    return [k_lie, k_elbow, k_hand, k_bridge, k_tuck, k_back, k_kneel, k_half, k_stand]


def bell_arm(p):
    """Lock the bell arm vertically over its shoulder."""
    S = solve(p).p['shoulderR']
    p = dict(p)
    p['armR'] = {'hand': S + v3(1.0, ARM - 1.2, 1.5), 'pole': v3(-1.0, 0.0, 0.3)}
    return p


@exercise('turkishGetUp', 'abdominals', 'side', muscles=['abs', 'obliques', 'delts'])
def turkish_get_up():
    ks = tgu_keys()
    n = len(ks) - 1
    f = keys(*ks)

    def pose(u):
        # u is the key index (fractional): up from 0 to n, then back down the same way
        p = f(u / n)
        if n - 1 < u < n:
            # standing up: the back foot steps through in an arc, it does not slide
            w = u - (n - 1)
            p['legL'] = dict(p['legL'], foot=p['legL']['foot'] + v3(0.0, 11.0 * math.sin(math.pi * w), 0.0))
        p['legL'] = keep_foot_up(p['legL'])
        return bell_arm(p)

    # lie -> elbow -> hand -> bridge -> (one sweep through tuck and back) -> kneel -> half -> stand
    up = [(0.9, 0, 1), (0.8, 1, 2), (0.8, 2, 3), (1.5, 3, 6), (0.9, 6, 7), (1.1, 7, 8)]
    down = [(d, b, a) for d, a, b in reversed(up)]
    tl = Timeline([(0.5, 0, 0)] + up + [(0.6, n, n)] + down)

    def equip(J, v, u):
        # the bell rests on the back of the forearm, behind the wrist (hanging along the forearm it
        # sat inside it)
        down = unit(J.p['elbowR'] - J.p['handR'])
        back = unit(v3(down[1], -down[0], 0.0))
        if back[0] > 0:
            back = -back
        d = unit(down * math.cos(math.radians(72.0)) + back * math.sin(math.radians(72.0)))
        return eq.kettlebell(v, J.p['handR'], d, ('before', 'armR'))

    return pose, tl, equip

