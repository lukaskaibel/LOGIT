"""Olympic lifts and their relatives: cleans, snatches, jerks, push press, high pulls, and the
kettlebell clean and snatch. Side view; the barbell is seen end-on (a plate disc).

A lift is a handful of solved key poses on a `Track`: every value runs through the keys on a
monotone cubic, so the explosive phases flow through their keys and the figure only comes to
rest where a value holds or turns (the setup, the catch, the lockout). Each key pose is solved
from a few constraints (the bar over mid-foot, straight arms while pulling, the bar on the front
delts in the rack, locked arms overhead), so the in-betweens stay close to them. On the way up
the legs the bar brushes them, in front (see `pull`): extra keys along the shins and thighs keep
the in-betweens there too. Hands are keyed
relative to the shoulders (reach, direction, elbow swivel), so straight arms stay straight along
any arc and a racked or overhead bar rides with the body between keys.
"""
from .common import *
from ..rig import rot_toward, solve
from ..spec import TOE

A = -6.0                        # ankle x with the feet flat
MID = A + 6.0                   # the bar's line over mid-foot
HALF = 11.0                     # stance half-width (hip width)
TOE_OUT = 8.0
CLEAN_Z = SHOULDER_HALF + 4.5   # clean / jerk grip: hands just outside the shoulders
SNATCH_Z = 42.0                 # wide snatch grip
PLATE_R = 22.5                  # bar height with the plates on the floor
WR = FORE - FORE_WRIST          # wrist -> grip centre
REACH = UPPER + FORE_WRIST      # shoulder -> wrist, arm straight


# ---- timing: key poses on a monotone cubic ------------------------------------------------

DERIVED = {'grip', 'hand', 'pole', 'wrist_flex'}     # arm values `settle` rebuilds every frame


def _paths(d, pre=()):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from _paths(v, pre + (k,))
        elif not (pre and pre[-1].startswith('arm') and k in DERIVED):
            yield pre + (k,)


def _get(d, path):
    for k in path:
        d = d[k]
    return d


def _put(d, path, v):
    for k in path[:-1]:
        d = d.setdefault(k, {})
    d[path[-1]] = v


def _slopes(ts, ys):
    """Monotone cubic (Fritsch-Carlson) slopes; the ends wrap around (a loop)."""
    h = np.diff(ts)
    d = np.diff(ys, axis=0) / h.reshape((-1,) + (1,) * (ys.ndim - 1))

    def one(d0, d1, h0, h1):
        w1, w2 = 2 * h1 + h0, h1 + 2 * h0
        with np.errstate(divide='ignore', invalid='ignore'):
            s = (w1 + w2) / (w1 / d0 + w2 / d1)
        return np.where(d0 * d1 > 0, s, 0.0)

    m = np.zeros(ys.shape)
    for i in range(1, len(ts) - 1):
        m[i] = one(d[i - 1], d[i], h[i - 1], h[i])
    m[0] = m[-1] = one(d[-1], d[0], h[-1], h[0])
    return m


class Track:
    """Pose dicts keyed at times (s). Each value is interpolated on its own monotone cubic, so it
    never overshoots its keys: it flows through a key while it keeps its direction and rests
    where it turns or holds (repeat a pose to hold it). The last key closes the loop: it is the
    first pose again. Use as `pose_fn = track.pose`, `phase = track.phase`.
    `post` finishes every interpolated pose (see `settle`)."""

    def __init__(self, keyed, post=None):
        self.post = settle if post is None else post
        keyed = list(keyed)
        if keyed[-1][1] is not keyed[0][1]:
            raise ValueError('the last key must repeat the first pose (seamless loop)')
        self.ts = np.array([t for t, _ in keyed], float)
        if np.any(np.diff(self.ts) <= 0):
            raise ValueError('key times must increase')
        self.total = float(self.ts[-1])
        poses = [p for _, p in keyed]
        self.chan = []
        for path in _paths(poses[0]):
            ys = np.array([np.asarray(_get(p, path), float) for p in poses])
            self.chan.append((path, ys, _slopes(self.ts, ys)))
        self.phase = Cycle(self.total, 1)

    def at(self, t):
        t = t % self.total
        i = int(np.clip(np.searchsorted(self.ts, t, side='right') - 1, 0, len(self.ts) - 2))
        h = self.ts[i + 1] - self.ts[i]
        s = (t - self.ts[i]) / h
        s2, s3 = s * s, s * s * s
        c0, c1, c2, c3 = 2 * s3 - 3 * s2 + 1, (s3 - 2 * s2 + s) * h, 3 * s2 - 2 * s3, (s3 - s2) * h
        out = {}
        for path, ys, m in self.chan:
            _put(out, path, c0 * ys[i] + c1 * m[i] + c2 * ys[i + 1] + c3 * m[i + 1])
        return self.post(out)

    def pose(self, u):
        return self.at(u * self.total)


def settle(p):
    """Finish an interpolated pose. Each foot follows its (ax, lift, hop) values, so the ball of
    the foot stays planted while the heel rises. Each hand follows its grip, keyed as a reach
    and a direction from the shoulder, and the rig's wrist target, pole and wrist flex are
    solved from it (see finish_arm)."""
    for s, sg in (('L', -1.0), ('R', 1.0)):
        lg = p['leg' + s]
        x, y, fp = toe_stand(lg['ax'], lg['lift'])
        lg['foot'] = v3(x, y + lg['hop'], lg['foot'][2])
        lg['foot_pitch'] = fp + lg['tip']
        finish_arm(p['arm' + s], shoulder_of(p, sg), sg)
    return p


# ---- feet and legs -------------------------------------------------------------------------

def toe_stand(ax, lift):
    """Ankle (x, y) and foot pitch with the heel raised `lift` degrees about the ball of the foot
    (the toe stays where it is with the foot flat and the ankle at ax)."""
    th = math.radians(lift)
    c = math.cos(math.radians(TOE_OUT))
    n, t = TOE
    return (ax + c * (t * (1 - math.cos(th)) - n * math.sin(th)),
            ANKLE_H + n + (-n) * math.cos(th) + t * math.sin(th), -lift)


def leg(ax, s, lift=0.0, half=HALF, pole=None, hop=0.0, tip=0.0):
    """Leg IK dict plus the values `settle` rebuilds the foot from: ax (ankle x with the foot
    flat), lift (heel raise about the ball of the foot, deg), hop (foot off the floor, cm) and
    tip (extra foot pitch while in the air)."""
    x, y, fp = toe_stand(ax, lift)
    return {'foot': v3(x, y + hop, s * half), 'toe_out': TOE_OUT, 'foot_pitch': fp + tip,
            'pole': v3(1.0, 0.0, 0.25 * s) if pole is None else np.asarray(pole, float),
            'ax': float(ax), 'lift': float(lift), 'hop': float(hop), 'tip': float(tip)}


def both_legs(ax=A, lift=0.0, half=HALF):
    return {'legL': leg(ax, -1.0, lift, half), 'legR': leg(ax, 1.0, lift, half)}


def chain(shin, thigh, ax=A, lift=0.0):
    """Knee and hip (sagittal) from the shin's forward lean and the thigh's angle above
    horizontal (90 = standing)."""
    x, y, _ = toe_stand(ax, lift)
    ph, al = math.radians(shin), math.radians(thigh)
    K = v3(x, y) + SHANK * v3(math.sin(ph), math.cos(ph))
    return K, K + THIGH * v3(-math.cos(al), math.sin(al))


def hip_between(K, S, t_len):
    """Hip joint THIGH from the knee and t_len from the shoulder line (sagittal), the one behind."""
    dv = S - K
    d0 = float(np.linalg.norm(dv))
    ex = dv / d0
    d = min(d0, THIGH + t_len - 1e-6)
    a = (THIGH ** 2 - t_len ** 2 + d * d) / (2 * d)
    h = math.sqrt(max(THIGH ** 2 - a * a, 0.0))
    base = K + ex * a
    ey = v3(-ex[1], ex[0])
    return min(base + ey * h, base - ey * h, key=lambda q: q[0])


# ---- arms ------------------------------------------------------------------------------------

def shoulder_of(p, s=1.0):
    th = math.radians(p['pitch'])
    f, u = v3(math.cos(th), -math.sin(th)), v3(math.sin(th), math.cos(th))
    return (np.asarray(p['pelvis'], float) + u * (TORSO + p.get('shrug', 0.0)) + f * p.get('protract', 0.0)
            + Z * (s * SHOULDER_HALF))


def solve_arm(S, G, aim, wf):
    """Wrist target and rig pole that put the grip centre exactly on G: the elbow sits on the
    `aim` side of the shoulder->grip line and the wrist bends by wf (- = extended) in the arm's
    plane. rig.solve reproduces this elbow (the pole's part across the shoulder->wrist line points
    at it) and bends the hand to the inside of the elbow, as built here."""
    a = math.radians(wf)
    Lf = math.sqrt(FORE_WRIST ** 2 + WR ** 2 + 2 * FORE_WRIST * WR * math.cos(a))   # elbow -> grip
    E, Gc = ik2(S, G, UPPER, Lf, aim)
    d_u = unit(E - S)
    e_g = unit(Gc - E)
    ins = e_g - np.dot(e_g, d_u) * d_u              # inside of the elbow bend
    if np.linalg.norm(ins) < 0.05:                  # nearly straight: away from the aim
        q = aim - np.dot(aim, d_u) * d_u
        if np.linalg.norm(q) > 1e-6:
            ins = -q
    ins = unit(ins)
    beta = math.degrees(math.asin(min(1.0, WR * abs(math.sin(a)) / Lf)))
    d_f = rot_toward(e_g, -ins if wf > 0 else ins, beta) if beta > 1e-6 else e_g
    W = E + d_f * FORE_WRIST
    bend = math.degrees(math.acos(float(np.clip(np.dot(d_u, d_f), -1.0, 1.0))))
    return W, (E - S) - unit(W - S) * (0.5 * UPPER), bend


def swivel_axes(S, G, sgn):
    """Directions across the shoulder->grip line: e1 = out to the side, e2 = the arm's natural
    bend (below an arm reaching forward, behind a hanging arm, in front of an overhead arm).
    Mirrored for the left arm (sgn -1)."""
    d = unit(np.asarray(G, float) - S)
    out = Z * sgn
    e1 = unit(out - np.dot(out, d) * d)
    return e1, np.cross(d, e1) * sgn


def finish_arm(am, S, sgn):
    """Fill in the grip and the rig's 'hand' (wrist target), 'pole' and 'wrist_flex' from the
    arm's keyed values. The grip is held relative to the shoulder as a reach and a direction, so
    a straight arm (reach beyond ARM) stays straight along any arc between keys and a racked or
    overhead bar moves with the shoulders. The elbow sits `swivel` degrees around the
    shoulder->grip line from straight out (see swivel_axes): keyed as an angle it sweeps smoothly
    and can never flip. A grip at or beyond reach gives a straight arm pointing at it (the wrist
    target overshoots, the IK clamps).
    rig.solve bends the hand towards the inside of the elbow measured against the upper arm,
    which lines up with the forearm at a 90 deg elbow: the hand would flip sides there, so the
    flex fades to 0 within 12 deg of a right-angled elbow."""
    reach = float(am['reach'])
    G = S + unit(np.asarray(am['dir'], float)) * reach
    am['grip'] = G
    e1, e2 = swivel_axes(S, G, sgn)
    w = math.radians(float(am['swivel']))
    aim = e1 * math.cos(w) + e2 * math.sin(w)
    wf = float(am['flex'])
    if reach >= ARM - 0.02:
        am['hand'], am['pole'], am['wrist_flex'] = S + unit(G - S) * (REACH + 2.0), aim, wf
        return am
    W, pole, bend = solve_arm(S, G, aim, wf)
    k = smooth(0.0, 12.0, abs(bend - 90.0))
    if k < 1.0 and wf != 0.0:
        wf *= k
        W, pole, bend = solve_arm(S, G, aim, wf)
    am['hand'], am['pole'], am['wrist_flex'] = W, pole, wf
    return am


def arm(S, G, aim, wf=0.0, straight=False, sgn=1.0):
    """Arm dict with the keyed values `settle` works from: the grip's reach and direction from
    the shoulder, the elbow's swivel (from the aim direction: the elbow goes to the aim's side of
    the shoulder->grip line) and the wrist flex; plus the grip and the rig's IK values derived
    from them. straight: the arm locked towards G (its reach just beyond ARM)."""
    G = np.asarray(G, float)
    aim = np.asarray(aim, float)
    rel = G - S
    reach = ARM + 1.0 if straight else float(np.linalg.norm(rel))
    e1, e2 = swivel_axes(S, G, sgn)
    sw = math.degrees(math.atan2(float(aim @ e2), float(aim @ e1)))
    return finish_arm({'reach': reach, 'dir': unit(rel), 'swivel': sw, 'flex': float(wf)}, S, sgn)


def set_arms(p, G, pole, wf=None):
    """Both hands on the bar: G is the right hand's grip (mirrored for the left).
    wf None = arms locked straight towards the bar, else bent with that wrist flex."""
    for s, sg in (('L', -1.0), ('R', 1.0)):
        g = np.array(G, float)
        g[2] *= sg
        pl = np.array(pole, float)
        pl[2] *= sg
        p['arm' + s] = arm(shoulder_of(p, sg), g, pl, 0.0 if wf is None else wf, wf is None, sg)
    return p


def arm_len(gz):
    """In-plane (side view) length of a straight arm whose hand is gz from the midline."""
    return math.sqrt(ARM ** 2 - (gz - SHOULDER_HALF) ** 2)


# ---- key-pose solvers --------------------------------------------------------------------------

HANG_POLE = (0.1, -0.2, 1.0)        # elbows turned out, arms long
KNEES = 0.08                        # knee pole outwards with a clean grip: knees over the toes,
                                    # inside the arms (0.25, the legs' default, pushes them out)
BALL = A + 10.0                     # over the balls of the feet, where the bar leaves the floor
# A bar pulled up the legs brushes them: its centre stays this far from the shank's axis, and from
# the knee and the thigh's axis (the body's capsules in clip.py plus the bar's radius, less the
# 1.7 cm a loaded bar presses in; the checker allows 2).
GRAZE_SHIN = 5.0
GRAZE_THIGH = 6.8


def seg_dist(p, a, b):
    ab = b - a
    t = min(max(float(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12)), 0.0), 1.0)
    return float(np.linalg.norm(p - (a + ab * t)))


def pull(by, lead, shin, gz=CLEAN_Z, bx=MID, lift=0.0, shrug=0.0, neck=None, pole=HANG_POLE, knees=0.25):
    """Arms hanging straight to the bar at (bx, by), the shoulders `lead` degrees in front of it,
    the shins `shin` degrees forward, but no further than the bar allows: it passes in front of
    the shins, knees and thighs, brushing them; the hips close the chain. knees: the knee pole's
    outward part (KNEES with a clean grip)."""
    B = v3(bx, by)
    L = arm_len(gz)
    b = math.radians(lead)
    S = B + L * v3(math.sin(b), math.cos(b))
    x, y, _ = toe_stand(A, lift)
    ank = v3(x, y)

    def chain(ph):
        K = ank + SHANK * v3(math.sin(ph), math.cos(ph))
        return K, hip_between(K, S, TORSO + shrug)

    def clear(ph):
        K, H = chain(ph)
        return min(seg_dist(B, ank, K) - GRAZE_SHIN, seg_dist(B, K, H) - GRAZE_THIGH)

    ph = math.radians(shin)
    if clear(ph) < 0.0:
        # lean the shins forward from upright only until the legs reach the bar
        lo, step = math.radians(-10.0), math.radians(1.0)
        while lo + step < ph and clear(lo + step) >= 0.0:
            lo += step
        hi = min(lo + step, ph)
        for _ in range(24):
            mid = (lo + hi) / 2
            if clear(mid) >= 0.0:
                lo = mid
            else:
                hi = mid
        ph = lo
    K, H = chain(ph)
    d = S - H
    pitch = math.degrees(math.atan2(d[0], d[1]))
    p = {'pelvis': H, 'pitch': pitch, 'neck': 0.35 * pitch if neck is None else neck,
         'shrug': shrug, 'protract': 0.0}
    p.update(both_legs(A, lift))
    for s, sg in (('L', -1.0), ('R', 1.0)):
        p['leg' + s]['pole'] = v3(1.0, 0.0, knees * sg)
    return set_arms(p, v3(bx, by, gz), pole)


def hang_arms(p, gz=CLEAN_Z, bar_fwd=12.0, pole=HANG_POLE):
    """Arms hanging straight, swung forward until the bar is bar_fwd in front of the hip joint
    (against the thighs)."""
    H = p['pelvis']
    S = shoulder_of(p, 0.0)
    L = arm_len(gz)
    b = math.asin(max(-1.0, min(1.0, (H[0] + bar_fwd - S[0]) / L)))
    B = S + L * v3(math.sin(b), -math.cos(b))
    return set_arms(p, v3(B[0], B[1], gz), pole)


def graze_arms(p, gz=CLEAN_Z, pole=HANG_POLE):
    """Arms hanging straight, swung back from in front until the bar meets the legs as the body
    stands (the solved knees and hips, seen side-on): the bar brushes the thighs or shins."""
    p = settle(p)
    J = solve(p)
    ank, K, H = (v3(*J.p[k][:2]) for k in ('ankleR', 'kneeR', 'hipR'))
    S = shoulder_of(p, 0.0)
    L = arm_len(gz)

    def bar(a):
        return S + L * v3(math.sin(a), -math.cos(a))

    def clear(a):
        B = bar(a)
        return min(seg_dist(B, ank, K) - GRAZE_SHIN, seg_dist(B, K, H) - GRAZE_THIGH)

    lo, hi = math.radians(-20.0), math.radians(50.0)    # lo: swung back; hi: forward, clear
    a = hi
    while a > lo and clear(a - math.radians(1.0)) >= 0.0:
        a -= math.radians(1.0)
    b = a - math.radians(1.0)
    for _ in range(24):
        mid = (a + b) / 2
        if clear(mid) >= 0.0:
            a = mid
        else:
            b = mid
    B = bar(a)
    return set_arms(p, v3(B[0], B[1], gz), pole)


def between(p0, p1, t, gz=CLEAN_Z):
    """A key between two pull keys: the body blended, the bar brushing the legs."""
    return graze_arms(blend(p0, p1, t), gz)


def stance(shin=3.0, thigh=86.0, lean=2.0, shrug=0.0, protract=0.0, neck=0.0, lift=0.0):
    """Body on a squat chain with the torso at `lean`; arms still to be set."""
    K, H = chain(shin, thigh, A, lift)
    p = {'pelvis': H, 'pitch': lean, 'neck': neck, 'shrug': shrug, 'protract': protract}
    p.update(both_legs(A, lift))
    return p


def hang(shin=3.0, thigh=86.0, lean=2.0, bar_fwd=12.0, gz=CLEAN_Z, shrug=0.0, neck=0.0):
    """Standing with soft knees, the bar hanging at the hips."""
    return hang_arms(stance(shin, thigh, lean, shrug, neck=neck), gz, bar_fwd)


def tall(lift, lean=0.0, lean_legs=1.0, shrug=0.0, neck=2.0):
    """Legs straight on the balls of the feet (heels raised `lift` deg), leaning `lean_legs`
    forward, torso at `lean`; arms still to be set."""
    x, y, _ = toe_stand(A, lift)
    Lg = math.sqrt((THIGH + SHANK - 0.4) ** 2 - (HALF - HIP_HALF) ** 2)
    g = math.radians(lean_legs)
    H = v3(x, y) + Lg * v3(math.sin(g), math.cos(g))
    p = {'pelvis': H, 'pitch': lean, 'neck': neck, 'shrug': shrug, 'protract': 0.0}
    p.update(both_legs(A, lift))
    return p


def extended(lift, lean=-8.0, lean_legs=1.5, shrug=4.0, gz=CLEAN_Z, bar_fwd=12.0, pole=HANG_POLE):
    """Triple extension: on the toes, legs straight, torso leaning back, shoulders shrugged,
    arms still long with the bar brushing the hips."""
    return hang_arms(tall(lift, lean, lean_legs, shrug, 4.0), gz, bar_fwd, pole)


def tvec(pitch, f, u, z=0.0):
    """A direction given in the torso frame (forward, up, out to the right)."""
    th = math.radians(pitch)
    return v3(math.cos(th), -math.sin(th)) * f + v3(math.sin(th), math.cos(th)) * u + Z * z


RACK = (9.0, 57.0)                  # the bar on the front delts, torso-local (forward, up)
RACK_ELBOW = 22.0                   # elbow aim this far below horizontal: elbows up front
RACK_WF = -85.0                     # wrists extended under the bar
RACK_PROTRACT, RACK_SHRUG = 2.5, 1.5


def rack_arms(p, local=RACK, elbow=RACK_ELBOW, wf=RACK_WF):
    b = math.radians(elbow)
    B = torso_point(p['pelvis'], p['pitch'], *local)
    return set_arms(p, v3(B[0], B[1], CLEAN_Z), v3(math.cos(b), -math.sin(b), 0.45), wf)


def unrack_arms(p, local=(19.0, 35.0), wf=-15.0):
    """The bar leaving the shoulders: elbows dropped under it, the bar in front of the chest."""
    B = torso_point(p['pelvis'], p['pitch'], *local)
    return set_arms(p, v3(B[0], B[1], CLEAN_Z), tvec(p['pitch'], 0.15, -1.0, 0.35), wf)


def rack(shin, thigh, bar_dx=0.0, lift=0.0, neck=4.0, ax=A):
    """Front rack over mid-foot on a squat chain (shin lean, thigh angle)."""
    K, H = chain(shin, thigh, ax, lift)
    pitch = solve_torso_for(RACK, H, MID + bar_dx)
    p = {'pelvis': H, 'pitch': pitch, 'neck': neck, 'shrug': RACK_SHRUG, 'protract': RACK_PROTRACT}
    p.update(both_legs(ax, lift))
    return rack_arms(p)


HIGH_WF = 25.0                      # knuckles down while the elbows lead


def high_arms(p, local=(15.0, 31.0), gz=CLEAN_Z, back=0.45, up=0.9, wf=HIGH_WF):
    """Bar pulled up the body to a torso-local point, elbows high and out (above the wrists)."""
    B = torso_point(p['pelvis'], p['pitch'], *local)
    return set_arms(p, v3(B[0], B[1], gz), tvec(p['pitch'], -back, up, 1.0), wf)


def under(shin, thigh, pitch, local=(15.0, 31.0), gz=CLEAN_Z, shrug=3.0, lift=0.0, neck=2.0, up=0.9):
    """Pulling under the bar: feet back down, knees bending, the bar high on the body."""
    K, H = chain(shin, thigh, A, lift)
    p = {'pelvis': H, 'pitch': pitch, 'neck': neck, 'shrug': shrug, 'protract': 0.0}
    p.update(both_legs(A, lift))
    return high_arms(p, local, gz, up=up)


OVER_POLE = (-0.35, 0.0, 1.0)       # locked arms: elbows out and back


def overhead(shin, thigh, gz=CLEAN_Z, tilt=0.0, bar_dx=0.0, shrug=2.5, lift=0.0, neck=0.0, ax=A):
    """Bar locked out overhead over mid-foot on a squat chain. tilt: the arms' lean from
    vertical (+ = bar in front of the shoulders)."""
    K, H = chain(shin, thigh, ax, lift)
    L = arm_len(gz)
    t = math.radians(tilt)
    sx = MID + bar_dx - L * math.sin(t)
    pitch = solve_torso_for((0.0, TORSO + shrug), H, sx)
    p = {'pelvis': H, 'pitch': pitch, 'neck': neck, 'shrug': shrug, 'protract': 0.0}
    p.update(both_legs(ax, lift))
    return overhead_arms(p, gz, tilt)


def overhead_arms(p, gz=CLEAN_Z, tilt=0.0):
    """Arms locked overhead from the body as it is (tilt: + = bar in front of the shoulders)."""
    S = shoulder_of(p, 0.0)
    t = math.radians(tilt)
    B = S + arm_len(gz) * v3(math.sin(t), math.cos(t))
    return set_arms(p, v3(B[0], B[1], gz), OVER_POLE)


def face_arms(p, gz=CLEAN_Z, local=(20.0, 76.0), aim=(-0.5, 0.2, 1.0), wf=-20.0):
    """The bar passing in front of the face, arms bent (a snatch turnover, a press, a lowering).
    aim: elbow direction in the torso frame (forward, up, out)."""
    B = torso_point(p['pelvis'], p['pitch'], *local)
    return set_arms(p, v3(B[0], B[1], gz), tvec(p['pitch'], *aim), wf)


PRESS_RACK = (11.0, 54.0)           # the bar on the shoulders for pressing and jerking


def press_rack_arms(p, local=PRESS_RACK):
    """Full grip on the shoulders: elbows a little lower and in front of the bar."""
    return rack_arms(p, local, elbow=40.0, wf=-60.0)


def press_rack(shin, thigh, bar_dx=1.0, lift=0.0, neck=2.0):
    K, H = chain(shin, thigh, A, lift)
    pitch = solve_torso_for(PRESS_RACK, H, MID + bar_dx)
    p = {'pelvis': H, 'pitch': pitch, 'neck': neck, 'shrug': 1.0, 'protract': 1.5}
    p.update(both_legs(A, lift))
    return press_rack_arms(p)


PRESS_FACE = dict(local=(21.0, 73.0), aim=(0.25, -1.0, 0.7), wf=-35.0)   # elbows under the bar


# ---- equipment -------------------------------------------------------------------------------

def bar_equip(J, v, u):
    B = (J.p['handL'] + J.p['handR']) / 2
    return eq.barbell(v, v3(B[0], B[1], 0.0))


def rack_bar_equip(J, v, u):
    """A bar that starts in the front rack and never touches the floor: smaller plates, so the
    camera-side plate doesn't hide the head while the bar sits at the collarbones."""
    B = (J.p['handL'] + J.p['handR']) / 2
    return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)


# ---- cleans ------------------------------------------------------------------------------------

BACK_MUSCLES = ['traps', 'erectors', 'glutes', 'hamstrings']


def clean_keys():
    """Key poses of a barbell clean (clean grip). Up the shins and thighs the bar brushes the legs:
    'low' and 'shin' keep them behind it on the way to the knees, 'drive' as the hips come through."""
    k = dict(
        setup=pull(PLATE_R, 6.0, 22.0, bx=BALL, knees=KNEES),   # hips just above the knees, back flat
        low=pull(29.5, 6.5, 19.0, bx=BALL - (BALL - MID) / 3, knees=KNEES),
        shin=pull(37.0, 7.0, 13.0, bx=(BALL + MID) / 2, knees=KNEES),   # the shins pull back behind the bar
        knee=pull(52.0, 8.0, 4.0, knees=KNEES),          # first pull: same back angle, knees back
        power=pull(74.0, 1.0, 12.0, knees=KNEES),        # knees under the bar again, torso upright
        ext=extended(25.0, lean=-8.0, lean_legs=0.5, bar_fwd=10.0),   # on the toes, shrugged
        under=under(14.0, 62.0, 2.0, up=0.5),            # elbows high and out, dropping
        catch=rack(22.0, 45.0, bar_dx=1.0),              # front rack in a quarter squat
        absorb=rack(24.0, 40.0, bar_dx=1.0),
        stand=rack(1.0, 89.0, bar_dx=2.0),
        unrack=unrack_arms(stance(4.0, 84.0, 2.0)),      # elbows drop, bar leaves the shoulders
        hang=hang(6.0, 82.0, 4.0),                       # bar back at the hips, knees soft
    )
    k['drive'] = between(k['power'], k['ext'], 0.5)     # hips through, the bar up the thighs
    return k


@exercise('powerClean', 'back', 'side', muscles=BACK_MUSCLES)
def power_clean():
    k = clean_keys()
    tr = Track([(0.0, k['setup']), (0.45, k['setup']), (0.6, k['low']), (0.75, k['shin']), (1.0, k['knee']),
                (1.2, k['power']), (1.29, k['drive']), (1.38, k['ext']), (1.53, k['under']), (1.7, k['catch']),
                (1.92, k['absorb']), (2.12, k['absorb']), (3.0, k['stand']), (3.5, k['stand']), (3.85, k['unrack']),
                (4.2, k['hang']), (4.45, k['hang']), (5.05, k['knee']), (5.33, k['shin']), (5.47, k['low']),
                (5.6, k['setup']), (5.9, k['setup'])])
    return tr.pose, tr.phase, bar_equip


@exercise('hangClean', 'back', 'side', muscles=BACK_MUSCLES)
def hang_clean():
    k = clean_keys()
    hinge = pull(58.0, 11.0, 9.0, knees=KNEES)           # hang position: bar just above the knees
    tr = Track([(0.0, k['hang']), (0.35, k['hang']), (1.05, hinge), (1.2, hinge), (1.36, k['power']),
                (1.44, k['drive']), (1.52, k['ext']), (1.67, k['under']), (1.84, k['catch']), (2.05, k['absorb']),
                (2.22, k['absorb']), (3.05, k['stand']), (3.55, k['stand']), (3.9, k['unrack']),
                (4.25, k['hang']), (4.5, k['hang'])])
    return tr.pose, tr.phase, bar_equip


@exercise('cleanAndPress', 'shoulders', 'side', muscles=['delts', 'triceps', 'traps'])
def clean_and_press():
    k = clean_keys()
    pr = press_rack(1.0, 89.0)                           # re-grip for the press, elbows lower
    dip = press_rack(8.0, 80.0)                          # a slight dip
    mid = face_arms(stance(2.0, 88.0, -2.0, shrug=1.5, neck=8.0), **PRESS_FACE)
    lock = overhead(1.0, 89.0, CLEAN_Z, tilt=2.0)
    down = face_arms(stance(3.0, 87.0, -1.0, shrug=1.5, neck=8.0), **PRESS_FACE)
    soft = press_rack(6.0, 83.0)                         # bar back on the shoulders, knees soft
    tr = Track([(0.0, k['setup']), (0.45, k['setup']), (0.6, k['low']), (0.75, k['shin']), (1.0, k['knee']),
                (1.2, k['power']), (1.29, k['drive']), (1.38, k['ext']), (1.53, k['under']), (1.7, k['catch']),
                (1.92, k['absorb']), (2.12, k['absorb']), (3.0, k['stand']), (3.3, k['stand']), (3.55, pr), (3.8, dip),
                (4.1, mid), (4.5, lock), (5.0, lock), (5.5, down), (5.85, soft), (6.05, soft),
                (6.4, k['unrack']), (6.75, k['hang']), (7.0, k['hang']), (7.6, k['knee']),
                (7.88, k['shin']), (8.02, k['low']), (8.15, k['setup']), (8.45, k['setup'])])
    return tr.pose, tr.phase, bar_equip


# ---- snatches ----------------------------------------------------------------------------------

def snatch_keys():
    """Key poses of a barbell snatch (wide grip)."""
    gz = SNATCH_Z
    k = dict(
        setup=pull(PLATE_R, 7.0, 24.0, gz=gz, bx=BALL),  # wide grip: hips lower, chest up
        low=pull(29.5, 6.5, 20.0, gz=gz, bx=BALL - (BALL - MID) / 3),
        shin=pull(37.0, 6.0, 15.0, gz=gz, bx=(BALL + MID) / 2),
        knee=pull(52.0, 5.0, 6.0, gz=gz),                # first pull: the back angle holds
        power=pull(78.0, 1.0, 12.0, gz=gz),
        ext=extended(25.0, lean=-8.0, lean_legs=0.5, bar_fwd=11.0, gz=gz),
        under=under(12.0, 66.0, 1.0, local=(15.0, 36.0), gz=gz, up=0.35),
        turn=face_arms(stance(24.0, 40.0, 8.0, shrug=3.0), gz, local=(15.0, 85.0), aim=(-0.2, 0.15, 1.0),
                       wf=-10.0),                        # forearms up past the forehead
        catch=overhead(38.0, 8.0, gz, tilt=-2.0),        # overhead squat, head through the arms
        ride=overhead(40.0, 3.0, gz, tilt=-2.0),
        power_catch=overhead(24.0, 42.0, gz, tilt=-1.0),
        power_ride=overhead(26.0, 37.0, gz, tilt=-1.0),
        stand=overhead(1.0, 89.0, gz, tilt=3.0),
        down_face=face_arms(stance(3.0, 86.0, 0.0, shrug=1.0), gz, aim=(-0.6, 0.1, 1.0)),
        down_chest=high_arms(stance(5.0, 83.0, 2.0, shrug=2.0), (15.0, 36.0), gz),
        hang=hang(6.0, 82.0, 4.0, gz=gz),
    )
    k['drive'] = between(k['power'], k['ext'], 0.5, gz)
    return k


SNATCH_MUSCLES = ['delts', 'traps', 'quads']


@exercise('snatch', 'shoulders', 'side', muscles=SNATCH_MUSCLES)
def snatch():
    k = snatch_keys()
    tr = Track([(0.0, k['setup']), (0.45, k['setup']), (0.6, k['low']), (0.75, k['shin']), (1.0, k['knee']),
                (1.2, k['power']), (1.29, k['drive']), (1.38, k['ext']), (1.51, k['under']), (1.63, k['turn']),
                (1.78, k['catch']),
                (2.0, k['ride']), (2.3, k['ride']), (3.3, k['stand']), (3.9, k['stand']),
                (4.35, k['down_face']), (4.65, k['down_chest']), (4.95, k['hang']), (5.15, k['hang']),
                (5.75, k['knee']), (6.03, k['shin']), (6.17, k['low']), (6.3, k['setup']), (6.6, k['setup'])])
    return tr.pose, tr.phase, bar_equip


@exercise('hangSnatch', 'shoulders', 'side', muscles=SNATCH_MUSCLES)
def hang_snatch():
    k = snatch_keys()
    hinge = pull(58.0, 11.0, 9.0, gz=SNATCH_Z)
    tr = Track([(0.0, k['hang']), (0.35, k['hang']), (1.05, hinge), (1.2, hinge), (1.36, k['power']),
                (1.44, k['drive']), (1.52, k['ext']), (1.65, k['under']), (1.77, k['turn']), (1.92, k['power_catch']),
                (2.12, k['power_ride']), (2.35, k['power_ride']), (3.1, k['stand']), (3.65, k['stand']),
                (4.1, k['down_face']), (4.4, k['down_chest']), (4.7, k['hang']), (4.9, k['hang'])])
    return tr.pose, tr.phase, bar_equip


# ---- push press and jerks ----------------------------------------------------------------------

JERK_MUSCLES = ['delts', 'triceps', 'quads']


def drive_pose(lift=16.0):
    """Legs driven straight onto the balls of the feet; the bar leaving the shoulders, passing
    the chin with the elbows under it."""
    return face_arms(tall(lift, lean=-1.0, lean_legs=1.0, shrug=1.5, neck=8.0), local=(18.0, 66.0),
                     aim=(0.3, -1.0, 0.7), wf=-45.0)


def jerk_keys():
    return dict(
        rack=press_rack(1.0, 89.0),
        dip=press_rack(20.0, 58.0, bar_dx=1.5),          # knees forward, torso upright
        drive=drive_pose(),
        lock=overhead(1.0, 89.0, CLEAN_Z, tilt=2.0),
        down=face_arms(stance(3.0, 87.0, -1.0, shrug=1.5, neck=8.0), **PRESS_FACE),
        soft=press_rack(8.0, 80.0),                      # bar back on the shoulders, knees soft
    )


def repeat(one, period, start):
    """Two reps of the keyed list `one` (times within a rep ending at `period` with the start pose)."""
    return [(0.0, start)] + one + [(t + period, p) for t, p in one]


@exercise('pushPress', 'shoulders', 'side', muscles=JERK_MUSCLES)
def push_press():
    k = jerk_keys()
    tr = Track(repeat([(0.35, k['rack']), (0.75, k['dip']), (0.95, k['drive']), (1.25, k['lock']),
                       (1.7, k['lock']), (2.15, k['down']), (2.45, k['soft']), (2.75, k['rack'])], 2.75, k['rack']))
    return tr.pose, tr.phase, rack_bar_equip


@exercise('pushJerk', 'shoulders', 'side', muscles=JERK_MUSCLES)
def push_jerk():
    k = jerk_keys()
    catch = overhead(26.0, 58.0, CLEAN_Z, tilt=1.0)      # re-dipped under the locked bar, torso upright
    absorb = overhead(28.0, 53.0, CLEAN_Z, tilt=1.0)
    tr = Track([(0.0, k['rack']), (0.4, k['rack']), (0.8, k['dip']), (1.0, k['drive']), (1.18, catch),
                (1.4, absorb), (1.6, absorb), (2.25, k['lock']), (2.75, k['lock']), (3.2, k['down']),
                (3.5, k['soft']), (3.85, k['rack'])])
    return tr.pose, tr.phase, rack_bar_equip


def split_stance(front, back, hip_x, hip_y, lean=1.0, back_lift=45.0, hop_f=0.0, hop_b=0.0, tip_f=0.0,
                 tip_b=0.0, shrug=2.5, neck=2.0):
    """Feet split: the near (right) foot `front` cm ahead of the start, the far (left) foot `back`
    cm behind it on the ball of the foot; the pelvis placed at (hip_x, hip_y)."""
    p = {'pelvis': v3(hip_x, hip_y), 'pitch': lean, 'neck': neck, 'shrug': shrug, 'protract': 0.0}
    p['legR'] = leg(A + front, 1.0, 0.0, HALF, hop=hop_f, tip=tip_f)
    p['legL'] = leg(A - back, -1.0, back_lift, HALF, pole=v3(0.8, -1.0, -0.15), hop=hop_b, tip=tip_b)
    return p


@exercise('splitJerk', 'shoulders', 'side', muscles=JERK_MUSCLES)
def split_jerk():
    k = jerk_keys()
    ov = lambda p, tilt=0.0: overhead_arms(p, CLEAN_Z, tilt)
    fly = ov(split_stance(14.0, 32.0, A - 2.0, 88.5, back_lift=30.0, hop_f=4.0, hop_b=5.0, tip_f=6.0,
                          tip_b=-6.0), 1.0)
    land = ov(split_stance(28.0, 67.0, A - 5.0, 82.0, back_lift=50.0))   # front shin vertical, back leg long
    sink = ov(split_stance(28.0, 67.0, A - 5.0, 80.0, back_lift=50.0))
    step1a = ov(split_stance(14.0, 67.0, A - 11.0, 84.0, back_lift=50.0, hop_f=4.0, tip_f=6.0))
    step1 = ov(split_stance(0.0, 67.0, A - 17.0, 85.0, back_lift=48.0))
    step2a = ov(split_stance(0.0, 33.0, A - 8.0, 90.0, back_lift=25.0, hop_b=5.0, tip_b=-8.0))
    tr = Track([(0.0, k['rack']), (0.4, k['rack']), (0.8, k['dip']), (1.0, k['drive']), (1.14, fly),
                (1.28, land), (1.46, sink), (1.72, sink), (1.97, step1a), (2.17, step1), (2.42, step2a),
                (2.67, k['lock']), (3.12, k['lock']), (3.57, k['down']), (3.87, k['soft']), (4.22, k['rack'])])
    return tr.pose, tr.phase, rack_bar_equip


# ---- high pulls --------------------------------------------------------------------------------

@exercise('highPulls', 'shoulders', 'side', muscles=['delts', 'traps'])
def high_pulls():
    start = pull(68.0, 5.0, 11.0)                        # bar at mid-thigh, hips hinged
    ext = extended(16.0, lean=-5.0, lean_legs=1.0, shrug=3.0, bar_fwd=11.0)
    top = high_arms(tall(10.0, lean=-4.0, lean_legs=0.5, shrug=4.0), (16.0, 40.0), back=0.3, up=0.6)
    tr = Track(repeat([(0.35, start), (0.55, ext), (0.77, top), (0.97, top), (1.95, start)], 1.95, start))
    return tr.pose, tr.phase, bar_equip


# ---- kettlebell clean and snatch (one bell, right hand) -----------------------------------------

BELL_RACK = (0.985, -0.174)         # resting on the forearm in the rack: in front of the fist
BELL_LOCK = (-0.985, -0.174)        # locked out overhead: on the back of the forearm, behind the fist
BELL_OUT = 0.3                      # resting, the bell lies against the outside of the forearm: its
                                    # sideways lean from the arm's plane (tan)
KB_HALF = 20.0                      # kettlebell stance: feet wide, knees out over the toes


def wide(p):
    """The kettlebell stance: the feet wider and the knees out over the toes, so the bell and the
    forearm swing between the thighs; the hips drop as far as the wider stance needs."""
    for s, sg in (('L', -1.0), ('R', 1.0)):
        lg = p['leg' + s]
        p['leg' + s] = leg(lg['ax'], sg, lg['lift'], KB_HALF, v3(1.0, 0.0, 0.6 * sg), lg['hop'], lg['tip'])
    reach = THIGH + SHANK - 0.4
    P = np.asarray(p['pelvis'], float)
    d = p['legR']['foot'] - (P + Z * HIP_HALF)
    if np.linalg.norm(d) > reach:
        p['pelvis'] = v3(P[0], p['legR']['foot'][1] + math.sqrt(reach ** 2 - d[0] ** 2 - d[2] ** 2), P[2])
    return p


def kb(p, G, aim, wf=0.0, straight=False, rest=0.0, free=4.0, on=BELL_RACK):
    """Right hand on the kettlebell's handle at G (straight: the arm locked towards G); the left
    arm hangs free, `free` degrees in front of vertical. rest: 0 = the bell swings on along the
    arm, 1 = it rests on the forearm in direction `on` (side view, relative to the forearm
    pointing up)."""
    p['armR'] = arm(shoulder_of(p, 1.0), G, aim, wf, straight)
    SL = shoulder_of(p, -1.0)
    b = math.radians(free)
    p['armL'] = arm(SL, SL + v3(ARM * math.sin(b), -ARM * math.cos(b), -1.5), v3(0.1, -0.2, -1.0), 0.0, True, -1.0)
    p['bell'] = {'rest': float(rest), 'on': math.atan2(on[1], on[0])}
    return p


def swing_grip(p, deg, z=3.0):
    """Grip of the straight right arm swung `deg` in front of straight down (- = back)."""
    S = shoulder_of(p, 1.0)
    L = math.sqrt(ARM ** 2 - (z - SHOULDER_HALF) ** 2)
    b = math.radians(deg)
    return v3(S[0] + L * math.sin(b), S[1] - L * math.cos(b), z)


SWING_AIM = v3(-0.2, 0.3, 1.0)


def kb_hinge():
    """Backswing: hips back, the bell between the thighs behind the knees."""
    p = wide(stance(12.0, 58.0, 58.0, neck=24.0))
    return kb(p, swing_grip(p, -33.0, 2.0), SWING_AIM, straight=True, free=0.0)


def kb_spec3d(hand3, down3, gap=True):
    """3D: eq.kettlebell's form (the bell below the grip and the handle as a hoop round it), the
    hoop kept across the fist: in the plane of the bell's direction and the grip axis (z). The
    shared helper picks its hoop's plane from x, and turns it a quarter round whenever the bell
    points nearly along x (overhead in the snatch)."""
    hand3 = np.asarray(hand3, float)
    d = unit(down3)
    side = unit(Z - d * float(np.dot(Z, d)))
    ring = [hand3 + d * 4.0 + (d * math.cos(a) + side * math.sin(a)) * 4.9 for a in np.linspace(0.0, 2 * math.pi, 9)]
    return eq.ball3d(hand3 + d * 13.0, 10.5, 'metal', gap) + eq.rope3d(ring, 1.3, 'metal')


def kb_equip(track):
    """The bell hangs on along the arm while it swings (in the arm's plane, so on the backswing
    it passes between the thighs) and turns onto the forearm as `rest` goes to 1, where it lies
    against the outside of the forearm. Both parts are placed by depth: the bell by its own, so
    it swings behind the near leg and rests in front of the head overhead; the handle just behind
    the hand, so the fist closes around it."""
    def equip(J, v, u):
        bell = track.pose(u)['bell']
        rest = float(bell['rest'])
        hand, S, E = J.p['handR'], J.p['shoulderR'], J.p['elbowR']
        along = hand - S
        fore = hand - E
        # the resting direction turns with the forearm (keyed for a forearm pointing straight up)
        a_on = float(bell['on']) + math.atan2(fore[1], fore[0]) - math.pi / 2
        a0 = math.atan2(along[1], along[0])
        da = (a_on - a0 + math.pi) % (2 * math.pi) - math.pi
        a = a0 + da * rest
        dz = lerp(along[2] / max(math.hypot(along[0], along[1]), 1e-6), BELL_OUT, rest)
        d = v3(math.cos(a), math.sin(a), dz)
        items = eq.kettlebell(v, hand, d, ('before', 'legR'))
        body_depth = v.cam.depth(hand + unit(d) * 13.0)
        grip_depth = v.cam.depth(hand) - 0.5
        sh = items[0].shape
        if isinstance(sh, Union) and len(sh.shapes) == 2:     # [bell, handle]: split them
            first = items[0]
            # 3D: the whole kettlebell (bell and handle hoop) rides on the bell's item
            items[0] = Item(sh.shapes[0], first.color, gap=first.gap, depth=body_depth, collider=first.collider,
                            spec3d=kb_spec3d(hand, d, first.gap))
            items.insert(1, Item(sh.shapes[1], first.color, gap=first.gap, depth=grip_depth, spec3d=[]))
            for it in items[2:]:
                it.depth = grip_depth
        else:
            for it in items:
                it.depth = body_depth
        return items
    return equip


@exercise('kettlebellClean', 'back', 'side', muscles=BACK_MUSCLES)
def kettlebell_clean():
    back = kb_hinge()
    p = wide(stance(4.0, 84.0, 8.0))
    drive = kb(p, swing_grip(p, 14.0, 5.0), SWING_AIM, straight=True)
    p = wide(stance(1.0, 88.0, 2.0, shrug=1.5))          # elbow stays by the ribs, the hand rides up
    pull = kb(p, v3(*torso_point(p['pelvis'], p['pitch'], 22.0, 40.0)[:2], 9.0), tvec(2.0, 0.1, -1.0, 0.3),
              rest=0.2)
    p = wide(stance(1.0, 89.0, -1.0, neck=2.0))          # rack: fist under the chin, elbow tucked
    rack = kb(p, v3(*torso_point(p['pelvis'], p['pitch'], 13.0, 45.0)[:2], 9.0), tvec(-1.0, 0.2, -1.0, 0.15),
              rest=1.0)
    p = wide(stance(4.0, 82.0, 14.0))
    drop = kb(p, swing_grip(p, 22.0, 6.0), SWING_AIM, straight=True, rest=0.0)
    tr = Track(repeat([(0.32, drive), (0.47, pull), (0.62, rack), (1.12, rack), (1.42, drop), (1.85, back)],
                      1.85, back))
    return tr.pose, tr.phase, kb_equip(tr)


@exercise('kettlebellSnatch', 'shoulders', 'side', muscles=['delts', 'traps', 'glutes', 'hamstrings'])
def kettlebell_snatch():
    back = kb_hinge()
    p = wide(stance(4.0, 84.0, 6.0))
    drive = kb(p, swing_grip(p, 22.0, 6.0), SWING_AIM, straight=True)
    p = wide(tall(8.0, lean=-2.0, shrug=3.0))            # bell floats up close, elbow high and out
    pull = kb(p, v3(*torso_point(p['pelvis'], p['pitch'], 17.0, 45.0)[:2], 22.0), tvec(-2.0, -0.2, 0.25, 1.0),
              wf=10.0, rest=0.1)
    p = wide(stance(1.0, 89.0, 0.0, shrug=2.5))          # punching through: forearm up past the face
    punch = kb(p, v3(*torso_point(p['pelvis'], p['pitch'], 14.0, 82.0)[:2], 17.0), tvec(0.0, 0.1, -0.25, 1.0),
               rest=0.6, on=BELL_LOCK)
    p = wide(stance(1.0, 89.0, 0.0, shrug=2.5))
    lock = kb(p, swing_grip(p, 178.0, 19.0), v3(-0.3, 0.0, 1.0), straight=True, rest=1.0, on=BELL_LOCK)
    p = wide(stance(1.0, 88.0, 2.0, shrug=1.0))
    over = kb(p, swing_grip(p, 125.0, 12.0), SWING_AIM, straight=True, rest=0.25, on=BELL_LOCK)
    p = wide(stance(2.0, 86.0, 4.0))
    front = kb(p, swing_grip(p, 75.0, 8.0), SWING_AIM, straight=True, rest=0.0)
    p = wide(stance(5.0, 80.0, 18.0))
    low = kb(p, swing_grip(p, 20.0, 5.0), SWING_AIM, straight=True, rest=0.0)
    tr = Track(repeat([(0.3, drive), (0.47, pull), (0.6, punch), (0.72, lock), (1.2, lock), (1.45, over),
                       (1.68, front), (1.9, low), (2.2, back)], 2.2, back))
    return tr.pose, tr.phase, kb_equip(tr)
