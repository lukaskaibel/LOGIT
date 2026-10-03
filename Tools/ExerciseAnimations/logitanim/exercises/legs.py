"""Leg machines and single-leg work: leg presses, lunges, split squats, step-ups, extensions,
curls, calf raises, hip ab-/adduction, cable kickbacks, sled pushes and tire flips.

Machines are drawn here from sdf primitives and the shared equipment helpers, in the bench's
language: rounded 'pad' cushions on thin 'frame' posts, 'metal' for levers and handles. Machine
levers pivot at the knee: a two-leg machine carries its lever on the far side, so it is drawn
behind the legs, while the one-leg standing curl swings its lever between the knees. Rollers sit
on the shin or calf, across the legs they push. Grips sit at the hands' own depth (the near one in
front of the body), turned across the fist, and every part the body can meet carries a collider.

Conventions used here:
- Feet that rise onto their toes pivot about the ball of the foot (`ball_pivot`), so the ball stays
  planted: calf raises, the lunge's back foot, push-offs before a step.
- One-per-leg exercises run two reps, right then left, on a `Warp` phase: multi-part movements
  (lunges, step-ups) give each part its own tempo without stopping between them.
- Travelling movements stay in place: the sled push steps on a moving ground (like `Gait`); the
  tire flip is choreographed in world space and a follow-camera advances only while the lifter
  steps, one flip's length per loop, so the loop closes seamlessly.
"""
from .common import *
from ..sdf import Circle, Cone, RBox, Union, Offset
from ..spec import TOE, R_SHANK, R_THIGH, GAP
from ..rig import solve

SOLE = ANKLE_H              # ankle -> sole along the foot normal (flat foot)


# ---- motion helpers -------------------------------------------------------------------------

def curve(u, knots):
    """Smooth monotone (PCHIP) interpolation through knots [(u, value), ...]. Values may be
    numbers or arrays; the path passes every key without overshooting between them."""
    xs = [float(k[0]) for k in knots]
    scalar = np.ndim(knots[0][1]) == 0
    ys = np.array([np.atleast_1d(np.asarray(k[1], float)) for k in knots])
    if u <= xs[0]:
        out = ys[0]
    elif u >= xs[-1]:
        out = ys[-1]
    else:
        n = len(xs)
        h = np.diff(xs)
        d = np.diff(ys, axis=0) / h[:, None]
        m = np.zeros_like(ys)
        m[0], m[-1] = d[0], d[-1]
        for i in range(1, n - 1):
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            a, b = d[i - 1], d[i]
            same = a * b > 0
            sa = np.where(same, a, 1.0)
            sb = np.where(same, b, 1.0)
            m[i] = np.where(same, (w1 + w2) / (w1 / sa + w2 / sb), 0.0)
        i = max(j for j in range(n - 1) if xs[j] <= u)
        t = (u - xs[i]) / h[i]
        h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
        h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
        out = h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]
    return float(out[0]) if scalar else out


def ball_pivot(ball, fp):
    """Ankle for a foot pitched fp degrees (+ toes up) whose ball (toe-circle centre) is at `ball`.
    Keeps the ball of the foot planted while the heel rises or drops."""
    a = math.radians(fp)
    t = v3(math.cos(a), math.sin(a))
    n = v3(-math.sin(a), math.cos(a))
    b = np.asarray(ball, float)
    return v3(b[0], b[1], b[2] if len(b) > 2 else 0.0) - (n * TOE[0] + t * TOE[1])


def flat_ball(ankle_x, y=ANKLE_H):
    """Ball of the foot (toe-circle centre) of a flat foot whose ankle is at ankle_x."""
    return v3(ankle_x + TOE[1], y + TOE[0])


class Warp:
    """A phase from time through smooth monotone (t, u) keys for one rep: each part of a
    multi-step movement gets its own tempo, repeated u values are holds (start and end each rep
    with one, so it begins and ends at rest), and motion flows through the other keys without
    stopping. The second rep runs at u + 2: the other leg (see `per_leg`)."""

    def __init__(self, keys, reps=2, per_rep=2.0):
        self.keys, self.reps, self.per_rep = keys, reps, per_rep
        self.rep_t = keys[-1][0]
        self.total = self.rep_t * reps

    def __call__(self, t):
        t = t % self.total
        k = min(int(t // self.rep_t), self.reps - 1)
        return curve(t - k * self.rep_t, self.keys) + self.per_rep * k


def per_leg(fn):
    """pose(u) for a two-rep `Warp` phase from fn(u, lead): u 0..1 right leg, 2..3 left leg."""
    def pose(u):
        return fn(u, 'R') if u < 1.5 else fn(u - 2.0, 'L')
    return pose


def shoulder_pt(pose, side):
    """World shoulder of a pose with an upright pelvis (spine pitch only)."""
    sh = torso_point(pose['pelvis'], pose.get('pitch', 0.0), 0.0, TORSO + pose.get('shrug', 0.0))
    return v3(sh[0], sh[1], SHOULDER_HALF * (1 if side == 'R' else -1))


DB_OUT = 9.0                # hands out from the shoulders when holding dumbbells at the sides


def hang_arms(pose, fwd=1.5, out=DB_OUT, drop=1.2):
    """Arms hanging straight down at the sides, holding dumbbells: the hands hang out far enough
    that the inner heads pass outside the thighs (a lunging or split-squatting thigh brushes past
    them instead of running through them)."""
    for s, sg in (('L', -1), ('R', 1)):
        sh = shoulder_pt(pose, s)
        pose['arm' + s] = {'hand': v3(sh[0] + fwd, sh[1] - ARM + drop, sg * (SHOULDER_HALF + out)),
                           'pole': v3(-1.0, 0.0, 0.3 * sg)}
    return pose


# ---- small machine parts --------------------------------------------------------------------

def rod(cam, a3, b3, r=2.2):
    """A straight bar between two 3D points."""
    return Cone(cam.p(np.asarray(a3, float)), cam.p(np.asarray(b3, float)), r)


def roller(cam, c3, r=5.6, half=17.0, axis=Z):
    """A cylindrical foam roller (end-on in the side view)."""
    return eq.cyl(cam, np.asarray(c3, float), axis, r, half)


def handle(cam, c3, r=2.0, half=5.0, axis=X):
    """A short grip bar (drawn under the hand that holds it)."""
    return eq.cyl(cam, np.asarray(c3, float), axis, r, half)


def dumbbells_at_sides(J, v, u=None, axis=X):
    """Equip function: a dumbbell in each hand, handle along `axis` (neutral grip at the sides)."""
    items = []
    for s in 'LR':
        items += eq.dumbbell(v, J.p['hand' + s], axis, ('before', 'arm' + s))
    return items


# ---- 3D forms (Item.spec3d) ---------------------------------------------------------------------
# The machines as 3D primitives for view3d and the app, where the camera turns. Built from the
# same 3D points the 2D shapes project, with what the side view can't show: real widths, the far
# upright or rail of a pair, and the brackets that mount grips and rollers. Parts added for 3D are
# placed where the exercise's own camera sees them end-on or hidden, so its picture stays as it is.

def cross_foot3d(b3, half=9.0, r=1.4, color='frame'):
    """A foot along z under a post, crossing its drawn foot: end-on from the side, so only a turned
    camera sees it."""
    b3 = np.asarray(b3, float)
    return eq.rod3d(b3 - Z * half, b3 + Z * half, r, color)


def grip3d(c3, axis3, r, half, bracket3, at, color='metal'):
    """A grip and the bracket that mounts it: from the point `at` cm along the grip's axis (inside
    the grip's outline, under the fist) to bracket3 on the machine."""
    c3, ax = np.asarray(c3, float), unit(axis3)
    return eq.cyl3d(c3, ax, r, half, color) + eq.rod3d(c3 + ax * at, bracket3, 1.6, color)


def strap3d(c3, e1, e2, radius, tube, color='metal', n=12):
    """A strap or cuff round a limb: a ring of capsules in the plane of e1 and e2 through
    c3 +- e1 * radius, so that seen along e2 it is the band from c3 - e1 * radius to c3 + e1 * radius
    (eq.ring3d picks its own axes)."""
    c3, e1, e2 = np.asarray(c3, float), unit(e1), unit(e2)
    pts = [c3 + (e1 * math.cos(a) + e2 * math.sin(a)) * radius for a in np.linspace(0.0, 2 * math.pi, n + 1)]
    return eq.rope3d(pts, tube, color)


# ---- 45-degree leg press ----------------------------------------------------------------------

LP_ANG = math.radians(45.0)
LP_D = v3(math.cos(LP_ANG), math.sin(LP_ANG))       # sled travel, away from the lifter
LP_UP = v3(-math.sin(LP_ANG), math.cos(LP_ANG))     # along the foot plate, towards its top edge
LP_HIP = v3(0.0, 50.0)
LP_PITCH = -55.0            # torso recline (pelvis + spine)
LP_PPITCH = -20.0           # the pelvis' share of it
LP_PLATE_C = 4.65           # plate centre along LP_UP (the flat foot's middle sits there)
LP_FOOT_MID = 4.65          # flat foot's middle along its toe direction, from the ankle


def lp_torso(a, b):
    """Point in the reclined torso's frame (forward, up) from the hip."""
    return torso_point(LP_HIP, LP_PITCH, a, b)


def lp_arms(pose):
    for s, sg in (('L', -1), ('R', 1)):
        pose['arm' + s] = {'hand': v3(LP_HIP[0] + 1.0, LP_HIP[1] - 6.5, sg * 27.0),
                           'pole': v3(-0.2, -1.0, 0.45 * sg)}
    return pose


def lp_pose(s, foot_up=0.0, half=14.0, toe_out=6.0, knee_out=0.2, fp=135.0):
    """Lifter on the leg press. s: plate surface distance from the hip along the track."""
    A = LP_HIP + LP_D * (s - SOLE) + LP_UP * foot_up
    p = {'pelvis': LP_HIP.copy(), 'pitch': LP_PITCH - LP_PPITCH, 'p_pitch': LP_PPITCH, 'neck': 0.0}
    for side, sg in (('L', -1), ('R', 1)):
        p['leg' + side] = {'foot': v3(A[0], A[1], sg * half), 'foot_pitch': fp, 'toe_out': -toe_out,
                           'pole': LP_UP + v3(0.0, 0.0, sg * knee_out)}
    return lp_arms(p)


LP_LEG_Z = 16.0             # 3D: each upright of the track stands on two legs, splayed out to here
LP_HORN_Z = 37.0            # 3D: the sled's plates hang on a horn out of each side


def leg_press_machine(v, s, plate_c=LP_PLATE_C):
    """Seat and back pad, the 45-degree track, the sled with its foot plate at depth s.

    In 3D the seat and back stand on the drawn central frame and the track is the drawn rail down
    the middle (the calf raise's heels drop below its line either side of it: rails out under the
    sled's edges would cross them in front from the side). Each of its uprights stands on two legs
    splayed out to the sides, on a foot each; the plate drawn end-on is one of two, on a horn
    across the sled."""
    cam = v.cam
    H = LP_HIP
    f2 = lp_torso(1.0, 0.0) - H
    back = [lp_torso(-12.8, 4.0), lp_torso(-12.8, 78.0)]      # back pad, up behind the head
    pads = [eq.pad(cam, back[0], back[1], f2, width=44.0, t=7.0)]
    seat_a, seat_b = H + v3(-17.0, -12.8), H + v3(10.0, -8.5)
    pads.append(eq.pad(cam, seat_a, seat_b, Y, width=44.0, t=7.0))
    pad_cols = [eq.pad_box(back[0], back[1], f2, width=44.0, t=7.0), eq.pad_box(seat_a, seat_b, Y, width=44.0, t=7.0)]
    # 3D: the back pad 40 wide (at 44 the upper arms, hanging past its edges to the handles, ran
    # 2 cm into it); the seat 44, out to the handles' brackets
    pad_spec = (eq.pad3d(back[0], back[1], f2, width=40.0, t=7.0)
                + eq.pad3d(seat_a, seat_b, Y, width=44.0, t=7.0))
    frame = []
    # seat and back support
    base_y = 1.2
    frame.append(rod(cam, H + v3(-6.0, -18.0), v3(H[0] - 6.0, base_y), 2.2))
    frame.append(rod(cam, lp_torso(-19.0, 40.0), v3(lp_torso(-19.0, 40.0)[0], base_y), 2.2))
    frame.append(rod(cam, v3(lp_torso(-19.0, 40.0)[0] - 8.0, base_y), v3(H[0] + 2.0, base_y), 1.4))
    frame_spec = (eq.rod3d(H + v3(-6.0, -18.0), v3(H[0] - 6.0, base_y), 2.2)
                  + eq.rod3d(lp_torso(-19.0, 40.0), v3(lp_torso(-19.0, 40.0)[0], base_y), 2.2)
                  + eq.rod3d(v3(lp_torso(-19.0, 40.0)[0] - 8.0, base_y), v3(H[0] + 2.0, base_y), 1.4))
    # the track: a rail parallel to the sled travel, below the plate
    rail_off = plate_c - 32.5
    r0 = H + LP_UP * rail_off + LP_D * 22.0
    r1 = H + LP_UP * rail_off + LP_D * 128.0
    frame.append(rod(cam, r0, r1, 2.6))
    frame.append(rod(cam, r1, v3(r1[0], base_y), 2.2))
    frame.append(rod(cam, v3(r1[0] - 8.0, base_y), v3(r1[0] + 8.0, base_y), 1.4))
    frame.append(rod(cam, r0, v3(r0[0], base_y), 2.2))
    frame.append(rod(cam, v3(r0[0] - 8.0, base_y), v3(r0[0] + 8.0, base_y), 1.4))
    frame_spec += eq.rod3d(r0, r1, 2.6)
    for r in (r1, r0):
        for zl in (-LP_LEG_Z, LP_LEG_Z):
            b = v3(r[0], base_y, zl)
            frame_spec += eq.rod3d(r, b, 2.2) + eq.rod3d(b - X * 8.0, b + X * 8.0, 1.4)
    # sled: the foot plate and its carriage on the rail
    c = H + LP_D * s + LP_UP * plate_c
    plate = eq.box3(cam, c + LP_D * 3.0, LP_D, LP_UP, Z, 3.0, 28.0, 30.0, 2.4)
    cc = c + LP_D * 19.0 + LP_UP * (rail_off + 6.2)
    carriage = eq.box3(cam, cc, LP_D, LP_UP, Z, 17.0, 3.6, 30.0, 3.0)
    items = [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
             Item(Union(pads), 'pad', 'back', collider=pad_cols, spec3d=pad_spec)]
    items += [Item(carriage, 'frame', 'back', spec3d=eq.box3d(cc, LP_D, LP_UP, Z, 17.0, 3.6, 30.0, 3.0, 'frame'))]
    pc = c + LP_D * 21.0 + LP_UP * (rail_off + 19.0)
    weights = eq.plate_disc(v, pc, Z, r=15.5)
    # 3D: the horn runs across the sled on a post from the carriage, ending inside the hubs (so the
    # side view still shows the plate's face), with a plate on each end
    weights[0].spec3d = (eq.cyl3d(pc, Z, 2.6, LP_HORN_Z + 2.5, 'metal') + eq.rod3d(pc, cc, 2.2, 'frame')
                         + eq.plate3d(pc + Z * LP_HORN_Z, Z, 15.5, 2.6, False)
                         + eq.plate3d(pc - Z * LP_HORN_Z, Z, 15.5, 2.6, False))
    items += weights
    # the feet press on the plate's near face; the plate lies beyond them, so it is drawn behind
    items += [Item(plate, 'frame', 'back', collider=('box', c + LP_D * 3.0, [LP_D, LP_UP, Z], [3.0, 28.0, 30.0]),
                   spec3d=eq.box3d(c + LP_D * 3.0, LP_D, LP_UP, Z, 3.0, 28.0, 30.0, 2.4, 'frame'))]
    # safety handles beside the seat, one in each hand (the near one in front of the hip). The
    # forearms reach forward to them level, so the grips stand upright across the fists.
    for sd, sg in (('L', -1.0), ('R', 1.0)):
        hc = H + v3(1.0, -6.5, sg * 27.0)
        # 3D: a bracket from the grip's foot into the side of the seat
        items.append(Item(handle(cam, hc, r=2.1, half=5.5, axis=Y), 'metal', ('before', 'arm' + sd),
                          collider=('cylinder', hc, Y, 2.1, 5.5), grip=True,
                          spec3d=grip3d(hc, Y, 2.1, 5.5, v3(hc[0], hc[1] - 3.9, sg * 19.0), -3.9)))
    return items


def leg_press(key, muscles, foot_on_plate=0.0, half=14.0, toe_out=6.0, knee_out=0.2):
    @exercise(key, 'legs', 'side', muscles=muscles)
    def build():
        foot_up = LP_PLATE_C - LP_FOOT_MID + foot_on_plate
        # top: knees ~17 degrees short of lockout; bottom: knees a little past 90 degrees
        reach = 2.0 * math.sqrt(THIGH * SHANK) * math.cos(math.radians(17.0) / 2)
        s_top = SOLE + math.sqrt(reach ** 2 - foot_up ** 2 - (half - HIP_HALF) ** 2)
        s_bot = SOLE + math.sqrt(57.5 ** 2 - foot_up ** 2 - (half - HIP_HALF) ** 2)

        def pose(u):
            return lp_pose(lerp(s_top, s_bot, u), foot_up, half, toe_out, knee_out)

        def equip(J, v, u):
            return leg_press_machine(v, lerp(s_top, s_bot, u))

        return pose, rep_down_first(1.5, 1.3, top=0.45, bottom=0.2), equip
    return build


leg_press('legPress', ['quads', 'glutes'])
leg_press('legPressWideStance', ['quads', 'glutes', 'adductors'], foot_on_plate=10.0, half=21.0, toe_out=18.0,
          knee_out=0.55)
leg_press('legPressNarrowStance', ['quads', 'glutes'], foot_on_plate=-9.0, half=7.5, toe_out=2.0, knee_out=0.05)


# ---- lunges -----------------------------------------------------------------------------------

LUNGE_STEP = 94.0           # how far the lead ankle steps forward
# one rep (t, u): step out (u 0..0.6) and sink (0.6..1) flow together; drive up and step back
LUNGE_WARP = [(0.0, 0.0), (0.3, 0.0), (1.2, 0.6), (1.95, 1.0), (2.15, 1.0), (2.85, 0.6), (3.8, 0.0),
              (3.9, 0.0)]


def lunge(u, lead='R', pitch=4.0):
    """Forward lunge onto `lead`, u: 0 standing (feet together) .. 1 bottom (back knee low)."""
    sg = 1.0 if lead == 'R' else -1.0
    trail = 'L' if lead == 'R' else 'R'
    P = curve(u, [(0.0, v3(0.5, HIP_H - 0.6)), (0.3, v3(21.0, 90.0)), (0.5, v3(39.0, 78.0)),
                  (0.62, v3(45.0, 72.0)), (1.0, v3(50.0, 56.0))])
    p = {'pelvis': v3(P[0], P[1], 0.0), 'pitch': pitch * smooth(0.0, 0.6, u), 'neck': 0.0}
    # lead foot: swings forward in an arc, lands heel first, then flat
    a = smooth(0.0, 0.6, u)
    fx = LUNGE_STEP * a
    fy = ANKLE_H + 11.0 * math.sin(math.pi * a)
    ffp = 16.0 * smooth(0.3, 0.8, a) * (1.0 - smooth(0.9, 1.0, a))
    p['leg' + lead] = {'foot': v3(fx, fy, sg * 9.5), 'foot_pitch': ffp, 'pole': v3(1.0, 0.0, 0.1 * sg)}
    # trailing foot: heel rises about the ball of the foot, the back knee drops under the hip
    tfp = curve(u, [(0.0, 0.0), (0.18, 0.0), (0.55, -26.0), (1.0, -44.0)])
    A = ball_pivot(flat_ball(0.0), tfp)
    p['leg' + trail] = {'foot': v3(A[0], A[1], -sg * 9.5), 'foot_pitch': tfp, 'pole': v3(1.0, -0.6, -0.1 * sg)}
    return p


def lunge_arms_swing(p, u, lead):
    sg = 1.0 if lead == 'R' else -1.0
    sw = 16.0 * smooth(0.0, 0.7, u)
    p['armR'] = {'flex': -sg * sw, 'abd': 5.0, 'elbow': 12.0 + 6.0 * smooth(0.0, 0.7, u)}
    p['armL'] = {'flex': sg * sw, 'abd': 5.0, 'elbow': 12.0 + 6.0 * smooth(0.0, 0.7, u)}
    return p


@exercise('walkingLunges', 'legs', 'side', muscles=['quads', 'glutes'])
def walking_lunges():
    def one(u, lead):
        return lunge_arms_swing(lunge(u, lead), u, lead)
    return per_leg(one), Warp(LUNGE_WARP), None


@exercise('dumbbellLunges', 'legs', 'side', muscles=['quads', 'glutes'])
def dumbbell_lunges():
    def one(u, lead):
        return hang_arms(lunge(u, lead, pitch=3.0))
    return per_leg(one), Warp(LUNGE_WARP), dumbbells_at_sides


BAR_BACK = (-7.0, 53.5)         # bar on the traps, torso-local (forward, up)


@exercise('barbellLunges', 'legs', 'side', muscles=['quads', 'glutes'])
def barbell_lunges():
    # the near arm runs from the shoulder (z 18) out to the grip (z 40), all of it nearer the camera
    # than the torso, so it is drawn in front of the back; the plate at the camera end covers it
    def one(u, lead):
        p = lunge(u, lead, pitch=5.0)
        B = torso_point(p['pelvis'], p['pitch'], *BAR_BACK)
        p.update(both(v3(B[0], B[1], 40.0), [-1.0, -0.7, 0.35]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)     # carried on the back: face readable

    return per_leg(one), Warp(LUNGE_WARP), equip


# ---- Bulgarian split squat ------------------------------------------------------------------

BSS_BALL = v3(-62.0, BENCH_H + R_TOE)      # rear foot's toes on the bench
BSS_FRONT = 33.0                           # front ankle x


def bss_pose(u):
    P = v3(lerp(0.0, 2.0, u), lerp(88.0, 52.5, u), 0.0)
    p = {'pelvis': P, 'pitch': lerp(4.0, 9.0, u), 'neck': -2.0}
    p['legR'] = {'foot': v3(BSS_FRONT, ANKLE_H, 10.0), 'foot_pitch': 0.0, 'toe_out': 4.0,
                 'pole': v3(1.0, 0.0, 0.12)}
    fp = lerp(190.0, 203.0, u)
    A = ball_pivot(BSS_BALL, fp)
    p['legL'] = {'foot': v3(A[0], A[1], -9.0), 'foot_pitch': fp, 'pole': v3(0.35, -1.0, -0.05)}
    return hang_arms(p)


@exercise('bulgarianSplitSquats', 'legs', 'side', muscles=['quads', 'glutes'])
def bulgarian_split_squats():
    def equip(J, v, u):
        bench = eq.bench(v, v3(BSS_BALL[0] + 9.0 - 45.0, BENCH_H, 0.0), length=90.0)
        return bench + dumbbells_at_sides(J, v)
    return bss_pose, rep_down_first(1.5, 1.3, top=0.45, bottom=0.2), equip


# ---- step-ups ---------------------------------------------------------------------------------

BOX_H = 42.0
BOX_X0 = 24.0               # near edge of the box
STEP_X = 44.0               # ankle x standing on the box

# Both feet pass the box's near top edge on their way up (and back down). The toes clear it: a
# foot rises in front of the box until its toes are above the top, and only then travels over it.
# Keys are (u, (ankle x, ankle y, foot pitch)).
LEAD_KEYS = [(0.0, v3(0.0, ANKLE_H, 0.0)), (0.061, v3(2.5, 30.0, 12.0)), (0.105, v3(4.5, 48.5, 14.0)),
             (0.14, v3(16.0, 58.0, 12.0)), (0.18, v3(34.0, 61.0, 8.0)), (0.22, v3(STEP_X, BOX_H + ANKLE_H, 0.0))]


def _trail_keys():
    top_y = BOX_H + ANKLE_H
    ks = [(0.0, v3(0.0, ANKLE_H, 0.0)), (0.26, v3(0.0, ANKLE_H, 0.0))]
    for i in range(1, 10):                  # the heel peels: dense keys on the ball-pivot arc
        uu = 0.26 + 0.18 * i / 9
        fp = -30.0 * smooth(0.26, 0.44, uu)
        A = ball_pivot(flat_ball(0.0), fp)
        ks.append((uu, v3(A[0], A[1], fp)))
    # the toes lift as the foot swings up past the edge
    ks += [(0.56, v3(6.5, 36.0, -28.0)), (0.63, v3(7.5, 53.0, -16.0)), (0.69, v3(18.0, 62.0, -12.0)),
           (0.78, v3(32.0, 65.0, -6.0)), (0.87, v3(STEP_X, top_y + 4.0, 2.0)), (0.93, v3(STEP_X, top_y, 0.0)),
           (1.0, v3(STEP_X, top_y, 0.0))]
    return ks


TRAIL_KEYS = _trail_keys()


def step_up(u, lead='R'):
    """Step up onto the box with `lead`, bring the other foot up, stand tall. u 0..1."""
    sg = 1.0 if lead == 'R' else -1.0
    trail = 'L' if lead == 'R' else 'R'
    P = curve(u, [(0.0, v3(0.5, HIP_H - 0.6)), (0.22, v3(4.0, 93.2)), (0.42, v3(15.0, 98.5)),
                  (0.6, v3(30.0, 118.0)), (0.78, v3(41.0, 132.5)), (1.0, v3(44.5, BOX_H + HIP_H - 0.6))])
    p = {'pelvis': v3(P[0], P[1], 0.0), 'neck': 0.0,
         'pitch': curve(u, [(0.0, 0.0), (0.25, 6.0), (0.5, 12.0), (0.8, 4.0), (1.0, 0.0)])}
    # lead foot: up and over the box edge, placed flat
    L = curve(u, LEAD_KEYS)
    p['leg' + lead] = {'foot': v3(L[0], L[1], sg * 10.0), 'foot_pitch': L[2], 'pole': v3(1.0, 0.0, 0.12 * sg)}
    # trailing foot: heel peels off the floor (keys on the ball-pivot arc), pushes off, swings up
    # onto the box; one smooth curve so the push-off flows into the swing
    K = curve(u, TRAIL_KEYS)
    A, fp = K, K[2]
    p['leg' + trail] = {'foot': v3(A[0], A[1], -sg * 10.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, -0.12 * sg)}
    sw = 10.0 * math.sin(math.pi * smooth(0.0, 0.9, u))
    p['armR'] = {'flex': -sg * sw + 4.0, 'abd': 5.0, 'elbow': 14.0}
    p['armL'] = {'flex': sg * sw + 4.0, 'abd': 5.0, 'elbow': 14.0}
    return p


@exercise('stepUps', 'legs', 'side', muscles=['quads', 'glutes'])
def step_ups():
    def equip(J, v, u):
        return eq.plyo_box(v, v3(BOX_X0 + 25.0, BOX_H / 2, 0.0), hx=25.0, hy=BOX_H / 2, hz=32.0)

    # place the lead foot, shift onto it, drive up while the trailing leg swings through under
    # control, stand tall; then the trailing leg steps down first and the lead foot follows
    one = [(0.0, 0.0), (0.2, 0.0), (0.95, 0.215), (1.05, 0.225), (1.4, 0.44), (2.25, 0.93),
           (2.45, 1.0), (2.65, 1.0), (2.9, 0.93), (3.75, 0.44), (4.1, 0.225), (4.2, 0.215), (4.95, 0.0),
           (5.05, 0.0)]
    return per_leg(step_up), Warp(one), equip


# ---- calf raises ------------------------------------------------------------------------------

STEP_TOP = 20.0             # calf-raise step height


def calf_stand(u, x_ball=16.0, top=STEP_TOP, drop=14.0, rise=-32.0):
    """Standing on the balls of the feet on a step edge; u 0 heels low .. 1 heels high."""
    fp = lerp(drop, rise, u)
    A = ball_pivot(v3(x_ball, top + R_TOE), fp)
    px = x_ball - 9.0
    reach = 86.6
    dz = 11.0 - HIP_HALF
    py = A[1] + math.sqrt(reach ** 2 - (px - A[0]) ** 2 - dz ** 2)
    p = {'pelvis': v3(px, py, 0.0), 'pitch': 1.5, 'neck': 0.0}
    for s, sg in (('L', -1), ('R', 1)):
        p['leg' + s] = {'foot': v3(A[0], A[1], sg * 11.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, 0.2 * sg)}
    return p


@exercise('calfRaises', 'legs', 'side', muscles=['calves'])
def calf_raises():
    x_ball = 16.0

    def pose(u):
        p = calf_stand(u, x_ball)
        sh = shoulder_pt(p, 'R')
        return merge(p, **both(v3(sh[0] + 3.0, sh[1] - ARM + 1.5, SHOULDER_HALF + 3.5), [-1.0, 0.0, 0.3]))

    def equip(J, v, u):
        c = v3(x_ball - 2.0 + 24.0, STEP_TOP / 2, 0.0)
        step = eq.box3(v.cam, c, X, Y, Z, 24.0, STEP_TOP / 2, 30.0, 3.0)
        return [Item(step, 'pad', 'back', collider=('box', c, [X, Y, Z], [24.0, STEP_TOP / 2, 30.0]),
                     spec3d=eq.box3d(c, X, Y, Z, 24.0, STEP_TOP / 2, 30.0, 3.0, 'pad'))]

    return pose, rep(1.2, 1.4, top=0.35, bottom=0.45), equip


# ---- seated machines --------------------------------------------------------------------------

def seat_and_back(v, P, pitch, seat_top, seat_x0=-17.0, seat_x1=33.0, back_to=60.0, width=40.0):
    """A machine seat under the thighs and a back pad along the back, on thin frame posts."""
    cam = v.cam
    seat = (v3(P[0] + seat_x0, seat_top, 0.0), v3(P[0] + seat_x1, seat_top, 0.0), Y)
    f2 = torso_point(P, pitch, 1.0, 0.0) - np.asarray(P, float)
    back = (torso_point(P, pitch, -12.8, 5.0), torso_point(P, pitch, -12.8, back_to), f2)
    pads = [eq.pad(cam, *seat, width=width), eq.pad(cam, *back, width=width)]
    cols = [eq.pad_box(*seat, width=width), eq.pad_box(*back, width=width)]
    under = seat_top - eq.PAD_T
    top = v3(P[0] + 0.5 * (seat_x0 + seat_x1), under, 0.0)
    frame = eq.post(cam, top, 1.2, 2.2, 9.0)
    brace = torso_point(P, pitch, -19.8, back_to * 0.5)
    frame.append(rod(cam, brace, v3(brace[0] + 6.0, under, 0.0), 1.8))
    frame_spec = (eq.post3d(top, 1.2, 2.2, 9.0) + cross_foot3d(v3(top[0], 1.2, 0.0))
                  + eq.rod3d(brace, v3(brace[0] + 6.0, under, 0.0), 1.8))
    pad_spec = eq.pad3d(*seat, width=width) + eq.pad3d(*back, width=width)
    return [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
            Item(Union(pads), 'pad', 'back', collider=cols, spec3d=pad_spec)]


SEAT_HANDLE_Z = 27.0        # grips beside the seat, just outside the hips


def seat_handles(pose, P, seat_top, x=-3.0, z=SEAT_HANDLE_Z):
    """Hands on the handles beside the seat."""
    for s, sg in (('L', -1), ('R', 1)):
        pose['arm' + s] = {'hand': v3(P[0] + x, seat_top + 1.5, sg * z), 'pole': v3(-0.3, -1.0, 0.5 * sg)}
    return pose


def seat_handle_items(v, P, seat_top, x=-3.0, z=SEAT_HANDLE_Z):
    """The grips under the hands of `seat_handles`: each sits just behind its fist, so the near
    one is drawn in front of the hip and thigh and the far one behind the body."""
    items = []
    for s, sg in (('L', -1.0), ('R', 1.0)):
        c = v3(P[0] + x, seat_top + 1.5, sg * z)
        # 3D: a bracket from the grip's rear end in to the seat's edge (end-on from the side)
        items.append(Item(handle(v.cam, c, 2.0, 6.0), 'metal', ('before', 'arm' + s),
                          collider=('cylinder', c, X, 2.0, 6.0), grip=True,
                          spec3d=grip3d(c, X, 2.0, 6.0, v3(c[0] - 4.4, c[1], sg * (z - 8.0)), -4.4)))
    return items


def shank_point(J, side, along, out):
    """A point on the shin: `along` cm from the knee, `out` cm off its axis towards the shin's
    front (+) or calf (-)."""
    K, A = J.p['knee' + side], J.p['ankle' + side]
    return K + unit(A - K) * along + J.v['shank_front' + side] * out


def thigh_point(J, side, along, out):
    H, K = J.p['hip' + side], J.p['knee' + side]
    return H + unit(K - H) * along + J.v['thigh_front' + side] * out


def flat(p3):
    return v3(p3[0], p3[1], 0.0)


def shank_r(along):
    return R_SHANK[0] + (R_SHANK[1] - R_SHANK[0]) * along / SHANK


def thigh_r(along):
    return R_THIGH[0] + (R_THIGH[1] - R_THIGH[0]) * along / THIGH


ROLL_R = 5.6                # foam roller radius
ROLL_HALF = 17.0            # a two-leg roller spans both shins
LEVER_Z = -21.0             # two-leg machines carry the lever on the far side, just outside the left knee


def roller_col(c3, half=ROLL_HALF, r=ROLL_R):
    return ('cylinder', np.asarray(c3, float), Z, r, half)


def housing_z(lever_z):
    """3D: the depth of a lever's pivot housing, on the side of the lever away from the legs (a
    two-leg machine's out beyond its far-side lever, the standing curl's between the knees)."""
    return lever_z - 4.0 if lever_z < -5.0 else lever_z - 2.0


def roller3d(c3, lever_z, half=ROLL_HALF, r=ROLL_R):
    """A foam roller across the legs and the axle that carries it out to the lever at lever_z."""
    c3 = np.asarray(c3, float)
    return eq.cyl3d(c3, Z, r, half, 'pad') + eq.rod3d(v3(c3[0], c3[1], lever_z), c3, 1.2, 'metal')


def lever_frame3d(pivot3, base3, lever_z=LEVER_Z):
    """3D for the frame rod a caller draws from a far-side lever's pivot down to the seat or bench:
    it runs at the housing's depth, beside the seat (not through it), then across under it."""
    hz = housing_z(lever_z)
    b = v3(base3[0], base3[1], hz)
    return eq.rod3d(v3(pivot3[0], pivot3[1], hz), b, 2.2) + eq.rod3d(b, v3(base3[0], base3[1], 0.0), 2.2)


def lever_items(v, pivot3, roller3, housing=True, lever_z=LEVER_Z, roller_half=ROLL_HALF, z='back'):
    """A machine lever from its pivot (aligned with the knee) to a foam roller. The lever swings at
    depth lever_z (a two-leg machine's on the far side, so it and its pivot hide behind the legs);
    the roller runs across the legs, centred on roller3.

    In 3D the housing is a hub beside the lever (housing_z), the pin runs through both, and the
    roller sits on an axle out to the lever."""
    cam = v.cam
    items = []
    hz = housing_z(lever_z)
    if housing:
        items.append(Item(Circle(cam.p(pivot3), 5.2), 'frame', z,
                          spec3d=eq.cyl3d(v3(pivot3[0], pivot3[1], hz), Z, 5.2, 1.2, 'frame')))
    a, b = v3(pivot3[0], pivot3[1], lever_z), v3(roller3[0], roller3[1], lever_z)
    z0, z1 = hz - 1.2, lever_z + 1.6                    # the pin: from the housing's far face into the lever
    pin = eq.cyl3d(v3(pivot3[0], pivot3[1], (z0 + z1) / 2), Z, 2.0, (z1 - z0) / 2, 'metal')
    items.append(Item(rod(cam, pivot3, roller3, 1.9), 'metal', z, collider=('capsule', a, b, 1.9),
                      spec3d=eq.rod3d(a, b, 1.9, 'metal') + pin))
    items.append(Item(Circle(cam.p(pivot3), 2.0), 'metal', z, spec3d=[]))
    items.append(Item(roller(cam, roller3, half=roller_half), 'pad', z, collider=roller_col(roller3, roller_half),
                      spec3d=roller3d(roller3, lever_z, roller_half)))
    return items


LE_SEAT = 52.0
LE_P = v3(0.0, LE_SEAT + 9.0, 0.0)
LE_PITCH = -12.0


@exercise('legExtension', 'legs', 'side', muscles=['quads'])
def leg_extension():
    def pose(u):
        p = {'pelvis': LE_P.copy(), 'pitch': LE_PITCH, 'neck': 3.0}
        k = lerp(88.0, 3.0, u)
        for s in 'LR':
            p['leg' + s] = {'hip': 88.0, 'abd': 2.0, 'knee': k, 'ankle': -6.0}
        return seat_handles(p, LE_P, LE_SEAT)

    def equip(J, v, u):
        items = seat_and_back(v, LE_P, LE_PITCH, LE_SEAT)
        pivot = flat(J.p['kneeR'])
        along = SHANK - 7.5
        rc = flat(shank_point(J, 'R', along, shank_r(along) + ROLL_R + 0.4))
        base = v3(LE_P[0] + 8.0, LE_SEAT - eq.PAD_T, 0.0)
        items.insert(0, Item(rod(v.cam, pivot, base, 2.2), 'frame', 'back', spec3d=lever_frame3d(pivot, base)))
        items += lever_items(v, pivot, rc)
        return items + seat_handle_items(v, LE_P, LE_SEAT)

    return pose, rep(1.3, 1.6, top=0.4, bottom=0.35), equip


# ---- lying and seated leg curls ---------------------------------------------------------------

LC_TOP = 58.0               # leg-curl bench pad top
LC_HAND = (60.0, LC_TOP - 15.0, 23.0)     # the grips at the head end, below the bench (x, y, |z|)


def prone_curl_pose(u, decline=0.0):
    P = v3(0.0, LC_TOP + 13.0, 0.0)
    p = {'pelvis': P, 'p_pitch': 90.0, 'pitch': decline, 'neck': 22.0}
    k = lerp(4.0, 122.0, u)
    for s in 'LR':
        p['leg' + s] = {'hip': 7.0, 'abd': 2.0, 'knee': k, 'ankle': lerp(6.0, -4.0, u)}
    for s, sg in (('L', -1), ('R', 1)):
        p['arm' + s] = {'hand': v3(LC_HAND[0], LC_HAND[1], sg * LC_HAND[2]), 'pole': v3(-1.0, 0.0, 0.7 * sg)}
    return p


def leg_curl_bench(v, decline=0.0):
    cam = v.cam
    P = v3(0.0, LC_TOP + 13.0, 0.0)
    hip = v3(P[0], LC_TOP, 0.0)
    a = math.radians(decline)
    chest = hip + v3(math.cos(a), -math.sin(a)) * 50.0
    tops = [(v3(P[0] - 37.0, LC_TOP - 3.0, 0.0), hip + v3(2.0, 0.0, 0.0)), (hip + v3(-2.0, 0.0, 0.0), chest)]
    pads = [eq.pad(cam, a3, b3, Y, width=36.0) for a3, b3 in tops]
    cols = [eq.pad_box(a3, b3, Y, width=36.0) for a3, b3 in tops]
    under = LC_TOP - eq.PAD_T
    posts = [v3(P[0] - 22.0, under - 1.5, 0.0), v3(chest[0] - 12.0, chest[1] - eq.PAD_T - 1.0, 0.0)]
    frame = eq.post(cam, posts[0], 1.2, 2.2, 9.0)
    frame += eq.post(cam, posts[1], 1.2, 2.2, 9.0)
    hx, hy, hz = LC_HAND
    arm = (v3(chest[0] - 12.0, chest[1] - eq.PAD_T - 6.0, 0.0), v3(hx, hy, 0.0))
    frame.append(rod(cam, *arm, 1.8))
    # 3D: each post with a foot across too; the arm to the grips ends on a bar across between them
    # (end-on from the side, inside the near fist)
    frame_spec = []
    for p in posts:
        frame_spec += eq.post3d(p, 1.2, 2.2, 9.0) + cross_foot3d(v3(p[0], 1.2, 0.0))
    frame_spec += eq.rod3d(*arm, 1.8) + eq.rod3d(v3(hx, hy, -hz), v3(hx, hy, hz), 1.8)
    items = [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
             Item(Union(pads), 'pad', 'back', collider=cols,
                  spec3d=[e for a3, b3 in tops for e in eq.pad3d(a3, b3, Y, width=36.0)])]
    # the forearms reach forward to the grips, so the grips stand upright across the fists
    for s, sg in (('L', -1.0), ('R', 1.0)):
        c = v3(hx, hy, sg * hz)
        items.append(Item(handle(cam, c, 2.0, 6.0, axis=Y), 'metal', ('before', 'arm' + s),
                          collider=('cylinder', c, Y, 2.0, 6.0), grip=True, spec3d=eq.cyl3d(c, Y, 2.0, 6.0, 'metal')))
    return items


def lying_leg_curl(key, decline):
    @exercise(key, 'legs', 'side', muscles=['hamstrings'])
    def build():
        def pose(u):
            return prone_curl_pose(u, decline)

        def equip(J, v, u):
            items = leg_curl_bench(v, decline)
            pivot = flat(J.p['kneeR'])
            along = SHANK - 7.0
            rc = flat(shank_point(J, 'R', along, -(shank_r(along) + ROLL_R + 0.4)))
            base = v3(pivot[0] + 10.0, LC_TOP - eq.PAD_T - 1.5, 0.0)
            items.insert(0, Item(rod(v.cam, pivot, base, 2.2), 'frame', 'back', spec3d=lever_frame3d(pivot, base)))
            return items + lever_items(v, pivot, rc)

        return pose, rep(1.2, 1.6, top=0.4, bottom=0.35), equip
    return build


lying_leg_curl('legCurls', 0.0)
lying_leg_curl('lyingLegCurls', 12.0)


SLC_SEAT = 50.0
SLC_P = v3(0.0, SLC_SEAT + 9.0, 0.0)
SLC_PITCH = -14.0


@exercise('seatedLegCurls', 'legs', 'side', muscles=['hamstrings'])
def seated_leg_curls():
    def pose(u):
        p = {'pelvis': SLC_P.copy(), 'pitch': SLC_PITCH, 'neck': 3.0}
        k = lerp(6.0, 100.0, u)
        for s in 'LR':
            p['leg' + s] = {'hip': 88.0, 'abd': 2.0, 'knee': k, 'ankle': -8.0}
        return seat_handles(p, SLC_P, SLC_SEAT)

    def equip(J, v, u):
        items = seat_and_back(v, SLC_P, SLC_PITCH, SLC_SEAT)
        pivot = flat(J.p['kneeR'])
        along = SHANK - 6.5
        rc = flat(shank_point(J, 'R', along, -(shank_r(along) + ROLL_R + 0.4)))
        ta = THIGH - 10.0
        tp = flat(thigh_point(J, 'R', ta, thigh_r(ta) + ROLL_R + 0.4))
        base = v3(SLC_P[0] + 8.0, SLC_SEAT - eq.PAD_T, 0.0)
        items.insert(0, Item(rod(v.cam, pivot, base, 2.2), 'frame', 'back', spec3d=lever_frame3d(pivot, base)))
        # the thigh hold-down's arm swings with the lever on the far side
        arm = ('capsule', v3(pivot[0], pivot[1], LEVER_Z), v3(tp[0], tp[1], LEVER_Z), 1.9)
        items.append(Item(rod(v.cam, pivot, tp, 1.9), 'metal', 'back', collider=arm,
                          spec3d=eq.rod3d(arm[1], arm[2], 1.9, 'metal')))
        items += lever_items(v, pivot, rc)
        items.append(Item(roller(v.cam, tp), 'pad', 'back', collider=roller_col(tp), spec3d=roller3d(tp, LEVER_Z)))
        return items + seat_handle_items(v, SLC_P, SLC_SEAT)

    return pose, rep(1.3, 1.6, top=0.4, bottom=0.35), equip


# ---- standing leg curl ------------------------------------------------------------------------

SC_PLAT = 10.0              # standing platform height


@exercise('standingLegCurls', 'legs', 'side', muscles=['hamstrings'])
def standing_leg_curls():
    P = v3(0.0, SC_PLAT + HIP_H - 1.4, 0.0)
    col_x = 36.0
    hand = v3(col_x - 6.0, 121.0)

    def pose(u):
        p = {'pelvis': P.copy(), 'pitch': 12.0, 'neck': 2.0}
        p['legL'] = {'foot': v3(-1.0, SC_PLAT + ANKLE_H, -10.0), 'toe_out': 6.0, 'pole': v3(1.0, 0.0, -0.2)}
        # the working foot is flexed (toes up), so its toes clear the platform as the curl begins
        p['legR'] = {'hip': 9.0, 'abd': 2.0, 'knee': lerp(12.0, 112.0, u), 'ankle': lerp(-12.0, -4.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['arm' + s] = {'hand': v3(hand[0], hand[1], sg * 20.0), 'pole': v3(-0.2, -1.0, 0.4 * sg)}
        return p

    # A one-leg machine: the thigh pad and the ankle roller span the working (right, near) leg
    # only, and the lever swings between the knees. So they are drawn in front of the standing leg
    # and behind the working one (a two-leg roller would run through the standing leg).
    lz = 0.5                                # the lever's depth, between the knees
    pz0, pz1 = lz, 18.5                     # the pads run from the lever out past the working leg
    pzc, phalf = (pz0 + pz1) / 2, (pz1 - pz0) / 2
    between = ('after', 'legL')

    def equip(J, v, u):
        cam = v.cam
        col = (v3(col_x, 1.2, 0.0), v3(col_x, hand[1] + 4.0, 0.0))
        foot = (v3(col_x - 14.0, 1.2, 0.0), v3(col_x + 14.0, 1.2, 0.0))
        frame = [rod(cam, *col, 2.6), rod(cam, *foot, 1.4)]
        # 3D: a foot across as well, and an arm from the column out to each grip (hidden behind
        # the near fist and the column from the side)
        frame_spec = (eq.rod3d(*col, 2.6) + eq.rod3d(*foot, 1.4) + cross_foot3d(col[0], 14.0)
                      + [e for sg in (-1.0, 1.0) for e in eq.rod3d(v3(col_x, hand[1], 0.0),
                                                                    v3(hand[0], hand[1], sg * 20.0), 1.6)])
        pc = v3(-2.0, SC_PLAT / 2, 0.0)
        plat = eq.box3(cam, pc, X, Y, Z, 26.0, SC_PLAT / 2, 30.0, 2.5)
        pivot = flat(J.p['kneeR'])
        ta = THIGH - 9.0
        tp = flat(thigh_point(J, 'R', ta, thigh_r(ta) + ROLL_R + 0.4))
        links = [(tp, v3(col_x, tp[1], 0.0)), (pivot, v3(col_x, pivot[1] - 6.0, 0.0))]
        along = SHANK - 7.0
        rc = flat(shank_point(J, 'R', along, -(shank_r(along) + ROLL_R + 0.4)))
        items = [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
                 Item(plat, 'pad', 'back', collider=('box', pc, [X, Y, Z], [26.0, SC_PLAT / 2, 30.0]),
                      spec3d=eq.box3d(pc, X, Y, Z, 26.0, SC_PLAT / 2, 30.0, 2.5, 'pad'))]
        items.append(Item(Union([rod(cam, a, b, 2.0) for a, b in links]), 'frame', between,
                          collider=[('capsule', a + Z * lz, b + Z * lz, 2.0) for a, b in links],
                          spec3d=[e for a, b in links for e in eq.rod3d(a + Z * lz, b + Z * lz, 2.0)]))
        items += lever_items(v, pivot, rc + Z * pzc, lever_z=lz, roller_half=phalf, z=between)
        items.append(Item(roller(cam, tp, half=phalf), 'pad', between, collider=roller_col(tp + Z * pzc, phalf),
                          spec3d=eq.cyl3d(tp + Z * pzc, Z, ROLL_R, phalf, 'pad')))
        # the forearms reach forward to the column, so its grips stand upright across the fists
        for s, sg in (('L', -1.0), ('R', 1.0)):
            c = v3(hand[0], hand[1], sg * 20.0)
            items.append(Item(handle(cam, c, 2.0, 6.0, axis=Y), 'metal', ('before', 'arm' + s),
                              collider=('cylinder', c, Y, 2.0, 6.0), grip=True,
                              spec3d=eq.cyl3d(c, Y, 2.0, 6.0, 'metal')))
        return items

    return pose, rep(1.2, 1.5, top=0.4, bottom=0.35), equip


# ---- calf raises on machines ------------------------------------------------------------------

SCR_BALL = v3(58.5, 12.0 + R_TOE)        # seated calf raise: balls of the feet on the block edge
SCR_P = v3(0.0, 63.5, 0.0)


@exercise('seatedCalfRaises', 'legs', 'side', muscles=['calves'])
def seated_calf_raises():
    def pose(u):
        fp = lerp(16.0, -30.0, u)
        A = ball_pivot(SCR_BALL, fp)
        p = {'pelvis': SCR_P.copy(), 'pitch': 6.0, 'neck': 0.0}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 10.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.6, 0.15 * sg)}
        return p

    def pad_center(J):
        ta = THIGH - 8.0
        return flat(thigh_point(J, 'R', ta, thigh_r(ta) + ROLL_R + 0.6))

    def pose_with_hands(u):
        """Hands rest on the knee pad, which rides on the thighs: solve the legs first."""
        p = pose(u)
        pc = pad_center(solve(p))
        for s, sg in (('L', -1), ('R', 1)):
            p['arm' + s] = {'hand': v3(pc[0] + 1.0, pc[1] + ROLL_R + 1.5, sg * 19.0), 'pole': v3(-0.4, -1.0, 0.5 * sg)}
        return p

    def equip(J, v, u):
        cam = v.cam
        seat_top = SCR_P[1] - 9.0
        seat = (v3(-17.0, seat_top, 0.0), v3(30.0, seat_top, 0.0), Y)
        pads = [eq.pad(cam, *seat, width=40.0)]
        bc = v3(SCR_BALL[0] + 12.0, 6.0, 0.0)
        block = eq.box3(cam, bc, X, Y, Z, 14.0, 6.0, 30.0, 2.5)
        cols = [eq.pad_box(*seat, width=40.0), ('box', bc, [X, Y, Z], [14.0, 6.0, 30.0])]
        post_top = v3(6.0, seat_top - eq.PAD_T, 0.0)
        frame = eq.post(cam, post_top, 1.2, 2.2, 9.0)
        rail = (v3(6.0, 1.2, 0.0), v3(SCR_BALL[0] + 26.0, 1.2, 0.0))
        frame.append(rod(cam, *rail, 1.4))
        frame_spec = eq.post3d(post_top, 1.2, 2.2, 9.0) + cross_foot3d(rail[0]) + eq.rod3d(*rail, 1.4)
        pc = pad_center(J)
        pivot = v3(SCR_BALL[0] + 24.0, 14.0, 0.0)
        items = [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
                 Item(Union(pads + [block]), 'pad', 'back', collider=cols,
                      spec3d=eq.pad3d(*seat, width=40.0) + eq.box3d(bc, X, Y, Z, 14.0, 6.0, 30.0, 2.5, 'pad'))]
        # the lever and its plate run up the middle, between the knees: in front of the far leg,
        # behind the near one
        between = ('after', 'legL')
        items.append(Item(rod(cam, pivot, pc, 2.2), 'metal', between, collider=('capsule', pivot, pc, 2.2),
                          spec3d=eq.rod3d(pivot, pc, 2.2, 'metal')))
        # 3D: the pivot's housing sits on the block behind the lever (the side view keeps the
        # lever's end in front of it)
        items.append(Item(Circle(cam.p(pivot), 3.6), 'frame', 'back',
                          spec3d=eq.cyl3d(pivot - Z * 4.4, Z, 3.6, 2.0, 'frame')))
        items += eq.plate_disc(v, pc + v3(9.0, 4.0, 0.0), Z, r=13.0, z=between)
        items.append(Item(roller(cam, pc, r=ROLL_R + 0.4), 'pad', 'back', collider=roller_col(pc, r=ROLL_R + 0.4),
                          spec3d=eq.cyl3d(pc, Z, ROLL_R + 0.4, ROLL_HALF, 'pad')))
        return items

    return pose_with_hands, rep(1.1, 1.4, top=0.35, bottom=0.45), equip


@exercise('legPressCalfRaise', 'legs', 'side', muscles=['calves'])
def leg_press_calf_raise():
    c_up = LP_PLATE_C - 28.0 + 5.0         # balls of the feet just above the plate's lower edge
    a_d = 80.5                             # legs long, knees soft

    def geo(u):
        fp = lerp(128.0, 84.0, u)
        a = math.radians(fp)
        t, n = v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a))
        o = n * TOE[0] + t * TOE[1]
        a_up = c_up - float(np.dot(o, LP_UP))
        s = a_d + float(np.dot(o, LP_D)) + R_TOE
        return fp, a_up, s

    def pose(u):
        fp, a_up, s = geo(u)
        A = LP_HIP + LP_D * a_d + LP_UP * a_up
        p = {'pelvis': LP_HIP.copy(), 'pitch': LP_PITCH - LP_PPITCH, 'p_pitch': LP_PPITCH, 'neck': 0.0}
        for side, sg in (('L', -1), ('R', 1)):
            p['leg' + side] = {'foot': v3(A[0], A[1], sg * 12.0), 'foot_pitch': fp,
                               'pole': LP_UP + v3(0.0, 0.0, sg * 0.15)}
        return lp_arms(p)

    def equip(J, v, u):
        return leg_press_machine(v, geo(u)[2])

    return pose, rep(1.1, 1.4, top=0.35, bottom=0.45), equip


# ---- hip abduction / adduction machines (front view) ----------------------------------------

HM_SLOPE = 30.0             # thighs slope down to the knees, so they read from the front
HM_REST = 4.0               # footrest top
HM_P = v3(0.0, HM_REST + SOLE + SHANK + THIGH * math.sin(math.radians(HM_SLOPE)), 0.0)
HM_SEAT = HM_P[1] - 9.0
HM_PITCH = -8.0
HM_HAND = (5.0, HM_SEAT + 3.0, 29.0)      # grips beside the seat, just outside it (x, y, |z|)


def hip_machine_pose(abd):
    p = {'pelvis': HM_P.copy(), 'pitch': HM_PITCH, 'neck': 0.0}
    for s in 'LR':
        p['leg' + s] = {'hip': 90.0 - HM_SLOPE, 'abd': abd, 'knee': 90.0 - HM_SLOPE, 'ankle': 0.0}
    for s, sg in (('L', -1), ('R', 1)):
        p['arm' + s] = {'hand': v3(HM_HAND[0], HM_HAND[1], sg * HM_HAND[2]), 'pole': v3(-0.2, -0.4, 1.0 * sg)}
    return p


def ortho_box(c3, e1, e2, half):
    """A box collider along e1, with e2 made square to it (for pads laid along a sloping limb)."""
    e1 = unit(e1)
    e2 = unit(e2 - np.dot(e2, e1) * e1)
    return ('box', np.asarray(c3, float), [e1, e2, np.cross(e1, e2)], list(half))


def hip_machine(v, J, outside):
    """Seat, back pad, knee pads on the outside (abduction) or inside (adduction) of the knees and
    footrests; each leg's pad and footrest ride on one swinging arm.

    Seen from the front, the knee pads sit out by the knees, 20 cm and more nearer the camera than
    the hands beside the seat, so they cover the hands and forearms. The thighs slope down towards
    the camera, so an inside pad also lies in front of the leg it presses on, while an outside pad
    lies behind its knee. The front view paints the arms after the legs, so an outside pad is drawn
    after the arm with its leg (and the leg's knockout gap) cut out of it. The arm carrying a pad
    runs down beside the shin to a footrest flush under the sole, behind the leg."""
    cam = v.cam
    # the seat ends just in front of the hips: the thighs slope down from there, so a longer seat
    # would run through them (the front view shows its width and height, not its length)
    seat_c = v3(-6.5, HM_SEAT - 3.5, 0.0)
    pads = [eq.box3(cam, seat_c, X, Y, Z, 9.5, 3.5, 23.0, 3.0)]
    f2 = torso_point(HM_P, HM_PITCH, 1.0, 0.0) - HM_P
    u2 = torso_point(HM_P, HM_PITCH, 0.0, 1.0) - HM_P
    back_c = torso_point(HM_P, HM_PITCH, -16.0, 36.0)
    pads.append(eq.box3(cam, back_c, f2, u2, Z, 3.5, 34.0, 21.0, 3.0))
    cols = [('box', seat_c, [X, Y, Z], [9.5, 3.5, 23.0]), ('box', back_c, [f2, u2, Z], [3.5, 34.0, 21.0])]
    frame = [rod(cam, v3(0.0, HM_SEAT - 7.0, 0.0), v3(0.0, 1.2, 0.0), 2.4),
             rod(cam, v3(0.0, 1.2, -24.0), v3(0.0, 1.2, 24.0), 1.4)]
    # 3D: a second post carries the back pad (from the front it stands behind the seat post), and a
    # foot along the machine (end-on from the front) joins the two
    bp = torso_point(HM_P, HM_PITCH, -19.5, 6.0)
    frame_spec = (eq.rod3d(v3(0.0, HM_SEAT - 7.0, 0.0), v3(0.0, 1.2, 0.0), 2.4)
                  + eq.rod3d(v3(0.0, 1.2, -24.0), v3(0.0, 1.2, 24.0), 1.4)
                  + eq.rod3d(bp, v3(bp[0], 1.2, 0.0), 2.0) + eq.rod3d(v3(bp[0], 1.2, 0.0), v3(20.0, 1.2, 0.0), 1.4))
    # 3D: the seat's front edge 2 cm further back (out of the sloping thighs; the front view doesn't
    # see its length)
    items = [Item(Union(frame), 'frame', 'back', spec3d=frame_spec),
             Item(Union(pads), 'pad', 'back', collider=cols,
                  spec3d=(eq.box3d(seat_c - X * 1.0, X, Y, Z, 8.5, 3.5, 23.0, 3.0, 'pad')
                          + eq.box3d(back_c, f2, u2, Z, 3.5, 34.0, 21.0, 3.0, 'pad')))]
    # knee pads: (half length along the thigh, how far above the knee, half thickness). The inside
    # pads are smaller: the thighs converge towards the hips, and with the legs closed the two
    # pads just meet between the knees instead of running into each other
    p_len, p_up, p_t = (9.0, 5.0, 3.2) if outside else (6.0, 2.0, 1.8)
    for s, sg in (('L', -1.0), ('R', 1.0)):
        H, K, A = J.p['hip' + s], J.p['knee' + s], J.p['ankle' + s]
        d = unit(K - H)
        lat = unit(Z * sg - np.dot(Z * sg, d) * d)
        side = lat if outside else -lat
        c = K - d * p_up + side * (thigh_r(THIGH - 5.0) + 0.4 + p_t)
        # the footrest lies flush under the sole (as the foot is drawn from the front), along the foot
        n = J.v['foot_n' + s]
        t = J.p['toe' + s] - J.p['heel' + s]
        t = unit(t - np.dot(t, n) * n)
        w = unit(np.cross(t, n))
        rest = A + t * 3.0 - n * (SOLE - 0.5 + 1.4)
        rods = [(c - Y * 8.0 + side * 0.5, rest + side * 7.0), (rest + side * 7.0, rest)]
        arm = [eq.box3(cam, rest, t, n, w, 11.0, 1.4, 6.5, 1.4)] + [rod(cam, a, b, 1.3) for a, b in rods]
        arm_cols = [('box', rest, [t, n, w], [11.0, 1.4, 6.5])] + [('capsule', a, b, 1.3) for a, b in rods]
        r = min(2.8, p_t)
        # 3D: the 2D box is sheared (along the thigh, upright, out to the side). The real pad is
        # square: along the thigh, out to the side, and up square to both, which differs from
        # upright only along the line of sight, so from the front its outline is the same; where it
        # passes behind the knee, depth cuts the leg out of it as the Subtract does in 2D
        up = unit(np.cross(lat, d))
        up = up if up[1] > 0 else -up
        p_up3 = (12.0 - r) / up[1] + r
        # 3D: the rod leaves the pad from inside its lower end (the 2D one starts on its face, which
        # in depth lies just off the thin inside pads), a hair off the 2D line inside the outline
        arm_spec = (eq.box3d(rest, t, n, w, 11.0, 1.4, 6.5, 1.4, 'metal')
                    + eq.rod3d(c - up * (p_up3 - 2.5), rods[0][1], 1.3, 'metal') + eq.rod3d(*rods[1], 1.3, 'metal'))
        items.append(Item(Union(arm), 'metal', ('before', 'leg' + s), collider=arm_cols, spec3d=arm_spec))
        pad = eq.box3(cam, c, d, Y, lat, p_len, 12.0, p_t, r)
        if outside:
            leg = [layer.shape for layer in v.layers if layer.name in ('leg' + s, 'shin' + s)]
            if leg:
                pad = Subtract(pad, Offset(Union(leg), GAP + 0.15))
        items.append(Item(pad, 'pad', ('after', 'arm' + s), gap=True, collider=ortho_box(c, d, Y, (p_len, 12.0, p_t)),
                          spec3d=eq.box3d(c, d, up, lat, p_len, p_up3, p_t, r, 'pad', True)))
        hc = v3(HM_HAND[0], HM_HAND[1], sg * HM_HAND[2])
        # 3D: the grip ends inside the fist towards the camera (it is seen end-on), and a bracket
        # runs from under its rear end in to the seat's edge
        items.append(Item(handle(cam, hc, 2.0, 6.0), 'metal', ('before', 'arm' + s),
                          collider=('cylinder', hc, X, 2.0, 6.0), grip=True,
                          spec3d=(eq.cyl3d(hc - X * 0.9, X, 2.0, 5.1, 'metal')
                                  + eq.rod3d(v3(hc[0] - 4.4, HM_SEAT + 1.4, sg * HM_HAND[2]),
                                             v3(hc[0] - 4.4, HM_SEAT + 1.4, sg * 21.5), 1.6, 'metal'))))
    return items


def hip_machine_exercise(key, muscles, abd0, abd1, outside):
    @exercise(key, 'legs', 'front', muscles=muscles)
    def build():
        def pose(u):
            return hip_machine_pose(lerp(abd0, abd1, u))

        def equip(J, v, u):
            return hip_machine(v, J, outside)

        return pose, rep(1.2, 1.5, top=0.4, bottom=0.35), equip
    return build


hip_machine_exercise('abductorMachine', ['abductors'], 3.0, 22.0, outside=True)
hip_machine_exercise('adductorMachine', ['adductors'], 32.0, 5.0, outside=False)


# ---- cable kickbacks --------------------------------------------------------------------------

@exercise('cableKickbacks', 'legs', 'side', muscles=['glutes'])
def cable_kickbacks():
    tower_x = 80.0
    pulley = v3(tower_x - 5.0, 12.0, 0.0)
    P = v3(0.0, HIP_H - 0.6, 0.0)
    hand = v3(tower_x - 6.5, 112.0)

    def pose(u):
        p = {'pelvis': P.copy(), 'pitch': 22.0, 'neck': -6.0}
        p['legL'] = {'foot': v3(-1.0, ANKLE_H, -10.0), 'toe_out': 5.0, 'pole': v3(1.0, 0.0, -0.2)}
        # the working foot hovers: knee soft through the bottom of the arc, toes pulled up
        p['legR'] = {'hip': lerp(18.0, -28.0, u), 'abd': 3.0,
                     'knee': lerp(26.0, 8.0, u) + 11.0 * math.sin(math.pi * u),
                     'ankle': lerp(-20.0, 10.0, smooth(0.45, 1.0, u))}
        for s, sg in (('L', -1), ('R', 1)):
            p['arm' + s] = {'hand': v3(hand[0], hand[1], sg * 14.0), 'pole': v3(-0.2, -1.0, 0.4 * sg)}
        return p

    def equip(J, v, u):
        cam = v.cam
        K, A = J.p['kneeR'], J.p['ankleR']
        d = unit(A - K)
        fr = J.v['shank_frontR']
        cuff_c = A - d * 3.2
        # the cable runs from the pulley (midline) out to the working ankle: in front of the
        # standing leg, behind the working one
        clip = cuff_c + fr * 5.6
        items = eq.cable_stack(v, pulley, clip, z=('after', 'legL'), tower_x=tower_x)
        cuff = Cone(cam.p(cuff_c + fr * 5.2), cam.p(cuff_c - fr * 5.2), 1.9)
        # 3D: the cuff is a strap round the ankle (from the side, the band across it) with the
        # cable's ring at its front
        items.append(Item(Union([cuff, Circle(cam.p(clip), 1.9)]), 'metal', ('after', 'legR'),
                          spec3d=strap3d(cuff_c, fr, np.cross(d, fr), 5.2, 1.9) + eq.ball3d(clip, 1.9, 'metal')))
        for s, sg in (('L', -1.0), ('R', 1.0)):
            c = v3(hand[0], hand[1], sg * 14.0)
            # 3D: an arm out of the tower to each grip (from the side, behind the near fist)
            items.append(Item(handle(cam, c, 2.0, 5.0, axis=Y), 'metal', ('before', 'arm' + s),
                              collider=('cylinder', c, Y, 2.0, 5.0), grip=True,
                              spec3d=(eq.cyl3d(c, Y, 2.0, 5.0, 'metal')
                                      + eq.rod3d(v3(tower_x, hand[1], 0.0), c, 1.6, 'frame'))))
        return items

    return pose, rep(1.0, 1.4, top=0.35, bottom=0.35), equip


# ---- sled push --------------------------------------------------------------------------------

class SledStride:
    """Short, driving steps on the balls of the feet, in place (the ground runs back)."""

    def __init__(self, front=-4.0, back=-45.0, duty=0.56, lift=24.0):
        self.front, self.back, self.duty, self.lift = front, back, duty, lift

    def foot(self, ph):
        if ph < self.duty:                      # stance: ball planted, heel rising, ground runs back
            t = ph / self.duty
            bx = lerp(self.front, self.back, t)
            fp = lerp(-12.0, -40.0, smooth(0.0, 1.0, t))
            A = ball_pivot(v3(bx, R_TOE), fp)
            return A, fp
        t = (ph - self.duty) / (1.0 - self.duty)  # swing: knee drives through, foot re-plants ahead
        A0 = ball_pivot(v3(self.back, R_TOE), -40.0)
        A1 = ball_pivot(v3(self.front, R_TOE), -12.0)
        e = 0.5 - 0.5 * math.cos(math.pi * t)
        x = lerp(A0[0], A1[0], e)
        y = lerp(A0[1], A1[1], e) + self.lift * math.sin(math.pi * t) ** 1.3
        fp = lerp(-40.0, -12.0, smooth(0.0, 0.8, t)) + 18.0 * math.sin(math.pi * t)
        return v3(x, y), fp


@exercise('sledPush', 'legs', 'side', muscles=['quads', 'glutes', 'calves'])
def sled_push():
    stride = SledStride()
    period, cycles = 1.4, 3
    lean = 48.0
    hand = v3(94.0, 100.0)

    def pose(ph):
        p = {'pelvis': v3(0.0, 80.0 - 1.2 * (0.5 + 0.5 * math.cos(4 * math.pi * ph)), 0.0), 'pitch': lean,
             'neck': 18.0}
        for s, off, sg in (('R', 0.0, 1), ('L', 0.5, -1)):
            A, fp = stride.foot((ph + off) % 1.0)
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 10.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, 0.15 * sg)}
        for s, sg in (('L', -1), ('R', 1)):
            p['arm' + s] = {'hand': v3(hand[0], hand[1], sg * 21.0), 'pole': v3(-0.3, -1.0, 0.5 * sg)}
        return p

    def equip(J, v, u):
        cam = v.cam
        skid = eq.box3(cam, v3(126.0, 5.0, 0.0), X, Y, Z, 36.0, 5.0, 28.0, 2.5)
        horn = rod(cam, v3(130.0, 9.0, 0.0), v3(130.0, 36.0, 0.0), 2.0)
        plates = [eq.cyl(cam, v3(130.0, 12.6 + 5.4 * k, 0.0), Y, 22.5, 2.5) for k in range(3)]
        items = [Item(Union([skid]), 'frame', 'back',
                      spec3d=eq.box3d(v3(126.0, 5.0, 0.0), X, Y, Z, 36.0, 5.0, 28.0, 2.5, 'frame')),
                 Item(horn, 'metal', 'back', spec3d=eq.rod3d(v3(130.0, 9.0, 0.0), v3(130.0, 36.0, 0.0), 2.0, 'metal')),
                 Item(Union(plates), 'plate_rim', 'back',
                      spec3d=[e for k in range(3) for e in eq.plate3d(v3(130.0, 12.6 + 5.4 * k, 0.0), Y, 22.5, 2.5,
                                                                         False)])]
        # an upright (with its brace to the skid) in each hand: each sits just behind its fist
        for s, sg in (('L', -1.0), ('R', 1.0)):
            a, b = v3(hand[0] + 1.0, 8.0, sg * 21.0), v3(hand[0] + 1.0, hand[1] + 12.0, sg * 21.0)
            post = rod(cam, a, b, 2.3)
            ba, bb = v3(hand[0] + 1.0, 60.0, sg * 21.0), v3(118.0, 9.0, sg * 21.0)
            brace = rod(cam, ba, bb, 2.0)
            items.append(Item(Union([post, brace]), 'metal', ('before', 'arm' + s),
                              collider=('capsule', a, b, 2.3), grip=True,
                              spec3d=eq.rod3d(a, b, 2.3, 'metal') + eq.rod3d(ba, bb, 2.0, 'metal')))
        return items

    return pose, Cycle(period, cycles), equip


# ---- tire flip --------------------------------------------------------------------------------

class Tire:
    """A big tire lying flat, flipped end over end away from the lifter. Seen from the side it is a
    rounded slab that tips about its far edge, stands on it, and falls over onto its other face.
    `world(local, th)`: local points (x in [-D, 0] from the far edge, y in [0, H] up) at flip
    angle th (0 flat, 90 upright on its far edge, 180 flat again, one flip further on)."""

    def __init__(self, D=105.0, H=30.0):
        self.D, self.H = D, H

    @staticmethod
    def _rot(p, deg):                       # clockwise by deg (the near edge rises)
        a = math.radians(deg)
        return v3(p[0] * math.cos(a) + p[1] * math.sin(a), -p[0] * math.sin(a) + p[1] * math.cos(a))

    def world(self, local, th):
        D, H = self.D, self.H
        up = self._rot(local, min(th, 90.0)) + v3(D, 0.0)
        if th <= 90.0:
            return up
        pivot = v3(D + H, 0.0)
        return pivot + self._rot(up - pivot, th - 90.0)

    def shape(self, cam, th, dx):
        """The tread seen edge-on: a rounded slab with a lighter rim and cross grooves. In 3D the
        tire is a disc D across and H thick (the collider); the hands hold and push it."""
        D, H = self.D, self.H
        off = v3(dx, 0.0)
        c = self.world(v3(-D / 2, H / 2), th) + off
        axis = unit(self.world(v3(-D / 2, H / 2 + 1.0), th) - self.world(v3(-D / 2, H / 2), th))
        ang = -math.radians(th)
        outer = RBox(cam.p(c), D / 2, H / 2, 10.0, ang)
        inner = RBox(cam.p(c), D / 2 - 3.0, H / 2 - 3.0, 7.5, ang)
        n = 7
        grooves = [RBox(cam.p(self.world(v3(-D / 2 + (i - (n - 1) / 2) * (D - 26.0) / (n - 1), H / 2), th) + off),
                        1.1, H / 2 - 7.0, 1.1, ang) for i in range(n)]
        return [Item(outer, 'plate_rim', 'back', collider=('cylinder', c, axis, D / 2, H / 2), grip=True,
                     spec3d=self.form3d(th, dx)),
                Item(inner, 'plate', 'back', spec3d=[]), Item(Union(grooves), 'plate_rim', 'back', spec3d=[])]

    def form3d(self, th, dx):
        """The tire in 3D, on the same transform: a disc D across and H thick in the light tone
        (sidewalls and shoulders), the tread band between the shoulders and the sidewall faces inside
        a light rim in the dark tone, the bead hole, and cross grooves on the tread. The side view
        sees it edge-on whatever the flip angle (it turns about the line of sight), so its grooves sit
        where the 2D draws them, on the near tread and mirrored on the far one, plus one at each end."""
        D, H = self.D, self.H
        off = v3(dx, 0.0)
        o = self.world(v3(-D / 2, H / 2), th)
        c = o + off
        a = unit(self.world(v3(-D / 2, H / 2 + 1.0), th) - o)        # the axis, across the thickness
        e = unit(self.world(v3(-D / 2 + 1.0, H / 2), th) - o)        # across the tire, in the picture
        R = D / 2
        spec = (eq.cyl3d(c, a, R, H / 2, 'plate_rim') + eq.cyl3d(c, a, R + 0.1, H / 2 - 3.0, 'plate')
                + eq.cyl3d(c, a, R - 3.0, H / 2 + 0.06, 'plate') + eq.cyl3d(c, a, 22.0, H / 2 + 0.12, 'floor'))
        n, g, rg = 7, H / 2 - 7.0 - 1.1, R - 0.4
        for x in [(i - (n - 1) / 2) * (D - 26.0) / (n - 1) for i in range(n)]:
            for sz in (1.0, -1.0):
                p = c + e * x + Z * sz * math.sqrt(rg * rg - x * x)
                spec += eq.rod3d(p - a * g, p + a * g, 1.1, 'plate_rim')
        for se in (1.0, -1.0):
            spec += eq.rod3d(c + e * se * rg - a * g, c + e * se * rg + a * g, 1.1, 'plate_rim')
        return spec


TF_T = 7.6                  # one flip per loop (seconds)
TF_KNEE_OUT = 0.1           # knees track over the feet, so the arms reaching down pass outside them
TF_GRIP_Z = 25.0            # hands under the lip, just outside the knees


@exercise('tireFlips', 'legs', 'side', muscles=['quads', 'glutes'])
def tire_flips():
    tire = Tire()
    S = tire.D + tire.H                     # the tire (and the lifter) move this far per flip
    F0 = -42.0                              # standing ankles, world x, at the start
    lip = v3(-tire.D - 2.0, 7.0)            # fingers under the near edge
    face = lambda a: v3(-a, -1.0)           # pushing on the face that turns towards the lifter

    th_keys = [(0.0, 0.0), (0.18, 0.0), (0.33, 35.0), (0.43, 58.0), (0.53, 80.0), (0.6, 92.0)]

    def theta(u):
        if u <= 0.6:
            return curve(u, th_keys)
        t = min((u - 0.6) / 0.12, 1.0)      # falls over under its own weight
        return 92.0 + 88.0 * t * t

    # follow camera: advances only while the lifter steps, one flip's length per loop
    cam_keys = [(0.0, 0.0), (0.33, 0.0), (0.44, 24.0), (0.55, 75.0), (0.74, 75.0), (0.97, S), (1.0, S)]

    pel_keys = [(0.0, v3(F0 + 0.5, HIP_H - 0.6, 0.0)), (0.04, v3(F0 + 0.5, HIP_H - 0.6, 0.0)),
                (0.15, v3(-57.0, 46.0, 68.0)), (0.18, v3(-56.0, 47.0, 67.0)), (0.33, v3(-24.0, 80.0, 36.0)),
                (0.43, v3(5.0, 86.0, 30.0)), (0.53, v3(30.0, 89.0, 28.0)), (0.6, v3(42.0, 90.0, 30.0)),
                (0.66, v3(40.0, 91.0, 12.0)), (0.745, v3(36.0, 91.5, 2.0)), (0.8, v3(52.0, 92.0, 3.0)),
                (0.855, v3(72.0, 91.5, 3.0)), (0.91, v3(85.0, 93.0, 2.0)),
                (0.965, v3(F0 + S + 0.5, HIP_H - 0.6, 0.0)), (1.0, v3(F0 + S + 0.5, HIP_H - 0.6, 0.0))]

    def step(u, u_off, u0, u1, x0, x1, lift=12.0):
        """Ankle x, y and foot pitch of a foot that peels its heel (u_off..u0), then steps from x0
        to x1 (u0..u1) and lands heel first."""
        if u <= u_off:
            return x0, ANKLE_H, 0.0
        if u < u0:
            fp = -30.0 * smooth(u_off, u0, u)
            A = ball_pivot(flat_ball(x0), fp)
            return A[0], A[1], fp
        if u >= u1:
            return x1, ANKLE_H, 0.0
        t = (u - u0) / (u1 - u0)
        e = t * t * (3 - 2 * t)
        A0 = ball_pivot(flat_ball(x0), -30.0)
        fp = lerp(-30.0, 0.0, smooth(0.0, 0.6, t)) + 12.0 * smooth(0.5, 0.85, t) * (1 - smooth(0.85, 1.0, t))
        return lerp(A0[0], x1, e), lerp(A0[1], ANKLE_H, e) + lift * math.sin(math.pi * t), fp

    def feet(u):
        if u < 0.74:
            return (step(u, 0.3, 0.345, 0.43, F0, 22.0, 14.0), step(u, 0.4, 0.44, 0.53, F0, 48.0, 14.0))
        return (step(u, 0.745, 0.765, 0.855, 22.0, F0 + S, 11.0), step(u, 0.84, 0.865, 0.965, 48.0, F0 + S, 11.0))

    def hands(u, th, hang):
        grip = tire.world(lip, th)
        push = tire.world(face(tire.D - 17.0), min(th, 92.0))
        if u < 0.15:
            return lerp(hang, grip, smooth(0.04, 0.15, u))
        if u < 0.47:
            return grip
        if u < 0.53:
            return lerp(grip, push, smooth(0.47, 0.53, u))
        return lerp(push, hang, smooth(0.6, 0.7, u))

    def pose(u):
        u = u % 1.0
        th = theta(u)
        c = curve(u, cam_keys)
        K = curve(u, pel_keys)
        p = {'pelvis': v3(K[0] - c, K[1], 0.0), 'pitch': K[2], 'neck': 0.35 * K[2] * -0.5}
        (rx, ry, rfp), (lx, ly, lfp) = feet(u)
        # trailing foot rolls onto its ball before it leaves the floor
        for s, (x, y, fp), sg in (('R', (rx, ry, rfp), 1.0), ('L', (lx, ly, lfp), -1.0)):
            p['leg' + s] = {'foot': v3(x - c, y, sg * 11.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, TF_KNEE_OUT * sg)}
        sh = torso_point(p['pelvis'], p['pitch'], 0.0, TORSO)
        hang = v3(sh[0] + 2.0 + c, sh[1] - ARM + 1.5)          # world, like the tire
        target = hands(u, th, hang) - v3(c, 0.0)
        reach = target - v3(sh[0], sh[1])
        if np.linalg.norm(reach) > ARM - 1.5:        # reaching for the tire before it is in range
            target = v3(sh[0], sh[1]) + reach * (ARM - 1.5) / np.linalg.norm(reach)
        lifting = smooth(0.02, 0.12, u) * (1.0 - smooth(0.45, 0.53, u))    # elbows out while lifting
        for s, sg in (('L', -1.0), ('R', 1.0)):
            p['arm' + s] = {'hand': v3(target[0], target[1], sg * TF_GRIP_Z),
                            'pole': v3(-0.6 * lifting, -1.0 + 0.6 * lifting, (0.5 + 0.5 * lifting) * sg)}
        return p

    def equip(J, v, u):
        u = u % 1.0
        return tire.shape(v.cam, theta(u), -curve(u, cam_keys))

    return pose, Cycle(TF_T, 1), equip

