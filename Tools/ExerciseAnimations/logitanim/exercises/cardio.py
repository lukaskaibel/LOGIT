"""Cardio and loaded carries: gaits in place (treadmill style), machines, floor work, carries.

Side view unless noted (the figure faces screen-right, the near side has the larger z).
Machines are drawn minimal here from sdf primitives in the equipment palette only.
"""
from .common import *
from ..spec import HEEL, TOE, R_HEEL, R_TOE, R_HAND
from ..sdf import V, Circle, Cone, RBox, Union, Subtract, Poly, Ellipse, Intersect

LEG = THIGH + SHANK


# ---- small helpers -------------------------------------------------------------------------

def smin(a, b, k=4.0):
    """Smooth minimum (never above min(a, b))."""
    h = max(k - abs(a - b), 0.0) / k
    return min(a, b) - h * h * k * 0.25


def keyed(t, pts):
    """Smoothstep interpolation through (t, value) keys, t ascending."""
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, a), (t1, b) in zip(pts, pts[1:]):
        if t <= t1:
            return lerp(a, b, smooth(t0, t1, t))
    return pts[-1][1]


class Spline:
    """Cubic Hermite through points at times ts (0 .. 1) with given end velocities (d/dt)."""

    def __init__(self, ts, ps, v0, v1):
        self.ts = list(ts)
        self.ps = [np.asarray(p, float) for p in ps]
        n = len(self.ps)
        ms = [np.asarray(v0, float)]
        for i in range(1, n - 1):
            ms.append((self.ps[i + 1] - self.ps[i - 1]) / (self.ts[i + 1] - self.ts[i - 1]))
        ms.append(np.asarray(v1, float))
        self.ms = ms

    def __call__(self, s):
        ts, ps, ms = self.ts, self.ps, self.ms
        for i in range(len(ps) - 1):
            if s <= ts[i + 1] or i == len(ps) - 2:
                h = ts[i + 1] - ts[i]
                u = min(max((s - ts[i]) / h, 0.0), 1.0)
                u2, u3 = u * u, u * u * u
                return ((2 * u3 - 3 * u2 + 1) * ps[i] + (u3 - 2 * u2 + u) * h * ms[i]
                        + (-2 * u3 + 3 * u2) * ps[i + 1] + (u3 - u2) * h * ms[i + 1])


def rot(p, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([c * p[0] - s * p[1], s * p[0] + c * p[1]])


def foot_offsets(fp):
    """Heel and toe circle centres relative to the ankle (x, y) for a foot pitched fp deg."""
    a = math.radians(fp)
    t = np.array([math.cos(a), math.sin(a)])
    n = np.array([-math.sin(a), math.cos(a)])
    return n * HEEL[0] + t * HEEL[1], n * TOE[0] + t * TOE[1]


def planted_ankle(xa, fp):
    """Ankle (x, y) of a foot resting on the ground y = 0 with pitch fp: rocking on the heel for
    fp > 0, on the toes for fp < 0, flat at 0. xa = the ankle x of the flat foot."""
    if fp > 0:
        h, _ = foot_offsets(fp)
        return np.array([xa + HEEL[1], R_HEEL]) - h
    if fp < 0:
        _, to = foot_offsets(fp)
        return np.array([xa + TOE[1], R_TOE]) - to
    return np.array([xa, ANKLE_H])


def clear_pitch(ankle_y, fp, margin=0.4):
    """Smallest change of foot pitch that keeps heel and toe `margin` above the ground y = 0
    (ankle at height ankle_y)."""
    def low(p, which):
        h, t = foot_offsets(p)
        return ankle_y + (t[1] - R_TOE if which == 'toe' else h[1] - R_HEEL)
    for which, sgn in (('toe', 1.0), ('heel', -1.0)):
        if low(fp, which) < margin:
            lo, hi = fp, fp + sgn * 90.0
            if low(hi, which) < margin:
                return fp
            for _ in range(30):
                mid = (lo + hi) / 2
                if low(mid, which) < margin:
                    lo = mid
                else:
                    hi = mid
            return hi
    return fp


def swing_margin(s, m=0.4):
    """Clearance kept by a swinging foot: none at lift-off and touch-down (the foot is on the
    floor there), so the guard never tilts the foot against its contact pitch."""
    return m * smooth(0.0, 0.25, s) * (1.0 - smooth(0.75, 1.0, s))


def shank_pitch(hip, ankle, pole):
    """Foot pitch (deg) of a neutral ankle (foot square to the shank) for this leg."""
    knee, a = ik2(hip, ankle, THIGH, SHANK, pole)
    d = unit(a - knee)
    return math.degrees(math.atan2(d[0], -d[1]))


def polyline(pts, r):
    pts = [np.asarray(p, float) for p in pts]
    return Union([Cone(a, b, r) for a, b in zip(pts, pts[1:])])


def ring(c, r, w):
    return Subtract(Circle(c, r), Circle(c, r - w))


# ---- 3D forms (Item.spec3d) ---------------------------------------------------------------------
# The machines here are drawn side-on. In 3D they get their width: both pedals, cranks, handles and
# rails, feet across the floor, wheels and drums on their real axes.

def p3(q, z=0.0):
    """A side-view point (x, y) at depth z."""
    return v3(q[0], q[1], z)


def hoop3d(c3, normal3, radius, tube, color, n=16, gap=False):
    """A ring (a tyre) as n capsules round its centre line, the corners a little outside `radius` and
    the chords' middles as far inside, so it reads as round as the 2D ring it replaces."""
    return eq.ring3d(c3, normal3, radius * 2.0 / (1.0 + math.cos(math.pi / n)), tube, color, gap, n)


def drum3d(c3, axis3, r, half, rim, face, rim_w, hub_r=None, hub=None, hub_half=None, gap=False):
    """A fan, flywheel or chainring as the 2D draws it side-on (a rim round a darker face, a hub):
    the rim's cylinder, the face a hair proud of it on both sides, the hub prouder still."""
    out = eq.cyl3d(c3, axis3, r, half, rim, gap) + eq.cyl3d(c3, axis3, r - rim_w, half + 0.06, face)
    if hub_r is not None:
        out += eq.cyl3d(c3, axis3, hub_r, half + 0.12 if hub_half is None else hub_half, hub)
    return out


# ---- gait ------------------------------------------------------------------------------------

class Tread:
    """Walking or running in place on a moving belt. ph in [0, 1) is the right leg's cycle,
    0 = right foot contact; the left leg runs half a cycle behind.

    Stance: the foot rolls heel -> flat -> toes (pitch keys `roll` over stance progress) while its
    contact moves back at belt speed, so it neither slides nor sinks. Swing: a Hermite path through
    `via` points (s, x from x0, height) with the end velocities of the stance, so the foot leaves
    and meets the belt smoothly. The pelvis never rises above what the legs can reach.
    A `slope` (deg) tilts the belt (incline treadmill) about (0, deck_y); the body stays upright.
    """

    def __init__(self, travel=64.0, duty=0.62, x0=0.0, hip_x=2.0, half=9.0, height=HIP_H - 0.6,
                 bob=0.0, lean=2.0, neck=0.0, reach=0.9985,
                 roll=((0.0, 13.0), (0.16, 0.0), (0.52, 0.0), (1.0, -32.0)),
                 via=((0.48, 0.0, 12.5),), relax=-8.0, prep=0.3,
                 arm_mean=0.0, arm_amp=20.0, abd=6.0, elbow=16.0, elbow_amp=6.0,
                 slope=0.0, deck_y=0.0):
        self.travel, self.duty, self.x0, self.hip_x, self.half = travel, duty, x0, hip_x, half
        self.height, self.bob, self.lean, self.neck = height, bob, lean, neck
        self.Lmax = LEG * reach
        self.roll, self.relax, self.prep = roll, relax, prep
        self.arm_mean, self.arm_amp, self.abd = arm_mean, arm_amp, abd
        self.elbow, self.elbow_amp = elbow, elbow_amp
        self.slope, self.deck_y = slope, deck_y
        d = duty
        eps = 1e-4
        a_hs, a_to = self._stance(0.0), self._stance(1.0)
        v_hs = (self._stance(eps) - a_hs) / eps * (1 - d) / d
        v_to = (a_to - self._stance(1.0 - eps)) / eps * (1 - d) / d
        ts = [0.0] + [p[0] for p in via] + [1.0]
        ps = [a_to] + [np.array([x0 + p[1], p[2]]) for p in via] + [a_hs]
        self.swing = Spline(ts, ps, v_to, v_hs)

    # local frame: x along the belt, y up from the belt surface
    def _stance(self, t):
        fp = keyed(t, self.roll)
        return planted_ankle(self.x0 + self.travel * (0.5 - t), fp)

    def world(self, p):
        q = rot(p, self.slope)
        return np.array([q[0], q[1] + self.deck_y])

    def foot(self, p):
        """(ankle world (x, y), local pitch or None, stance?, swing progress)."""
        d = self.duty
        if p < d:
            t = p / d
            return self.world(self._stance(t)), keyed(t, self.roll), True, 0.0
        s = (p - d) / (1 - d)
        return self.world(self.swing(s)), None, False, s

    def clear(self, a, fpw, margin=0.4):
        """Tilt a swinging foot (toes up, or heel up) just enough to keep it off the belt."""
        la = rot(np.array([a[0], a[1] - self.deck_y]), -self.slope)
        return clear_pitch(la[1], fpw - self.slope, margin) + self.slope

    def pelvis(self, ph, ankles):
        x = self.x0 + self.hip_x
        y = self.height - self.bob * math.cos(4 * math.pi * (ph - self.duty / 2))
        for a, sg in ankles.values():
            dz = sg * self.half - sg * HIP_HALF
            r = self.Lmax ** 2 - (a[0] - x) ** 2 - dz * dz
            y = smin(y, a[1] + math.sqrt(max(r, 0.0)), 3.0)
        return x, y

    def pose(self, ph, arms=True, **extra):
        ph = ph % 1.0
        phases = {'R': ph, 'L': (ph + 0.5) % 1.0}
        sgn = {'R': 1.0, 'L': -1.0}
        feet_ = {s: self.foot(phases[s]) for s in 'LR'}
        px, py = self.pelvis(ph, {s: (feet_[s][0], sgn[s]) for s in 'LR'})
        pose = {'pelvis': v3(px, py, 0.0), 'pitch': self.lean, 'neck': self.neck}
        fp_hs = self.roll[0][1] + self.slope
        fp_to = self.roll[-1][1] + self.slope
        for s in 'LR':
            a, fp, st, sw = feet_[s]
            sg = sgn[s]
            pole = v3(1.0, 0.0, 0.15 * sg)
            foot3 = v3(a[0], a[1], sg * self.half)
            if st:
                fpw = fp + self.slope
            else:
                hip = v3(px, py, sg * HIP_HALF)
                rel = self.relax if not isinstance(self.relax, (tuple, list)) else keyed(sw, self.relax)
                nat = shank_pitch(hip, foot3, pole) + rel
                fpw = lerp(fp_to, nat, smooth(0.0, 0.35, sw))
                fpw = lerp(fpw, fp_hs, smooth(1.0 - self.prep, 1.0, sw))
                fpw = self.clear(a, fpw, swing_margin(sw))
            pose['leg' + s] = {'foot': foot3, 'foot_pitch': fpw, 'pole': pole}
        if arms:
            for s, p in (('R', phases['L']), ('L', phases['R'])):
                c = math.cos(2 * math.pi * p)
                pose['arm' + s] = {'flex': self.arm_mean + self.arm_amp * c, 'abd': self.abd,
                                   'elbow': self.elbow + self.elbow_amp * c}
        pose.update(extra)
        return pose


def gait_muscles(*extra):
    return ['quads', 'glutes', 'calves'] + list(extra)


WALK = dict(travel=64.0, duty=0.62, hip_x=2.0, lean=2.0, height=HIP_H - 0.2, arm_amp=19.0, elbow=16.0,
            elbow_amp=6.0, relax=((0.0, -6.0), (0.4, 18.0), (0.78, 8.0), (1.0, 2.0)),
            roll=((0.0, 16.0), (0.16, 0.0), (0.52, 0.0), (1.0, -32.0)))

JOG = dict(travel=64.0, duty=0.4, hip_x=4.0, reach=0.99, height=HIP_H - 3.2, bob=2.6, lean=6.0, neck=3.0,
           roll=((0.0, 5.0), (0.18, 0.0), (0.42, 0.0), (1.0, -38.0)),
           via=((0.3, -30.0, 34.0), (0.66, 22.0, 30.0)), relax=-16.0, prep=0.25,
           arm_mean=6.0, arm_amp=30.0, abd=8.0, elbow=84.0, elbow_amp=10.0)

SPRINT = dict(travel=74.0, duty=0.3, x0=-16.0, hip_x=16.0, reach=0.99, height=HIP_H - 3.0, bob=2.4, lean=13.0,
              neck=8.0, roll=((0.0, -6.0), (0.3, -2.0), (0.45, -4.0), (1.0, -44.0)),
              via=((0.28, -36.0, 58.0), (0.64, 40.0, 52.0)), relax=-22.0, prep=0.3,
              arm_mean=10.0, arm_amp=58.0, abd=8.0, elbow=92.0, elbow_amp=18.0)


@exercise('walking', 'cardio', 'side', muscles=gait_muscles())
def walking():
    g = Tread(**WALK)
    return g.pose, Cycle(1.1, 4), None


@exercise('running', 'cardio', 'side', muscles=gait_muscles())
def running():
    g = Tread(**JOG)
    return g.pose, Cycle(0.7, 6), None


@exercise('sprints', 'cardio', 'side', muscles=gait_muscles('hamstrings'))
def sprints():
    g = Tread(**SPRINT)
    return g.pose, Cycle(0.5625, 8), None


# ---- rucking ---------------------------------------------------------------------------------

def backpack(v, J):
    tf = J.torso_frame
    c = J.p['pelvis'] + tf.f * (-19.5) + tf.u * 33.0
    shape = eq.box3(v.cam, c, tf.f, tf.u, tf.r, 8.5, 17.0, 15.0, 4.5)
    # on the back, narrower than the shoulders: behind the torso, the far arm swinging behind it
    return [Item(shape, 'plate_rim', ('before', 'base'),
                 collider=('box', c, [tf.f, tf.u, tf.r], [8.5, 17.0, 15.0]),
                 spec3d=eq.box3d(c, tf.f, tf.u, tf.r, 8.5, 17.0, 15.0, 4.5, 'plate_rim'))]


@exercise('rucking', 'cardio', 'side', muscles=gait_muscles())
def rucking():
    g = Tread(**merge(WALK, lean=5.0, arm_amp=15.0, travel=62.0))

    def equip(J, v, u):
        return backpack(v, J)

    return g.pose, Cycle(1.125, 4), equip


# ---- incline treadmill -----------------------------------------------------------------------

INCLINE = 8.5           # deg (15 %)
DECK_Y = 22.0           # belt surface height at x = 0
TM_LEG_Z = 22.0         # 3D: the deck's legs and floor rails, under its sides
TM_POST_Z = 28.0        # 3D: the uprights and handrails, just outside the belt


def treadmill(v, slope=INCLINE, deck_y=DECK_Y, rear=-80.0, front=76.0):
    """Treadmill in the side view: belt deck on the incline, base rail, front upright, console,
    short handrail."""
    tn = math.tan(math.radians(slope))
    R = V(rear, deck_y + rear * tn)
    F = V(front, deck_y + front * tn)
    d = (F - R) / np.linalg.norm(F - R)
    n = V(-d[1], d[0])
    th = 8.0
    deck = RBox((R + F) / 2 - n * th / 2, np.linalg.norm(F - R) / 2 + 2.0, th / 2, th / 2, math.radians(slope))
    rb = R - n * th + d * 10.0             # under the rear of the deck
    fb = F - n * th - d * 12.0             # under the front
    frame = [Cone(V(rear - 2.0, 2.2), V(front + 10.0, 2.2), 2.2),
             Cone(rb, V(rb[0], 2.2), 2.0),
             Cone(fb, V(fb[0] + 6.0, 2.2), 2.4),
             Cone(V(front + 8.0, 3.0), V(front - 4.0, 142.0), 3.2)]      # upright, leaning to the user
    console = RBox(V(front - 7.0, 146.0), 13.0, 5.0, 4.0, math.radians(-24.0))
    rail = Cone(V(front - 5.0, 132.0), V(front - 40.0, 127.0), 2.1)
    c = (R + F) / 2 - n * th / 2
    belt = ('box', v3(c[0], c[1], 0.0), [v3(d[0], d[1]), v3(n[0], n[1]), Z],
            [np.linalg.norm(F - R) / 2 + 2.0, th / 2, 25.0])
    # 3D: the deck on a leg each side at either end, on a floor rail each side; an upright each side
    # of the deck (a bar across their feet), the console across their tops, a handrail along each
    frame3 = eq.rod3d(v3(front + 8.0, 2.2, -TM_POST_Z), v3(front + 8.0, 2.2, TM_POST_Z), 2.2)
    rail3 = []
    for sg in (-1.0, 1.0):
        frame3 += (eq.rod3d(v3(rear - 2.0, 2.2, sg * TM_LEG_Z), v3(front + 10.0, 2.2, sg * TM_LEG_Z), 2.2)
                   + eq.rod3d(p3(rb, sg * TM_LEG_Z), v3(rb[0], 2.2, sg * TM_LEG_Z), 2.0)
                   + eq.rod3d(p3(fb, sg * TM_LEG_Z), v3(fb[0] + 6.0, 2.2, sg * TM_LEG_Z), 2.4)
                   + eq.rod3d(v3(front + 8.0, 3.0, sg * TM_POST_Z), v3(front - 4.0, 142.0, sg * TM_POST_Z), 3.2))
        rail3 += eq.rod3d(v3(front - 5.0, 132.0, sg * TM_POST_Z), v3(front - 40.0, 127.0, sg * TM_POST_Z), 2.1, 'metal')
    a = math.radians(-24.0)
    console3 = eq.box3d(v3(front - 7.0, 146.0), v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a)), Z,
                        13.0, 5.0, TM_POST_Z + 3.0, 4.0, 'frame')
    # the rails stand at the sides of the belt, ahead of the swinging hands: nothing of the machine
    # comes between the walker and the camera
    return [Item(Union(frame), 'frame', 'back', spec3d=frame3), Item(console, 'frame', 'back', spec3d=console3),
            Item(rail, 'metal', 'back', spec3d=rail3),
            Item(deck, 'pad', 'back', collider=belt, spec3d=eq.box3d(belt[1], *belt[2], *belt[3], th / 2, 'pad'))]


@exercise('inclineTreadmillWalk', 'cardio', 'side', muscles=['glutes', 'calves', 'hamstrings'])
def incline_treadmill_walk():
    g = Tread(**merge(WALK, slope=INCLINE, deck_y=DECK_Y, height=HIP_H + DECK_Y, lean=7.0, neck=4.0,
                      travel=60.0, arm_amp=17.0))

    def equip(J, v, u):
        return treadmill(v)

    return g.pose, Cycle(1.2, 4), equip


# ---- loaded carries: calm walking with the load ----------------------------------------------

CARRY = merge(WALK, travel=52.0, duty=0.64, lean=1.0, arm_amp=0.0)


def hang_arms(pose, sway=2.5, ph=0.0, abd=9.0, elbow=4.0):
    for s, p in (('R', (ph + 0.5) % 1.0), ('L', ph)):
        pose['arm' + s] = {'flex': 1.0 + sway * math.cos(2 * math.pi * p), 'abd': abd, 'elbow': elbow}
    return pose


@exercise('farmersWalk', 'back', 'side', muscles=['traps', 'forearms'])
def farmers_walk():
    g = Tread(**CARRY)

    def pose(u):
        return hang_arms(g.pose(u, arms=False, shrug=0.6), ph=u)

    def equip(J, v, u):
        items = []
        for s in 'LR':
            items += eq.dumbbell(v, J.p['hand' + s], X, ('before', 'arm' + s), head_r=10.2, half=13.0)
        return items

    return pose, Cycle(1.2, 4), equip


def shoulder_c(pose):
    return torso_point(pose['pelvis'], pose.get('pitch', 0.0), pose.get('protract', 0.0),
                       TORSO + pose.get('shrug', 0.0))


@exercise('overheadCarry', 'shoulders', 'side', muscles=['delts', 'traps', 'triceps'])
def overhead_carry():
    # the arms go up beside the head, so the near one passes in front of it
    g = Tread(**merge(CARRY, travel=46.0, lean=0.0, neck=2.0))
    grip = 23.0

    def pose(u):
        p = g.pose(u, arms=False, shrug=3.0)
        sc = shoulder_c(p)
        dz = grip - SHOULDER_HALF
        reach = ARM - 0.1
        dx = -3.0
        hy = sc[1] + math.sqrt(reach ** 2 - dz * dz - dx * dx)
        p.update(both(v3(sc[0] + dx, hy, grip), [-0.3, -0.1, 1.0]))
        return p

    def equip(J, v, u):
        items = []
        for s in 'LR':
            items += eq.dumbbell(v, J.p['hand' + s], X, ('before', 'arm' + s))
        return items

    return pose, Cycle(1.2, 4), equip


YOKE_L = (-7.0, 53.5)       # crossbar on the traps, torso-local (forward, up)
YOKE_Z = 56.0               # the uprights, each side of the carrier
YOKE_BOTTOM = 12.0          # the base runners, lifted off the floor


def yoke(v, J):
    """The yoke in 3D: a crossbar across the traps, an upright down from each end to a base runner
    along the floor, and a plate on a horn outside each upright. Every part is placed by its depth,
    so the bar lies over the back and under the fists that hold it."""
    cam = v.cam
    tf = J.torso_frame
    B = J.p['pelvis'] + tf.f * YOKE_L[0] + tf.u * YOKE_L[1]
    bx, by = B[0], B[1]
    bar = v3(bx, by, 0.0)
    items = [Item(eq.cyl(cam, bar, Z, 3.2, YOKE_Z), 'metal', gap=True, depth=cam.depth(bar),
                  collider=('capsule', bar - Z * YOKE_Z, bar + Z * YOKE_Z, 3.2), grip=True,
                  spec3d=eq.cyl3d(bar, Z, 3.2, YOKE_Z, 'metal', True))]
    for sg in (-1.0, 1.0):
        top, foot = v3(bx, by + 44.0, sg * YOKE_Z), v3(bx, YOKE_BOTTOM, sg * YOKE_Z)
        items.append(Item(Cone(cam.p(top), cam.p(foot), 3.0), 'metal', gap=True, depth=cam.depth((top + foot) / 2),
                          collider=('capsule', top, foot, 3.0), spec3d=eq.rod3d(top, foot, 3.0, 'metal', True)))
        a, b = v3(bx - 32.0, YOKE_BOTTOM, sg * YOKE_Z), v3(bx + 32.0, YOKE_BOTTOM, sg * YOKE_Z)
        items.append(Item(Cone(cam.p(a), cam.p(b), 2.8), 'frame', gap=True, depth=cam.depth((a + b) / 2),
                          collider=('capsule', a, b, 2.8), spec3d=eq.rod3d(a, b, 2.8, 'frame', True)))
        pc = v3(bx - 4.0, YOKE_BOTTOM + 27.0, sg * (YOKE_Z + 8.0))
        horn = v3(pc[0], pc[1], sg * YOKE_Z)
        items.append(Item(Cone(cam.p(horn), cam.p(pc + Z * sg * 4.0), 2.2), 'metal', depth=cam.depth(pc),
                          spec3d=eq.rod3d(horn, pc + Z * sg * 4.0, 2.2, 'metal')))
        items += eq.plate_disc(v, pc, Z, r=22.5, depth=True)
    return items


# Seen from the side, the yoke's near upright and plate would stand in front of the carrier (they
# are wider than the body), covering the torso and the stepping legs; from behind, the frame stands
# round the carrier, the crossbar lies across the traps and the working traps and erectors show.
@exercise('yokeCarry', 'back', 'back', muscles=['traps', 'erectors'])
def yoke_carry():
    g = Tread(**merge(CARRY, travel=42.0, lean=4.0))

    def pose(u):
        p = g.pose(u, arms=False)
        B = torso_point(p['pelvis'], p['pitch'], *YOKE_L)
        p.update(both(v3(B[0], B[1], 36.0), [-1.0, -0.7, 0.35]))
        return p

    def equip(J, v, u):
        return yoke(v, J)

    return pose, Cycle(1.1, 4), equip


BAG_L = (27.0, 26.0)        # sandbag centre, torso-local (forward, up)
BAG3 = (28.3, 14.7)         # 3D: the bag's centre forward and its half depth: from the chest (13.6) to 43


@exercise('sandbagCarry', 'back', 'side', muscles=['erectors', 'traps', 'biceps'])
def sandbag_carry():
    g = Tread(**merge(CARRY, travel=46.0, lean=-4.0))

    def pose(u):
        p = g.pose(u, arms=False)
        C = torso_point(p['pelvis'], p['pitch'], *BAG_L)
        th = math.radians(p['pitch'])
        f = v3(math.cos(th), -math.sin(th))
        up = v3(math.sin(th), math.cos(th))
        h = C + f * 8.0 - up * 13.0
        p.update(both(v3(h[0], h[1], 12.0), [-0.1, -1.0, 1.0]))
        return p

    def equip(J, v, u):
        tf = J.torso_frame
        C = J.p['pelvis'] + tf.f * BAG_L[0] + tf.u * BAG_L[1]
        f2 = v.cam.d(tf.f)
        ang = math.atan2(f2[1], f2[0])
        # hugged to the chest, about as wide as it is deep: in front of the torso, the arms round
        # its sides (the near one in front of it, the far one behind)
        # 3D: a soft block (a box rounded deep into its corners), its front where the drawing's is,
        # its back flat against the chest rather than through it
        B = J.p['pelvis'] + tf.f * BAG3[0] + tf.u * BAG_L[1]
        return [Item(Ellipse(v.cam.p(C), 16.0, 20.0, ang), 'plate_rim', ('after', 'base'), gap=True,
                     collider=('capsule', C - tf.u * 4.0, C + tf.u * 4.0, 16.0), grip=True,
                     spec3d=eq.box3d(B, tf.f, tf.u, tf.r, BAG3[1], 20.0, 16.0, 13.0, 'plate_rim', True))]

    return pose, Cycle(1.2, 4), equip


# ---- rowing machine --------------------------------------------------------------------------
# Seat on a monorail, feet in an inclined stretcher, fan housing in front. Drive: legs, body,
# arms; recovery: arms, body, legs (the recovery takes about twice as long as the drive).

ROW_SEAT = 36.0                     # seat top
ROW_PY = ROW_SEAT + 9.0             # hip joint height
ROW_ANK = (60.0, 24.0)              # ankles in the stretcher
ROW_FP = 38.0                       # foot pitch on the stretcher
ROW_EXIT = np.array([103.0, 60.0, 0.0])   # where the chain leaves the fan housing
ROW_FAN = V(126.0, 52.0)
ROW_GRIP = 21.0
ROW_X = (20.0, -24.5)               # pelvis x at the catch and at the finish


def row_phase(u):
    seat = smooth(0.0, 0.25, u) - smooth(0.6, 0.98, u)
    body = smooth(0.1, 0.3, u) - smooth(0.46, 0.66, u)
    arms = smooth(0.2, 0.38, u) - smooth(0.42, 0.54, u)
    return seat, body, arms


def rower_pose(u):
    seat, body, arms = row_phase(u)
    P = v3(lerp(ROW_X[0], ROW_X[1], seat), ROW_PY, 0.0)
    pitch = lerp(30.0, -22.0, body)
    S = torso_point(P, pitch, 0.0, TORSO)
    d = unit(ROW_EXIT - S)
    reach = math.sqrt((ARM - 0.3) ** 2 - (ROW_GRIP - SHOULDER_HALF) ** 2)
    H = lerp(S + d * reach, torso_point(P, pitch, 19.0, 31.0), arms)
    pose = {'pelvis': P, 'pitch': pitch, 'neck': 0.4 * pitch}
    for s, sg in (('L', -1), ('R', 1)):
        pose['leg' + s] = {'foot': v3(ROW_ANK[0], ROW_ANK[1], sg * 10.0), 'foot_pitch': ROW_FP,
                           'pole': v3(0.25, 1.0, 0.2 * sg)}
    pose.update(both(v3(H[0], H[1], ROW_GRIP), [-1.0, -0.4, 0.6]))
    return pose


def rower(v, J):
    H = (J.p['handL'] + J.p['handR']) / 2
    px = J.p['pelvis'][0]
    frame = [RBox(V(24.0, 27.0), 80.0, 3.0, 3.0),                                    # monorail
             Cone(V(-50.0, 26.0), V(-50.0, 2.4), 2.4), Cone(V(-61.0, 2.2), V(-39.0, 2.2), 2.2),
             Cone(V(116.0, 40.0), V(122.0, 2.4), 3.0), Cone(V(106.0, 2.2), V(138.0, 2.2), 2.2),
             Cone(V(66.0, 18.0), V(74.0, 27.0), 2.4)]                                 # stretcher mount
    a = math.radians(ROW_FP)
    t, n = V(math.cos(a), math.sin(a)), V(-math.sin(a), math.cos(a))
    sole = V(*ROW_ANK) - n * 7.8 + t * 4.5
    plate = RBox(sole - n * 1.9, 15.5, 1.9, 1.9, a)
    seat = RBox(V(px - 3.0, ROW_SEAT - 2.6), 15.0, 2.6, 2.6)
    pc = sole - n * 1.9
    t3, n3 = v3(t[0], t[1]), v3(n[0], n[1])
    H0 = v3(H[0], H[1], 0.0)
    # 3D: the monorail on a leg at each end, each leg on a foot along the rail and one across it; the
    # fan a drum on its axle; one foot plate across both feet; the seat on the rail; the handle
    # across the fists (its ends inside them) with the chain from its middle
    frame3 = (eq.box3d(v3(24.0, 27.0), X, Y, Z, 80.0, 3.0, 4.0, 3.0, 'frame')
              + eq.rod3d(v3(-50.0, 26.0), v3(-50.0, 2.4), 2.4) + eq.rod3d(v3(-61.0, 2.2), v3(-39.0, 2.2), 2.2)
              + eq.rod3d(v3(-50.0, 2.2, -22.0), v3(-50.0, 2.2, 22.0), 2.2)
              + eq.rod3d(v3(116.0, 40.0), v3(122.0, 2.4), 3.0) + eq.rod3d(v3(106.0, 2.2), v3(138.0, 2.2), 2.2)
              + eq.rod3d(v3(122.0, 2.2, -24.0), v3(122.0, 2.2, 24.0), 2.2)
              + eq.rod3d(v3(66.0, 18.0), v3(74.0, 27.0), 2.4))
    # the monorail, seat, fan and the chain run down the middle, the feet strap in each side of it;
    # the chain leaves the middle of the handle (drawn in the fists) between the knees
    return [Item(Union(frame), 'frame', 'back', collider=('box', v3(24.0, 27.0, 0.0), [X, Y, Z], [80.0, 3.0, 4.0]),
                 spec3d=frame3),
            Item(Circle(ROW_FAN, 25.0), 'pad', 'back',
                 collider=('cylinder', v3(ROW_FAN[0], ROW_FAN[1], 0.0), Z, 25.0, 15.0),
                 spec3d=drum3d(p3(ROW_FAN), Z, 25.0, 15.0, 'frame', 'pad', 3.0, hub_r=6.0, hub='frame')),
            Item(ring(ROW_FAN, 25.0, 3.0), 'frame', 'back', spec3d=[]),
            Item(Circle(ROW_FAN, 6.0), 'frame', 'back', spec3d=[]),
            Item(plate, 'pad', 'back', collider=[('box', v3(pc[0], pc[1], sg * 10.0), [t3, n3, Z], [15.5, 1.9, 6.0])
                                                 for sg in (-1.0, 1.0)],
                 spec3d=eq.box3d(p3(pc), t3, n3, Z, 15.5, 1.9, 16.0, 1.9, 'pad')),
            Item(seat, 'pad', 'back', collider=('box', v3(px - 3.0, ROW_SEAT - 2.6, 0.0), [X, Y, Z], [15.0, 2.6, 13.0]),
                 spec3d=eq.box3d(v3(px - 3.0, ROW_SEAT - 2.6), X, Y, Z, 15.0, 2.6, 13.0, 2.6, 'pad')
                 + eq.box3d(v3(px - 3.0, 30.4), X, Y, Z, 9.0, 1.0, 5.0, 0.5, 'frame')),     # its carriage on the rail
            Item(None, 'metal', 'back', collider=('capsule', H0 - Z * 27.0, H0 + Z * 27.0, 1.8), grip=True),
            Item(Cone(V(H[0], H[1]), V(ROW_EXIT[0], ROW_EXIT[1]), 0.6), 'metal', ('before', 'base'),
                 collider=('capsule', H0, ROW_EXIT, 0.4),
                 spec3d=eq.rod3d(H0 - Z * 25.0, H0 + Z * 25.0, 1.8, 'metal') + eq.rod3d(H0, ROW_EXIT, 0.6, 'metal'))]


def rowing_machine(key):
    @exercise(key, 'cardio', 'side', muscles=['lats', 'quads', 'glutes'])
    def build():
        def equip(J, v, u):
            return rower(v, J)
        return rower_pose, Cycle(2.4, 2), equip
    return build


rowing_machine('rowing')
rowing_machine('rowingMachine')


# ---- bikes -----------------------------------------------------------------------------------

CRANK_L = 17.25


def crank_pin(bb, theta, r=CRANK_L):
    """Pedal spindle; theta clockwise from the top in the side view (the pedal moves forward on top)."""
    return np.asarray(bb, float) + r * np.array([math.sin(theta), math.cos(theta)])


def ankle_on_pedal(spindle, fp, ball=10.0, below=9.3):
    """Ankle for the ball of the foot on the pedal spindle, foot pitched fp."""
    a = math.radians(fp)
    t = np.array([math.cos(a), math.sin(a)])
    n = np.array([-math.sin(a), math.cos(a)])
    return spindle - t * ball + n * below


def ankling(theta):
    """Foot pitch through the pedal stroke: level over the top, toes down pulling through the back."""
    return -10.0 + 10.0 * math.cos(theta) + 8.0 * math.sin(theta)


def pedal_legs(pose, bb, theta_r, half=11.0, pole=(1.0, 0.15, 0.12)):
    for s, th, sg in (('R', theta_r, 1.0), ('L', theta_r + math.pi, -1.0)):
        fp = ankling(th)
        a = ankle_on_pedal(crank_pin(bb, th), fp)
        pose['leg' + s] = {'foot': v3(a[0], a[1], sg * half), 'foot_pitch': fp,
                           'pole': v3(pole[0], pole[1], pole[2] * sg)}
    return pose


CRANK_Z = 6.5          # crank arms each side of the bottom bracket; the pedal runs out under the foot


def saddle_collider(rear, nose, top_y, half_w, nose_r=2.0):
    """A saddle: the wide rear the sit bones rest on (x from rear to the middle) and the narrow nose
    the thighs pass either side of."""
    mid = (rear + nose) / 2
    return [('box', v3((rear + mid) / 2, top_y - 1.6, 0.0), [X, Y, Z], [(mid - rear) / 2, 1.6, half_w]),
            ('capsule', v3(mid, top_y - nose_r, 0.0), v3(nose - nose_r, top_y - nose_r, 0.0), nose_r)]


def cranks(bb, theta_r, fp_r, fp_l, ring_r=10.0):
    """(far items, near items): crank arms, pedals and the chainring, each side with the foot on it.
    Both go between the far leg and the body: the far crank lies nearer the camera than the far foot
    on its pedal, the frame covers it; the near crank, inboard of the near foot, lies under that leg."""
    out, cols, spec = {}, {}, {}
    for s, th, fp, sg in (('R', theta_r, fp_r, 1.0), ('L', theta_r + math.pi, fp_l, -1.0)):
        p = crank_pin(bb, th)
        arm = Cone(V(*bb), V(*p), 2.0)
        a = math.radians(fp)
        pedal = RBox(V(*p), 5.0, 1.3, 1.3, a)
        out[s] = Union([arm, pedal])
        t, n = v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a))
        cols[s] = [('capsule', v3(bb[0], bb[1], sg * CRANK_Z), v3(p[0], p[1], sg * CRANK_Z), 1.2),
                   ('box', v3(p[0], p[1], sg * (CRANK_Z + 4.5)), [t, n, Z], [5.0, 1.3, 4.5])]
        # 3D: each arm outside the bottom bracket, its pedal running out under the ball of the foot
        # (inside the foot's width, so seen side-on the sole stays in front of it)
        col = 'metal' if s == 'R' else 'frame'
        spec[s] = (eq.rod3d(p3(bb, sg * CRANK_Z), p3(p, sg * CRANK_Z), 2.0, col)
                   + eq.box3d(p3(p, sg * (CRANK_Z + 3.5)), t, n, Z, 5.0, 1.3, 3.5, 1.3, col))
    # the chainring on the drive side between the frame and the near arm, the bottom bracket's shell
    # across between the arms
    ring3 = (drum3d(p3(bb, 4.6), Z, ring_r, 0.5, 'frame', 'plate', 2.4)
             + eq.cyl3d(p3(bb), Z, 3.2, CRANK_Z, 'frame'))
    near = [Item(ring(V(*bb), ring_r, 2.4), 'frame', ('after', 'legL'), spec3d=ring3),
            Item(Circle(V(*bb), 3.2), 'frame', ('after', 'legL'), spec3d=[]),
            Item(out['R'], 'metal', ('after', 'legL'), collider=cols['R'], spec3d=spec['R'])]
    far = [Item(out['L'], 'frame', ('after', 'legL'), collider=cols['L'], spec3d=spec['L'])]
    return far, near


BIKE_BB = np.array([0.0, 28.0])
BIKE_REAR = V(-40.5, 34.0)
BIKE_FRONT = V(59.0, 34.0)
BIKE_SEAT = V(-21.0, 99.0)          # saddle top
BIKE_HOOD = np.array([53.0, 92.0])
WHEEL_R = 34.0


def road_bike(theta_r):
    bb = V(*BIKE_BB)
    cluster = V(-15.6, 80.7)
    head_top, head_bot = V(45.0, 84.0), V(49.0, 70.0)
    tubes = [Cone(bb, BIKE_REAR, 1.6), Cone(BIKE_REAR, cluster, 1.4), Cone(bb, cluster, 2.0),
             Cone(cluster, head_top, 1.9), Cone(bb, head_bot, 2.3), Cone(head_top, head_bot, 2.6),
             Cone(head_bot, BIKE_FRONT, 1.7), Cone(cluster, V(-20.2, 96.0), 1.4),
             Cone(head_top, V(49.0, 89.0), 1.8)]
    bar_pts = [V(47.0, 89.5), V(54.0, 91.5), V(58.5, 88.0), V(58.0, 79.5), V(52.5, 77.5)]
    bars = polyline(bar_pts, 1.7)
    saddle = Poly([V(-34.0, 99.2), V(-9.0, 98.6), V(-12.0, 96.4), V(-32.0, 96.0)], r=1.6)
    wheels = [ring(BIKE_REAR, WHEEL_R, 3.2), ring(BIKE_FRONT, WHEEL_R, 3.2),
              Circle(BIKE_REAR, 2.4), Circle(BIKE_FRONT, 2.4)]
    far, near = cranks(BIKE_BB, theta_r, ankling(theta_r), ankling(theta_r + math.pi))
    # the drops curve down at the hands, each side; the tops cross between them at the stem
    bar_cols = [('capsule', v3(a[0], a[1], sg * 20.0), v3(b[0], b[1], sg * 20.0), 1.2)
                for sg in (-1.0, 1.0) for a, b in zip(bar_pts, bar_pts[1:])]
    bar_cols.append(('capsule', v3(50.0, 90.4, -20.0), v3(50.0, 90.4, 20.0), 1.2))
    # 3D: the wheels as tyres round hubs on their axles; the stays and the fork blades in pairs either
    # side of the wheels, the other tubes down the middle; the drops at the hands' width with the tops
    # across between them at the stem; the saddle wide at the back, narrow at the nose
    wheel3 = []
    for c, half in ((BIKE_REAR, 6.5), (BIKE_FRONT, 5.5)):
        wheel3 += hoop3d(p3(c), Z, WHEEL_R - 1.6, 1.6, 'frame') + eq.cyl3d(p3(c), Z, 2.4, half, 'frame')
    tube3 = (eq.rod3d(p3(bb), p3(cluster), 2.0) + eq.rod3d(p3(cluster), p3(head_top), 1.9)
             + eq.rod3d(p3(bb), p3(head_bot), 2.3) + eq.rod3d(p3(head_top), p3(head_bot), 2.6)
             + eq.rod3d(p3(cluster), v3(-20.2, 96.0), 1.4) + eq.rod3d(p3(head_top), v3(49.0, 89.0), 1.8))
    for sg in (-1.0, 1.0):
        tube3 += (eq.rod3d(p3(bb, sg * 3.0), p3(BIKE_REAR, sg * 6.5), 1.6)
                  + eq.rod3d(p3(cluster, sg * 2.2), p3(BIKE_REAR, sg * 6.5), 1.4)
                  + eq.rod3d(p3(head_bot, sg * 3.2), p3(BIKE_FRONT, sg * 5.5), 1.7))
    bar3 = eq.rod3d(p3(bar_pts[0], -20.0), p3(bar_pts[0], 20.0), 1.7)
    for sg in (-1.0, 1.0):
        bar3 += eq.rope3d([p3(q, sg * 20.0) for q in bar_pts], 1.7, 'frame')
    saddle3 = (eq.box3d(v3(-27.0, 97.6), X, Y, Z, 8.6, 3.2, 7.0, 1.6, 'pad')
               + eq.box3d(v3(-16.0, 97.6), X, Y, Z, 8.6, 3.2, 2.8, 1.6, 'pad'))
    return far + [Item(Union(wheels), 'frame', ('after', 'legL'), spec3d=wheel3),
                  Item(Union(tubes), 'frame', ('after', 'legL'),
                       collider=[('capsule', v3(cluster[0], cluster[1], 0.0), v3(head_top[0], head_top[1], 0.0), 1.9),
                                 ('capsule', v3(bb[0], bb[1], 0.0), v3(cluster[0], cluster[1], 0.0), 2.0)],
                       spec3d=tube3),
                  Item(bars, 'frame', ('after', 'legL'), collider=bar_cols, grip=True, spec3d=bar3),
                  Item(saddle, 'pad', ('after', 'legL'), collider=saddle_collider(-34.0, -9.0, 99.0, 7.0),
                       spec3d=saddle3)] + near


@exercise('cycling', 'cardio', 'side', muscles=['quads', 'glutes', 'calves'])
def cycling():
    P = v3(-18.0, BIKE_SEAT[1] + 9.0, 0.0)

    def pose(u):
        th = 2 * math.pi * u
        p = {'pelvis': P + v3(0.0, -0.4 * (0.5 + 0.5 * math.cos(4 * math.pi * u)), 0.0),
             'pitch': 47.0, 'neck': 34.0}
        pedal_legs(p, BIKE_BB, th)
        p.update(both(v3(BIKE_HOOD[0], BIKE_HOOD[1], 20.0), [-0.6, -1.0, 0.55]))
        return p

    def equip(J, v, u):
        return road_bike(2 * math.pi * u)

    return pose, Cycle(2.0 / 3.0, 6), equip


# fan bike: pedals drive the fan, the arm levers push and pull opposite to the same-side leg
FAN_BB = np.array([0.0, 30.0])
FAN_C = V(58.0, 44.0)
FAN_R = 31.0
FAN_PIVOT = np.array([42.0, 60.0])
FAN_LEVER = 70.0
FAN_SEAT = V(-24.0, 88.0)


def fan_grip(theta):
    psi = math.radians(-17.0 - 15.0 * math.sin(theta))
    return FAN_PIVOT + FAN_LEVER * np.array([math.sin(psi), math.cos(psi)])


@exercise('assaultBike', 'cardio', 'side', muscles=['quads', 'glutes', 'delts'])
def assault_bike():
    P = v3(FAN_SEAT[0] + 2.0, FAN_SEAT[1] + 9.0, 0.0)

    def pose(u):
        th = 2 * math.pi * u
        p = {'pelvis': P, 'pitch': 12.0, 'neck': 6.0}
        pedal_legs(p, FAN_BB, th, pole=(1.0, 0.1, 0.12))
        gr, gl = fan_grip(th), fan_grip(th + math.pi)
        p.update(arms_ik(v3(gl[0], gl[1], -25.0), v3(gr[0], gr[1], 25.0),
                         [-0.6, -1.0, -0.5], [-0.6, -1.0, 0.5]))
        return p

    def equip(J, v, u):
        th = 2 * math.pi * u
        bb = V(*FAN_BB)
        tubes = [Cone(V(58.0, 44.0), V(64.0, 3.0), 2.6), Cone(V(46.0, 2.2), V(84.0, 2.2), 2.4),
                 Cone(bb, V(58.0, 44.0), 2.6), Cone(bb, V(-20.0, 80.0), 2.6),
                 Cone(bb, V(-36.0, 3.0), 2.4), Cone(V(-50.0, 2.2), V(-20.0, 2.2), 2.4)]
        seat = RBox(FAN_SEAT - V(0.0, 3.2), 13.0, 3.2, 3.2)
        far, near = cranks(FAN_BB, th, ankling(th), ankling(th + math.pi), ring_r=7.0)
        # 3D: the fan a drum on its axle; the frame down the middle, a foot across the floor at each
        # end; the fan's axle carried on struts down both faces of the drum (seen side-on, the near
        # ones are the 2D's tubes over the fan) and on a leg each side down to the front foot; the
        # seat wide at the back, narrow at the nose
        fan3 = drum3d(p3(FAN_C), Z, FAN_R, 12.0, 'frame', 'pad', 3.0, hub_r=6.0, hub='frame', hub_half=12.5)
        rim = bb + (FAN_C - bb) * (1.0 - FAN_R / float(np.linalg.norm(FAN_C - bb)))     # the beam meets the drum
        tube3 = (eq.rod3d(v3(46.0, 2.2), v3(84.0, 2.2), 2.4) + eq.rod3d(v3(64.0, 2.2, -26.0), v3(64.0, 2.2, 26.0), 2.4)
                 + eq.rod3d(p3(bb), p3(FAN_C), 2.6) + eq.rod3d(p3(bb), v3(-20.0, 80.0), 2.6)
                 + eq.rod3d(p3(bb), v3(-36.0, 3.0), 2.4) + eq.rod3d(v3(-50.0, 2.2), v3(-20.0, 2.2), 2.4)
                 + eq.rod3d(v3(-36.0, 2.2, -26.0), v3(-36.0, 2.2, 26.0), 2.4))
        for sg in (-1.0, 1.0):
            tube3 += (eq.rod3d(p3(rim, sg * 15.0), p3(FAN_C, sg * 15.0), 2.6)
                      + eq.rod3d(p3(FAN_C, sg * 15.0), v3(64.0, 3.0, sg * 15.0), 2.6))
        seat3 = (eq.box3d(v3(FAN_SEAT[0] - 3.0, FAN_SEAT[1] - 3.2), X, Y, Z, 10.0, 3.2, 11.0, 3.2, 'pad')
                 + eq.box3d(v3(FAN_SEAT[0] + 5.0, FAN_SEAT[1] - 3.2), X, Y, Z, 8.0, 3.2, 5.0, 3.2, 'pad'))
        # the frame, the fan and the seat stand on the midline: in front of the far leg (and of
        # the far crank beside them), behind the body and the near leg
        mid = ('after', 'legL')
        items = far + [Item(Circle(FAN_C, FAN_R), 'pad', mid,
                            collider=('cylinder', v3(FAN_C[0], FAN_C[1], 0.0), Z, FAN_R, 12.0), spec3d=fan3),
                       Item(ring(FAN_C, FAN_R, 3.0), 'frame', mid, spec3d=[]),
                       Item(Circle(FAN_C, 6.0), 'frame', mid, spec3d=[]),
                       Item(Union(tubes), 'frame', mid,
                            collider=('capsule', v3(bb[0], bb[1], 0.0), v3(-20.0, 80.0, 0.0), 2.6), spec3d=tube3),
                       Item(seat, 'pad', mid, collider=saddle_collider(FAN_SEAT[0] - 13.0, FAN_SEAT[0] + 13.0,
                                                                       FAN_SEAT[1], 11.0, nose_r=3.0), spec3d=seat3)]
        items += near
        # the arm levers run outside the knees: the near one in front of the near leg, just behind
        # its fist; the far one behind everything
        for s, t2, sg, z in (('R', th, 1.0, ('before', 'armR')), ('L', th + math.pi, -1.0, ('before', 'armL'))):
            g = fan_grip(t2)
            low = FAN_PIVOT - (g - FAN_PIVOT) * 0.18
            top = g + (g - FAN_PIVOT) * 0.12
            col = 'metal' if s == 'R' else 'frame'
            # 3D: each lever at its hand's width; the far one carries the axle both pivot on, across
            # through the fan's housing
            lever3 = (eq.rod3d(p3(low, sg * 25.0), p3(g, sg * 25.0), 2.2, col)
                      + eq.rod3d(p3(g, sg * 25.0), p3(top, sg * 25.0), 3.0, col))
            if s == 'L':
                lever3 += eq.rod3d(p3(FAN_PIVOT, -25.0), p3(FAN_PIVOT, 25.0), 2.0, 'frame')
            items.append(Item(Union([Cone(V(*low), V(*g), 2.2), Cone(V(*g), V(*top), 3.0)]), col, z,
                              collider=('capsule', v3(low[0], low[1], sg * 25.0), v3(top[0], top[1], sg * 25.0), 2.2),
                              grip=True, spec3d=lever3))
        return items

    return pose, Cycle(0.75, 6), equip


# ---- elliptical -------------------------------------------------------------------------------
# Front-drive linkage: a pedal arm runs from the crank pin to a roller on the rear track; the
# pedal rides on the arm, so the foot traces the ellipse the machine is named after.

ELL_K = np.array([66.0, 34.0])          # crank centre (inside the front housing)
ELL_RC = 22.0
ELL_LA = 104.0                          # crank pin -> rear roller
ELL_RY = 9.0                            # roller height
ELL_F = 0.64                            # pedal position along the arm
ELL_PIVOT = np.array([82.0, 70.0])      # handle pivot on the column
ELL_LEVER = 72.0
ELL_ARM_Z = 13.0                        # 3D: the pedal arms and their tracks, just outside the flywheel


def ell_link(theta):
    """Crank pin Q, roller R, pedal top point, pedal pitch for crank angle theta."""
    Q = ELL_K + ELL_RC * np.array([math.sin(theta), math.cos(theta)])
    dy = Q[1] - ELL_RY
    R = np.array([Q[0] - math.sqrt(ELL_LA ** 2 - dy * dy), ELL_RY])
    d = (Q - R) / np.linalg.norm(Q - R)
    up = np.array([-d[1], d[0]])
    slope = math.degrees(math.atan2(d[1], d[0]))
    pedal = Q + (R - Q) * ELL_F + up * 3.0
    return Q, R, pedal, 0.6 * (slope - 14.0)


def ell_grip(theta):
    psi = math.radians(36.0 + 13.0 * math.sin(theta))
    return ELL_PIVOT + ELL_LEVER * np.array([-math.sin(psi), math.cos(psi)])


@exercise('elliptical', 'cardio', 'side', muscles=['quads', 'glutes', 'calves'])
def elliptical():
    Lmax = LEG * 0.992

    def pose(u):
        th = 2 * math.pi * u
        p = {'pitch': 4.0, 'neck': 0.0}
        ank = {}
        for s, t2, sg in (('R', th, 1.0), ('L', th + math.pi, -1.0)):
            _, _, top, fp = ell_link(t2)
            a = math.radians(fp)
            t, n = np.array([math.cos(a), math.sin(a)]), np.array([-math.sin(a), math.cos(a)])
            A = top - t * 4.6 + n * ANKLE_H
            ank[s] = A
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 11.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, 0.15 * sg)}
        px = 1.0
        py = 111.0
        for s, A in ank.items():
            dz = 11.0 - HIP_HALF
            py = smin(py, A[1] + math.sqrt(Lmax ** 2 - (A[0] - px) ** 2 - dz * dz), 3.0)
        p['pelvis'] = v3(px, py, 0.0)
        gr, gl = ell_grip(th), ell_grip(th + math.pi)
        p.update(arms_ik(v3(gl[0], gl[1], -25.0), v3(gr[0], gr[1], 25.0),
                         [-0.5, -1.0, -0.6], [-0.5, -1.0, 0.6]))
        return p

    def equip(J, v, u):
        th = 2 * math.pi * u
        frame = [Cone(V(-72.0, 2.2), V(96.0, 2.2), 2.2),
                 Cone(V(-68.0, 5.2), V(-2.0, 5.2), 1.8),                       # roller track
                 Cone(V(92.0, 2.5), V(78.0, 150.0), 3.2)]                      # column
        console = RBox(V(75.0, 153.0), 12.0, 5.0, 4.0, math.radians(-22.0))
        items, cols, spec = [], {}, {}
        for s, t2, sg in (('L', th + math.pi, -1.0), ('R', th, 1.0)):
            Q, R, top, fp = ell_link(t2)
            arm = Union([Cone(V(*Q), V(*R), 2.2), Circle(V(*R), 3.2), Circle(V(*Q), 3.0),
                         RBox(V(*top) - V(0.0, 1.4), 14.0, 1.6, 1.6, math.radians(fp))])
            g = ell_grip(t2)
            # the handle ends in the fist: leaning back as far as it does, a top running on past the
            # hand would pass through the wrist when the handle is drawn back
            low, sleeve = ELL_PIVOT - (g - ELL_PIVOT) * 0.25, g - (g - ELL_PIVOT) * 0.1
            lever = Union([Cone(V(*low), V(*g), 2.2), Cone(V(*sleeve), V(*g), 3.0)])
            a = math.radians(fp)
            pc = top - np.array([0.0, 1.4])
            # each pedal rides under its foot; each handle runs up outside its arm to the fist
            cols[s] = ([('box', v3(pc[0], pc[1], sg * 11.0), [v3(math.cos(a), math.sin(a)),
                                                               v3(-math.sin(a), math.cos(a)), Z], [14.0, 1.6, 6.0])],
                       ('capsule', v3(low[0], low[1], sg * 25.0), v3(g[0], g[1], sg * 25.0), 2.2))
            # 3D: the pedal arm just outside the flywheel, from its crank pin on the flywheel's face
            # to the roller on its own track; the pedal on it under the foot; the handle at the
            # hand's width
            col = 'metal' if s == 'R' else 'frame'
            spec[s] = (eq.rod3d(p3(Q, sg * ELL_ARM_Z), p3(R, sg * ELL_ARM_Z), 2.2, col)
                       + eq.cyl3d(p3(R, sg * ELL_ARM_Z), Z, 3.2, 1.6, col)
                       + eq.cyl3d(p3(Q, sg * (ELL_ARM_Z - 1.6)), Z, 3.0, 1.6, col)
                       + eq.box3d(p3(pc, sg * 11.0), v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a)), Z,
                                  14.0, 1.6, 6.0, 1.6, col),
                       eq.rod3d(p3(low, sg * 25.0), p3(g, sg * 25.0), 2.2, col)
                       + eq.rod3d(p3(sleeve, sg * 25.0), p3(g, sg * 25.0), 3.0, col))
            if s == 'L':
                items += [Item(lever, 'frame', ('before', 'armL'), collider=cols[s][1], grip=True,
                               spec3d=spec[s][1] + eq.rod3d(p3(ELL_PIVOT, -25.0), p3(ELL_PIVOT, 25.0), 2.0, 'frame')),
                          Item(arm, 'frame', ('after', 'armL'), collider=cols[s][0], spec3d=spec[s][0])]
            else:
                near_arm, near_lever = arm, lever
        # 3D: a rail down the middle with a foot across the floor at each end, the rollers' tracks
        # each side, the column up the middle (both handles pivot on an axle across it, carried by
        # the far handle), the flywheel a drum on its crank axle
        frame3 = (eq.rod3d(v3(-72.0, 2.2), v3(96.0, 2.2), 2.2) + eq.rod3d(v3(92.0, 2.5), v3(78.0, 150.0), 3.2)
                  + eq.rod3d(v3(-68.0, 3.0, -16.0), v3(-68.0, 3.0, 16.0), 2.2)
                  + eq.rod3d(v3(-4.0, 3.4, -ELL_ARM_Z), v3(-4.0, 3.4, ELL_ARM_Z), 1.8)
                  + eq.rod3d(v3(92.0, 2.2, -22.0), v3(92.0, 2.2, 22.0), 2.2))
        for sg in (-1.0, 1.0):
            frame3 += eq.rod3d(v3(-68.0, 5.2, sg * ELL_ARM_Z), v3(-2.0, 5.2, sg * ELL_ARM_Z), 1.8)
        ca = math.radians(-22.0)
        console3 = eq.box3d(v3(75.0, 153.0), v3(math.cos(ca), math.sin(ca)), v3(-math.sin(ca), math.cos(ca)), Z,
                            12.0, 5.0, 17.0, 4.0, 'frame')
        items += [Item(Union(frame), 'frame', ('after', 'legL'),
                       collider=('capsule', v3(92.0, 2.5, 0.0), v3(78.0, 150.0, 0.0), 3.2), spec3d=frame3),
                  Item(console, 'frame', ('after', 'legL'), spec3d=console3),
                  Item(Circle(V(*ELL_K), 27.0), 'pad', ('after', 'legL'),
                       collider=('cylinder', v3(ELL_K[0], ELL_K[1], 0.0), Z, 27.0, 10.0),
                       spec3d=drum3d(p3(ELL_K), Z, 27.0, 10.0, 'frame', 'pad', 3.0)),
                  Item(ring(V(*ELL_K), 27.0, 3.0), 'frame', ('after', 'legL'), spec3d=[]),
                  Item(near_arm, 'metal', ('after', 'legL'), collider=cols['R'][0], spec3d=spec['R'][0]),
                  Item(near_lever, 'metal', ('before', 'armR'), collider=cols['R'][1], grip=True, spec3d=spec['R'][1])]
        return items

    return pose, Cycle(1.1, 4), equip


# ---- stair climber ---------------------------------------------------------------------------
# A revolving staircase: the steps sink one rise per step taken, so the climber stays in place.

ST_RUN, ST_RISE = 27.0, 20.0
ST_X0, ST_Y0 = -70.3, 2.2               # tread k spans [X0 + k run, X0 + (k + 1) run] at Y0 + k rise
ST_LAND = np.array([20.0, 70.0])        # ankle where each foot lands
ST_DUTY = 0.56
ST_WIN = (-31.0, 47.0)                  # visible part of the staircase (x)
ST_SLOPE = ST_RISE / ST_RUN
ST_HALF_W = 27.0                        # 3D: half the staircase's width
ST_SIDE_Z = 31.0                        # 3D: the stringers, floor rails and posts each side; the housings' half width
ST_PARK = (v3(-33.0, 7.0), v3(57.0, 86.0))      # 3D: inside the bottom and the top housing
# 3D relay (see Stairs.boxes3d), per family: where its slots pick a step up (runs from ST_X0), and the
# stretch between which they carry it. The upper family takes the steps as they come into the window
# (4.344, under the top housing), the lower one leaves them whole in the bottom housing (below 0.59);
# each handover leaves several frames with both families on the step, and every wait is 0.1 run or
# more (two of the bake's frames).
ST_RELAY = ((4.5, (ST_WIN[1] - ST_X0) / ST_RUN, 2.6), (3.1, 2.95, 1.2), (1.7, 1.55, 0.55))


def st_base(x):
    """The stringer line under the steps."""
    return ST_Y0 + (x - ST_X0 - ST_RUN) * ST_SLOPE - 12.0


ST_ROLL = ((0.0, 0.0), (0.72, 0.0), (1.0, -16.0))     # flat on the tread, a small toe push at the end


class Stairs:
    def __init__(self, period):
        self.period = period
        d = ST_DUTY
        a_to = self.stance(1.0)
        a_hs = self.stance(0.0)
        eps = 1e-4
        k = (1 - d) / d
        v_to = (a_to - self.stance(1.0 - eps)) / eps * k
        v_hs = (self.stance(eps) - a_hs) / eps * k
        # the foot leaves a tread whose front is the next riser, which comes down and back at it:
        # it lifts first, then passes over the next tread's nose and the corner of the one it
        # lands on, so the toes never go through a step
        self.swing = Spline([0.0, 0.25, 0.5, 1.0],
                            [a_to, a_to + np.array([-3.0, 18.0]), ST_LAND + np.array([-10.0, 11.0]), a_hs], v_to, v_hs)

    def stance(self, t):
        """Ankle at stance progress t: flat on a sinking tread, a small toe push at the end."""
        m = 2.0 * ST_DUTY * t                            # steps the tread has sunk
        tread_y = ST_LAND[1] - ANKLE_H - m * ST_RISE
        fp = keyed(t, ST_ROLL)
        a = planted_ankle(ST_LAND[0] - m * ST_RUN, fp)
        return np.array([a[0], a[1] + tread_y])

    def foot(self, p):
        if p < ST_DUTY:
            t = p / ST_DUTY
            return self.stance(t), keyed(t, ST_ROLL), True
        s = (p - ST_DUTY) / (1 - ST_DUTY)
        fp = keyed(s, ((0.0, -16.0), (0.35, -4.0), (0.8, 4.0), (1.0, 0.0)))
        return self.swing(s), fp, False

    def offset(self, t):
        """Steps the staircase has moved at time t (mod 1: it is periodic by one step)."""
        return (2.0 * t / self.period) % 1.0

    def shapes(self, t):
        o = self.offset(t)
        pts = []
        w0, w1 = ST_WIN
        k0 = int(math.floor((w0 - ST_X0) / ST_RUN)) - 1
        k1 = int(math.ceil((w1 - ST_X0) / ST_RUN)) + 1
        for k in range(k0, k1 + 1):
            x0 = ST_X0 + (k - o) * ST_RUN
            y = ST_Y0 + (k - o) * ST_RISE
            pts += [V(x0, y), V(x0 + ST_RUN, y)]
        xa, xb = pts[0][0], pts[-1][0]
        poly = Poly(pts + [V(xb, st_base(xb) - 40.0), V(xa, st_base(xa) - 40.0)], r=1.2)
        win = Poly([V(w0, st_base(w0)), V(w1, st_base(w1)), V(w1, 240.0), V(w0, 240.0)])
        return Intersect(poly, Intersect(win, RBox(V(0.0, 121.0), 200.0, 118.0)))

    def colliders(self, t, half_w=27.0):
        """Every step as a block one rise deep under its tread, the full width of the staircase."""
        o = self.offset(t)
        w0, w1 = ST_WIN
        out = []
        for k in range(int(math.floor((w0 - ST_X0) / ST_RUN)) - 1, int(math.ceil((w1 - ST_X0) / ST_RUN)) + 2):
            x0 = ST_X0 + (k - o) * ST_RUN
            y = ST_Y0 + (k - o) * ST_RISE
            out.append(('box', v3(x0 + ST_RUN / 2, y - ST_RISE / 2, 0.0), [X, Y, Z], [ST_RUN / 2, ST_RISE / 2, half_w]))
        return out

    def boxes3d(self, t, r=1.2):
        """The staircase shapes() draws, as 3D boxes the steps' width: a band along the stringer
        under the steps (between the stringer line and the line through the steps' inner corners),
        and on it for each step a block 12 deep under its tread and a filler under its nose (each
        step is a right triangle on the band, which the two cover without reaching past it). Cut to
        the window like the drawing; the treads and risers are where the feet meet them (the
        drawing is rounded out 1.2 past them).

        The boxes' make-up is fixed and the app interpolates between frames, so no box may jump.
        But equip only knows the cycle's phase, and the staircase moves two steps a cycle: a box
        can follow a step for two steps, then has to go back up. So the steps are carried in relay
        by three families of two slots (ST_RELAY): the upper family from the top housing, the
        middle and the lower ones taking over halfway down, the lower one into the bottom housing.
        A slot appears and vanishes only where it is hidden: shrunk to nothing inside the housing,
        or inside the other family's identical box while both carry the step."""
        u = (t / self.period) % 1.0
        w0, w1 = ST_WIN
        th = math.atan2(ST_RISE, ST_RUN)
        e1, e2 = v3(math.cos(th), math.sin(th)), v3(-math.sin(th), math.cos(th))
        xa, xb = w0 + 6.0 * math.sin(th) * math.cos(th), w1     # lower end in the bottom housing
        xm = (xa + xb) / 2
        out = eq.box3d(v3(xm, st_base(xm) + 6.0), e1, e2, Z, (xb - xa) / math.cos(th) / 2, 6.0 * math.cos(th),
                       ST_HALF_W, r, 'pad')
        for start, top, low in ST_RELAY:
            for w in ((-start / 2) % 0.5, (-start / 2) % 0.5 + 0.5):
                q = start - 2.0 * ((u - w) % 1.0)           # the slot's step, in runs from ST_X0
                x0, y = ST_X0 + q * ST_RUN, ST_Y0 + q * ST_RISE
                for xl, xr, yb, yt in ((x0, x0 + ST_RUN + r, y - 12.0 - r, y),
                                       (x0, x0 + 10.8 + r, y - ST_RISE, y - 12.0 + r)):
                    xl, xr, yb = max(xl, w0), min(xr, w1), max(yb, 3.0)
                    c = v3((xl + xr) / 2, (yb + yt) / 2)
                    hx, hy = (xr - xl) / 2, (yt - yb) / 2
                    if low < q < top and hx > 0.0 and hy > 0.0:
                        out += eq.box3d(c, X, Y, Z, hx, hy, ST_HALF_W, min(r, hx, hy), 'pad')
                    else:
                        # shrunk to nothing: in a housing (outside the window, or the step whole in
                        # it), else on the spot, inside the other family's box
                        if hx <= 0.0 or hy <= 0.0 or q >= ST_RELAY[0][1] or q <= ST_RELAY[-1][2]:
                            c = ST_PARK[1] if q >= 2.0 else ST_PARK[0]
                        out += eq.box3d(c, X, Y, Z, 0.0, 0.0, 0.0, 0.0, 'pad')
        return out


@exercise('stairClimber', 'cardio', 'side', muscles=['glutes', 'hamstrings', 'quads', 'calves'])
def stair_climber():
    period = 1.4
    st = Stairs(period)
    Lmax = LEG * 0.992
    grip = np.array([33.0, 138.0])

    def pose(u):
        p = {'pitch': 9.0, 'neck': 5.0}
        ank = {}
        for s, ph, sg in (('R', u, 1.0), ('L', (u + 0.5) % 1.0, -1.0)):
            a, fp, _ = st.foot(ph)
            ank[s] = a
            p['leg' + s] = {'foot': v3(a[0], a[1], sg * 10.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.1, 0.15 * sg)}
        px, py = 1.0, 134.0
        for s, A in ank.items():
            dz = 10.0 - HIP_HALF
            py = smin(py, A[1] + math.sqrt(max(Lmax ** 2 - (A[0] - px) ** 2 - dz * dz, 0.0)), 3.0)
        p['pelvis'] = v3(px, py, 0.0)
        p.update(both(v3(grip[0], grip[1], 24.0), [-0.4, -1.0, 0.6]))
        return p

    def equip(J, v, u):
        t = u * period
        stairs = st.shapes(t)
        w0, w1 = ST_WIN
        x_floor = w0 + (4.0 - st_base(w0)) / ST_SLOPE
        frame = [Cone(V(x_floor, 4.0), V(w1 + 6.0, st_base(w1 + 6.0)), 4.0),                 # stringer
                 Cone(V(x_floor - 12.0, 2.2), V(w1 + 24.0, 2.2), 2.2),
                 Cone(V(w1 + 12.0, 72.0), V(w1 + 16.0, 3.0), 3.0),                           # support
                 Cone(V(w1 + 12.0, 96.0), V(w1 + 16.0, 150.0), 3.0),                         # column
                 Cone(V(w1 + 15.0, 142.0), V(grip[0] - 4.0, grip[1]), 2.2)]                  # rail
        top = RBox(V(w1 + 10.0, 86.0), 13.0, 16.0, 5.0)
        bottom = RBox(V(w0 - 2.0, 7.0), 9.0, 7.0, 3.0)
        console = RBox(V(w1 + 14.0, 154.0), 11.0, 4.5, 4.0, math.radians(-20.0))
        # the rails run back to the hands each side, outside the arms
        rails = [('capsule', v3(w1 + 15.0, 142.0, sg * 24.0), v3(grip[0], grip[1], sg * 24.0), 2.2) for sg in (-1, 1)]
        # 3D: a stringer each side of the steps, each on a rail along the floor and a post up to the
        # top housing; the column up the middle from the housing to the console, a bar across it
        # and the rails back to the hands each side; the housings the staircase's width
        frame3 = (eq.rod3d(v3(w1 + 12.0, 96.0), v3(w1 + 16.0, 150.0), 3.0)
                  + eq.rod3d(v3(w1 + 15.0, 142.0, -24.0), v3(w1 + 15.0, 142.0, 24.0), 2.2))
        for sg in (-1.0, 1.0):
            z = sg * ST_SIDE_Z
            frame3 += (eq.rod3d(v3(x_floor, 4.0, z), v3(w1 + 6.0, st_base(w1 + 6.0), z), 4.0)
                       + eq.rod3d(v3(x_floor - 12.0, 2.2, z), v3(w1 + 24.0, 2.2, z), 2.2)
                       + eq.rod3d(v3(w1 + 12.0, 72.0, z), v3(w1 + 16.0, 3.0, z), 3.0)
                       + eq.rod3d(v3(w1 + 15.0, 142.0, sg * 24.0), v3(grip[0] - 4.0, grip[1], sg * 24.0), 2.2))
        a = math.radians(-20.0)
        housing3 = (eq.box3d(v3(w1 + 10.0, 86.0), X, Y, Z, 13.0, 16.0, ST_SIDE_Z, 5.0, 'frame')
                    + eq.box3d(v3(w0 - 2.0, 7.0), X, Y, Z, 9.0, 7.0, ST_SIDE_Z, 3.0, 'frame')
                    + eq.box3d(v3(w1 + 14.0, 154.0), v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a)), Z,
                               11.0, 4.5, 18.0, 4.0, 'frame'))
        return [Item(stairs, 'pad', 'back', collider=st.colliders(t), spec3d=st.boxes3d(t)),
                Item(Union(frame), 'frame', 'back', collider=rails, grip=True, spec3d=frame3),
                Item(Union([top, bottom, console]), 'frame', 'back',
                     collider=('box', v3(w1 + 10.0, 86.0, 0.0), [X, Y, Z], [13.0, 16.0, 27.0]), spec3d=housing3)]

    return pose, Cycle(period, 3), equip


# ---- ski erg ---------------------------------------------------------------------------------

SKI_PULLEY = np.array([55.0, 204.0])
SKI_Z = 24.0                        # the handles and their pulleys, each side of the midline


@exercise('skiErg', 'cardio', 'side', muscles=['lats', 'triceps', 'abs'])
def ski_erg():
    hands = Spline([0.0, 0.45, 1.0], [np.array([40.0, 190.0]), np.array([40.0, 140.0]), np.array([0.0, 63.0])],
                   np.array([10.0, -40.0]), np.array([-40.0, -50.0]))

    def pose(u):
        h = smooth(0.08, 0.92, u)
        P = v3(lerp(1.5, -15.0, h), lerp(HIP_H - 0.8, 84.0, h), 0.0)
        pitch = lerp(2.0, 44.0, h)
        p = {'pelvis': P, 'pitch': pitch, 'neck': 0.35 * pitch, 'shrug': lerp(2.5, 0.0, smooth(0.0, 0.4, u))}
        p.update(feet(0.0, 12.0, 6.0))
        H = hands(u)
        # the handles hang from pulleys wider than the head, and finish just outside the thighs
        p.update(both(v3(H[0], H[1], SKI_Z), [-0.5, -0.6, 1.0]))
        return p

    def equip(J, v, u):
        tower = [RBox(V(62.0, 108.0), 6.5, 106.0, 5.0), Cone(V(44.0, 2.2), V(84.0, 2.2), 2.4)]
        # 3D: the column on a foot along it and one across it; the flywheel a drum at its top, and
        # an arm across in front of it out to a pulley each side, where the cords come down
        tower3 = (eq.box3d(v3(62.0, 108.0), X, Y, Z, 6.5, 106.0, 7.5, 5.0, 'frame')
                  + eq.rod3d(v3(44.0, 2.2), v3(84.0, 2.2), 2.4) + eq.rod3d(v3(62.0, 2.2, -30.0), v3(62.0, 2.2, 30.0), 2.4)
                  + eq.rod3d(p3(SKI_PULLEY, -SKI_Z), p3(SKI_PULLEY, SKI_Z), 1.4)
                  + eq.cyl3d(p3(SKI_PULLEY, -SKI_Z), Z, 2.4, 1.0, 'frame') + eq.cyl3d(p3(SKI_PULLEY, SKI_Z), Z, 2.4, 1.0, 'frame'))
        items = [Item(Union(tower), 'frame', 'back', spec3d=tower3),
                 Item(Circle(V(62.0, 200.0), 14.0), 'pad', 'back',
                      spec3d=drum3d(v3(62.0, 200.0), Z, 14.0, 8.0, 'frame', 'pad', 2.6)),
                 Item(ring(V(62.0, 200.0), 14.0, 2.6), 'frame', 'back', spec3d=[])]
        for s, sg in (('L', -1.0), ('R', 1.0)):
            # each cord runs at its hand's side, beside the head: the near one passes in front of the
            # head and body, just behind the fist on its handle; the far one behind them. It leaves
            # the top of the handle, a few cm above the middle of the fist.
            h = J.p['hand' + s]
            top = v3(SKI_PULLEY[0], SKI_PULLEY[1], sg * SKI_Z)
            items.append(Item(Cone(V(h[0], h[1]), V(*SKI_PULLEY), 0.6), 'metal', ('before', 'arm' + s),
                              collider=('capsule', h + unit(top - h) * 6.0, top, 0.4),
                              spec3d=eq.rod3d(h, top, 0.6, 'metal')))
        return items

    return pose, Timeline([(0.2, 0, 0), (0.8, 0, 1), (0.15, 1, 1), (1.05, 1, 0)] * 2), equip


# ---- jump rope (seen from behind: the rope's arc and the calves read best) -----------------------

# The rope has to clear the feet and the arms in 3D: a jump high enough (with the toes only a little
# pointed) for the rope to pass under both feet, a loop wide and round at the bottom rather than a
# narrow U, swinging out past the hands, and the elbows kept in at the sides.
JR_HOP, JR_POINT = 6.5, 8.0        # hop height (ankle, cm), toes pointed at the top (deg)
JR_ELBOW_Z = -0.4                   # elbow pole sideways (- = elbows in)
JR_FLAT, JR_WIDE = 0.5, 0.4         # loop profile: out along the turn ~ sin^FLAT; swing past the hands


@exercise('jumpRope', 'cardio', 'back', muscles=['calves', 'delts'])
def jump_rope():
    hop = JR_HOP
    grip_z = 30.0

    def body(u):
        c = math.cos(2 * math.pi * u)                  # u = 0: top of the hop, rope under the feet
        ay = ANKLE_H + hop * max(c, 0.0) ** 1.5
        py = ay + 84.9 + 1.3 * c
        return ay, py

    def rope_dir(u):
        phi = math.radians(-90.0 - 360.0 * u)          # over the head from behind, under the feet
        return v3(math.cos(phi), math.sin(phi), 0.0)

    def hands(u):
        _, py = body(u)
        d = rope_dir(u)
        c = v3(11.0, py + 2.0, 0.0) + d * 3.0          # wrists turn small circles with the rope
        return c - v3(0, 0, grip_z), c + v3(0, 0, grip_z)

    radius = body(0.0)[1] + 2.0 - 3.0 - 1.5            # the rope just skims the floor

    def pose(u):
        ay, py = body(u)
        air = max(math.cos(2 * math.pi * u), 0.0)
        fp = -JR_POINT * air
        ay = max(ay, planted_ankle(0.0, fp)[1])          # push off and land on the toes
        p = {'pelvis': v3(0.5, py, 0.0), 'pitch': 2.0}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(0.0, ay, sg * 9.0), 'foot_pitch': fp, 'toe_out': 4.0,
                            'pole': v3(1.0, 0.0, 0.2 * sg)}
        hl, hr = hands(u)
        p.update(arms_ik(hl, hr, [-1.0, -0.4, -JR_ELBOW_Z], [-1.0, -0.4, JR_ELBOW_Z]))
        return p

    def equip(J, v, u):
        hl, hr = J.p['handL'], J.p['handR']
        d = rope_dir(u)
        mid, half = (hl + hr) / 2, (hr[2] - hl[2]) / 2

        def at(s):
            c, sn = math.cos(math.pi * s), math.sin(math.pi * s)
            p = mid + (hr - hl) * (s - 0.5)
            p[2] = mid[2] - half * c * (1.0 + JR_WIDE * sn)
            return p + d * (radius * sn ** JR_FLAT)

        pts = [at(i / 28) for i in range(29)]
        # every stretch of the rope by its own depth: behind the figure (nearer this camera) it
        # covers the body, in front of it the body covers it, and along the arms it changes over
        # as the rope sweeps past them rather than all at once
        items = [Item(Cone(v.cam.p(a), v.cam.p(b), 0.9), 'metal', depth=v.cam.depth((a + b) / 2),
                      collider=('capsule', a, b, 0.9), grip=True, spec3d=[])
                 for a, b in zip(pts, pts[1:])]
        # 3D: the whole rope on the first stretch, through the same curve in 16 segments
        items[0].spec3d = eq.rope3d([at(i / 16) for i in range(17)], 0.9, 'metal')
        return items

    return pose, Cycle(0.5, 9), equip            # 9 skips: the framing samples catch the rope's top


# ---- jumping jacks (hiit), front view ----------------------------------------------------------

def bump(u, c, w):
    x = (u - c) / w
    return max(0.0, 1.0 - x * x)


@exercise('hiitTraining', 'cardio', 'front', muscles=['delts', 'abductors', 'quads'])
def hiit_training():
    def pose(u):
        w = smooth(0.08, 0.42, u) - smooth(0.58, 0.92, u)
        half = lerp(9.5, 34.0, w)
        air = bump(u, 0.25, 0.17) + bump(u, 0.75, 0.17)
        ay = ANKLE_H + 6.0 * air
        dip = bump(u, 0.0, 0.13) + bump(u, 1.0, 0.13) + bump(u, 0.5, 0.13)
        leg = 86.4 - 3.2 * dip
        lat = half - HIP_HALF
        py = ay + math.sqrt(leg * leg - lat * lat)
        p = {'pelvis': v3(0.0, py, 0.0), 'pitch': 1.0}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(0.0, ay, sg * half), 'foot_pitch': -16.0 * min(air, 1.0),
                            'toe_out': lerp(6.0, 16.0, w), 'pole': v3(1.0, 0.0, 0.3 * sg)}
            p['arm' + s] = {'flex': 4.0, 'abd': lerp(12.0, 176.0, w), 'elbow': lerp(8.0, 12.0, w)}
        return p

    return pose, Cycle(1.0, 4), None


# ---- battle ropes ------------------------------------------------------------------------------

@exercise('battleRopes', 'cardio', 'side', muscles=['delts', 'forearms', 'abs'])
def battle_ropes():
    P = v3(-10.0, 80.0, 0.0)
    anchor = np.array([150.0, 9.0])
    hand0 = np.array([46.0, 90.0])
    amp, waves, grip_z = 14.0, 1.6, 22.0

    def phase(u, s):
        return 2 * math.pi * u + (0.0 if s == 'R' else math.pi)

    def hand(u, s):
        ph = phase(u, s)
        return hand0 + np.array([2.5 * math.cos(ph), amp * math.sin(ph)])

    def pose(u):
        p = {'pelvis': P + v3(0.0, 0.6 * math.cos(4 * math.pi * u), 0.0), 'pitch': 25.0, 'neck': 14.0}
        p.update(feet(0.0, 14.0, 10.0))
        hr, hl = hand(u, 'R'), hand(u, 'L')
        p.update(arms_ik(v3(hl[0], hl[1], -grip_z), v3(hr[0], hr[1], grip_z),
                         [-0.6, -1.0, -0.5], [-0.6, -1.0, 0.5]))
        return p

    def rope_at(u, s, k):
        ph = phase(u, s)
        b = hand0 + (anchor - hand0) * k
        a = (1 - k) ** 0.8
        return V(b[0] + 2.5 * math.cos(ph) * (1 - k), b[1] + amp * a * math.sin(ph - 2 * math.pi * waves * k))

    def rope(u, s):
        return polyline([rope_at(u, s, i / 32) for i in range(33)], 1.5)

    # 3D: each rope runs from its hand to the far side of the anchor post, where the two halves meet
    # round it, through the same wave in 14 segments
    post_r = 4.2
    end_z = math.sqrt(post_r ** 2 - 3.0 ** 2)

    def rope3(u, s):
        sg = 1.0 if s == 'R' else -1.0
        return eq.rope3d([p3(rope_at(u, s, i / 14), sg * lerp(grip_z, end_z, i / 14)) for i in range(15)], 1.5, 'metal')

    def equip(J, v, u):
        post = Union([Cone(V(anchor[0] + 3.0, 1.5), V(anchor[0] + 3.0, 15.0), 4.2),
                      Cone(V(anchor[0] - 8.0, 1.6), V(anchor[0] + 14.0, 1.6), 1.6)])
        # 3D: the anchor post on a round base plate
        post3 = (eq.rod3d(v3(anchor[0] + 3.0, 1.5), v3(anchor[0] + 3.0, 15.0), post_r, 'frame')
                 + eq.cyl3d(v3(anchor[0] + 3.0, 1.6), Y, 11.0, 1.6, 'frame'))
        return [Item(post, 'frame', 'back', spec3d=post3),
                Item(rope(u, 'L'), 'metal', ('before', 'armL'), spec3d=rope3(u, 'L')),
                Item(rope(u, 'R'), 'metal', ('before', 'armR'), spec3d=rope3(u, 'R'))]

    return pose, Cycle(0.5, 8), equip


# ---- swimming (freestyle) ------------------------------------------------------------------------

class Loop:
    """Closed Catmull-Rom curve through (t, point) keys, t in [0, 1)."""

    def __init__(self, keys):
        self.t = [k[0] for k in keys]
        self.p = [np.asarray(k[1], float) for k in keys]

    def __call__(self, t):
        t = t % 1.0
        n = len(self.t)
        ts = self.t + [self.t[0] + 1.0]
        i = max(j for j in range(n) if ts[j] <= t)
        t0, t1 = ts[i], ts[i + 1]
        p0, p1 = self.p[i], self.p[(i + 1) % n]
        tp, pp = self.t[i - 1] - (1.0 if i == 0 else 0.0), self.p[i - 1]
        tn = ts[(i + 2)] if i + 2 <= n else self.t[(i + 2) % n] + 1.0
        pn = self.p[(i + 2) % n]
        m0 = (p1 - pp) / (t1 - tp)
        m1 = (pn - p0) / (tn - t0)
        h = t1 - t0
        u = (t - t0) / h
        u2, u3 = u * u, u * u * u
        return ((2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * h * m0
                + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * h * m1)


WATER_Y = 47.0
SWIM_LANE = 40.0            # 3D: half the width of the water's surface


@exercise('swimming', 'cardio', 'side', muscles=['lats', 'delts', 'triceps'], floor=False)
def swimming():
    from ..rig import Frame
    SY = 38.0
    P_PITCH = 86.0
    # hand path relative to its shoulder (x towards the head, y up, |z|), one stroke from the entry;
    # the push finishes beside the thigh, brushing it rather than passing through the hip
    stroke = Loop([(0.00, (40.0, 4.0, 16.0)), (0.12, (56.0, -6.0, 14.0)), (0.30, (40.0, -30.0, 9.0)),
                   (0.45, (6.0, -40.0, 6.0)), (0.58, (-34.0, -28.0, 12.0)), (0.66, (-50.0, -4.0, 19.0)),
                   (0.80, (-16.0, 11.0, 27.0)), (0.92, (24.0, 10.0, 24.0))])

    def roll(u):
        return 32.0 * math.sin(2 * math.pi * (u - 0.55))      # right side up while the right arm recovers

    def pose(u):
        P = v3(0.0, SY, 0.0)
        r = roll(u)
        p = {'pelvis': P, 'p_pitch': P_PITCH, 'p_yaw': 0.45 * r, 'yaw': 0.55 * r, 'neck': 4.0}
        tf = Frame().orient(P_PITCH, 0.0, 0.45 * r).orient(0.0, 0.0, 0.55 * r)
        sc = P + tf.u * TORSO
        for s, ph, sg in (('R', u, 1.0), ('L', u + 0.5, -1.0)):
            S = sc + tf.r * (sg * SHOULDER_HALF)
            h = stroke(ph)
            pull = 0.5 - 0.5 * math.cos(2 * math.pi * (ph - 0.87))    # 1 mid-pull, 0 mid-recovery
            p['arm' + s] = {'hand': v3(S[0] + h[0], S[1] + h[1], sg * h[2]),
                            'pole': v3(0.0, 1.0, 0.8 * sg * pull)}   # elbow out while pulling, up on recovery
            k = 6 * math.pi * u + (0.0 if s == 'R' else math.pi)
            p['leg' + s] = {'hip': 3.0 + 11.0 * math.sin(k), 'abd': 2.0,
                            'knee': 14.0 + 12.0 * math.sin(k + 1.3), 'ankle': 50.0}
        return p

    def equip(J, v, u):
        items = []
        for y, amp, ofs in ((WATER_Y, 1.6, 0.0), (WATER_Y - 17.0, 1.3, 0.5)):
            pts = [V(x, y + amp * math.sin(2 * math.pi * (x / 40.0 + u + ofs))) for x in np.linspace(-104.0, 128.0, 59)]
            # 3D, behind the swimmer from every side (backdrops): the surface is a sheet of water the
            # line's length and a lane wide, edge-on from the side, where it is the line again; the
            # lower line a rod down the middle of the lane under it
            if y == WATER_Y:
                spec = eq.box3d(v3(12.0, y), X, Y, Z, 116.0, 1.1, SWIM_LANE, 1.1, 'water', 'back')
            else:
                spec = eq.rod3d(v3(-104.0, y), v3(128.0, y), 1.1, 'water', 'back')
            items.append(Item(polyline(pts, 1.1), 'water', 'back', spec3d=spec))
        return items

    return pose, Cycle(1.5, 3), equip


# ---- sequenced moves (burpees, box jumps) ---------------------------------------------------------

class Seq:
    """A loop of timed segments; each maps its local time (0..1, linear) to a pose, so every
    phase chooses its own easing (ballistic flight, accelerating push-off, ...)."""

    def __init__(self, segs):
        self.segs = segs
        self.total = sum(d for d, _ in segs)

    def __call__(self, u):
        t = (u % 1.0) * self.total
        for d, fn in self.segs:
            if t < d:
                return fn(t / d)
            t -= d
        return self.segs[-1][1](1.0)


def ease_in(t):
    return t * t


def ease_out(t):
    return 1.0 - (1.0 - t) * (1.0 - t)


def legs_flat(pose, x, half=12.0, y=ANKLE_H, pitch=0.0, pole=(1.0, 0.0, 0.25), toe_out=6.0):
    for s, sg in (('L', -1.0), ('R', 1.0)):
        a = planted_ankle(x, pitch) if y <= ANKLE_H + 1e-6 else np.array([x, y])
        pose['leg' + s] = {'foot': v3(a[0], max(a[1], y), sg * half), 'foot_pitch': pitch, 'toe_out': toe_out,
                           'pole': v3(pole[0], pole[1], pole[2] * sg)}
    return pose


def palms(pose, wrist_r, pole_r, palm_dir):
    pose.update(both(wrist_r, pole_r, palm=True, palm_dir=palm_dir))
    return pose


def within_reach(pose, margin=0.4):
    """Pull IK hand targets that are out of reach back onto the arm's reach sphere."""
    from ..rig import solve
    J = solve(pose)
    for s in 'LR':
        arm = pose.get('arm' + s, {})
        if 'hand' not in arm:
            continue
        L = (UPPER + (FORE_WRIST if arm.get('palm') else FORE)) - margin
        S = J.p['shoulder' + s]
        d = np.asarray(arm['hand'], float) - S
        n = np.linalg.norm(d)
        if n > L:
            arm['hand'] = S + d * (L / n)
    return pose


def arm_arc(pose, alpha, grip=21.0, reach=55.5):
    """Wrist targets on an arc around the shoulders: alpha 0 = straight ahead, 90 = overhead."""
    S = shoulder_c(pose)
    a = math.radians(alpha)
    w = S + v3(math.cos(a), math.sin(a), 0.0) * math.sqrt(reach ** 2 - (grip - SHOULDER_HALF) ** 2)
    return v3(w[0], w[1], grip), v3(math.cos(a), math.sin(a), 0.0)


# burpee: squat, hands down, jump the feet back to a plank, jump them in, jump up reaching overhead
BP_WRIST = v3(40.0, 4.4, 22.0)
BP_HAND_POLE = [-0.75, 0.15, 0.65]
BP_SQUAT_S = v3(36.4, 60.7, 0.0)            # shoulders over the hands in the squat


def bp_plank():
    S = v3(BP_WRIST[0], BP_WRIST[1] + math.sqrt((UPPER + FORE_WRIST - 0.35) ** 2 - (BP_WRIST[2] - SHOULDER_HALF) ** 2))
    return S


@exercise('burpees', 'cardio', 'side', muscles=['quads', 'glutes', 'pecs'])
def burpees():
    S_plank = bp_plank()
    g = 0.3
    for _ in range(20):          # body line angle so the toes rest on the floor
        ank_y = R_TOE + 4.8 * math.sin(g) + 14.6 * math.cos(g)
        g = math.asin((S_plank[1] - ank_y) / (TORSO + LEG * 0.999))
    gd = math.degrees(g)
    line = v3(math.cos(g), math.sin(g), 0.0)
    P_plank = S_plank - line * TORSO
    A_plank = P_plank - line * (LEG * 0.999)

    def stand():
        p = {'pelvis': v3(0.5, HIP_H - 0.6, 0.0), 'pitch': 0.0, 'neck': 0.0}
        legs_flat(p, 0.0)
        return palms(p, v3(2.0, SH_Y - UPPER - FORE_WRIST + 0.8, 21.0), [-1.0, 0.0, 0.3], v3(0.1, -1.0, 0.0))

    def squat(pitch=65.0, S=BP_SQUAT_S):
        p = {'pelvis': S - v3(math.sin(math.radians(pitch)), math.cos(math.radians(pitch)), 0.0) * TORSO,
             'pitch': pitch, 'neck': 22.0}
        legs_flat(p, 0.0, pole=(1.0, 0.0, 0.0))      # knees over the feet, inside the arms
        return palms(p, BP_WRIST, BP_HAND_POLE, X)

    def plank():
        p = {'pelvis': P_plank, 'pitch': 90.0 - gd, 'neck': 14.0}
        for s, sg in (('L', -1.0), ('R', 1.0)):
            p['leg' + s] = {'foot': v3(A_plank[0], A_plank[1], sg * 9.0), 'foot_pitch': gd - 90.0,
                            'toe_out': 0.0, 'pole': v3(0.0, -1.0, 0.0)}
        return palms(p, BP_WRIST, BP_HAND_POLE, X)

    STAND, SQUAT, PLANK = stand(), squat(), plank()

    def jump_back(t, reverse=False):
        e = ease(t)
        e = 1.0 - e if reverse else e
        arc = 4.0 * e * (1.0 - e)
        S = lerp(BP_SQUAT_S, S_plank, e)
        pitch = lerp(65.0, 90.0 - gd, e) + 14.0 * arc
        p = blend(SQUAT, PLANK, e)
        p['pelvis'] = S - v3(math.sin(math.radians(pitch)), math.cos(math.radians(pitch)), 0.0) * TORSO
        p['pitch'] = pitch
        for s in 'LR':
            f = np.array(p['leg' + s]['foot'], float)
            f[1] += 20.0 * arc
            p['leg' + s]['foot'] = f
        return p

    def loaded():
        p = {'pelvis': v3(-9.0, 66.0, 0.0), 'pitch': 35.0, 'neck': 10.5}
        legs_flat(p, 0.0, pole=(1.0, 0.0, 0.0))      # the hands come up outside the knees
        w, d = arm_arc(p, -76.0)
        return palms(p, w, [-1.0, 0.0, 0.4], d)

    LOADED = loaded()

    def jump(t, up=True):
        """Up: loaded crouch -> apex, reaching overhead. Down: apex -> landing crouch."""
        e = ease(t)
        if up:
            py = lerp(66.0, 110.0, e)
            px = lerp(-9.0, 1.0, e)
            pitch = lerp(35.0, -2.0, e)
            alpha = lerp(-76.0, 72.0, ease(min(t * 1.15, 1.0)))
            fp = -34.0 * smooth(0.3, 0.72, t)
        else:
            py = lerp(110.0, HIP_H - 9.0, e)
            px = lerp(1.0, 0.0, e)
            pitch = lerp(-2.0, 12.0, e)
            alpha = lerp(72.0, 12.0, e)
            fp = -34.0 * (1.0 - smooth(0.25, 0.6, t))
        p = {'pelvis': v3(px, py, 0.0), 'pitch': pitch, 'neck': 0.3 * pitch}
        ground = planted_ankle(0.0, fp)
        dz = 12.0 - HIP_HALF
        ay = max(ground[1], py - math.sqrt((LEG * 0.992) ** 2 - (px - ground[0]) ** 2 - dz * dz))
        ax = ground[0]
        spread = 0.25 * e if up else 0.25                # knees over the feet from the crouch
        for s, sg in (('L', -1.0), ('R', 1.0)):
            p['leg' + s] = {'foot': v3(ax, ay, sg * 12.0), 'foot_pitch': fp, 'toe_out': 6.0,
                            'pole': v3(1.0, 0.0, spread * sg)}
        w, d = arm_arc(p, alpha)
        pole = lerp(v3(-1.0, 0.0, 0.4), v3(-0.6, 0.0, 1.0), e) if up else v3(-0.6, 0.0, 1.0)
        return palms(p, w, list(pole), d)

    LAND = jump(1.0, up=False)

    rep_ = [(0.1, lambda t: STAND),
            (0.5, lambda t: within_reach(blend(STAND, SQUAT, ease(t)))),
            (0.35, lambda t: jump_back(t)),
            (0.14, lambda t: PLANK),
            (0.35, lambda t: jump_back(t, reverse=True)),
            (0.28, lambda t: within_reach(blend(SQUAT, LOADED, ease(t)))),
            (0.34, lambda t: jump(t)),
            (0.28, lambda t: jump(t, up=False)),
            (0.26, lambda t: within_reach(blend(LAND, STAND, ease(t))))]
    seq = Seq(rep_ * 2)
    return seq, Cycle(seq.total, 1), None


# box jump: dip, swing, jump onto the box, stand tall, step down backwards one foot at a time
BOX_TOP = 45.0
BOX_C = v3(57.0, BOX_TOP / 2, 0.0)         # front face at x = 32
FLOOR_X = 2.0
BOX_X = 46.0


@exercise('boxJumps', 'cardio', 'side', muscles=['quads', 'glutes', 'calves'])
def box_jumps():
    on_box = np.array([BOX_X, BOX_TOP + ANKLE_H])
    on_floor = np.array([FLOOR_X, ANKLE_H])
    toe_off = planted_ankle(FLOOR_X, -34.0)

    def body(px, py, pitch, flex, elbow=10.0):
        p = {'pelvis': v3(px, py, 0.0), 'pitch': pitch, 'neck': 0.4 * pitch}
        for s in 'LR':
            p['arm' + s] = {'flex': flex, 'abd': 7.0, 'elbow': elbow}
        return p

    def foot(p, s, a, fp=0.0, margin=None):
        sg = 1.0 if s == 'R' else -1.0
        if margin is not None:                        # a stepping foot keeps clear of floor and box
            ground = BOX_TOP if (a[0] + 17.6 > BOX_C[0] - 25.0 and a[1] > BOX_TOP + 3.0) else 0.0
            fp = clear_pitch(a[1] - ground, fp, margin)
        p['leg' + s] = {'foot': v3(a[0], a[1], sg * 12.0), 'foot_pitch': fp, 'toe_out': 6.0,
                        'pole': v3(1.0, 0.0, 0.2 * sg)}
        return p

    def both_feet(p, a, fp=0.0):
        return foot(foot(p, 'L', a, fp), 'R', a, fp)

    STAND = both_feet(body(FLOOR_X + 0.5, HIP_H - 0.6, 0.0, 0.0), on_floor)
    DIP = both_feet(body(-10.0, 74.0, 38.0, -50.0), on_floor)
    TOP = both_feet(body(BOX_X + 0.5, BOX_TOP + HIP_H - 0.6, 0.0, 0.0), on_box)

    def push(t):
        e = ease_in(t)
        p = body(lerp(-10.0, 0.0, e), lerp(74.0, 101.0, e), lerp(38.0, 12.0, e), lerp(-50.0, 22.0, ease_in(t)))
        fp = -34.0 * smooth(0.4, 1.0, t)
        return both_feet(p, planted_ankle(FLOOR_X, fp), fp)

    # the tucked feet pass over the box's front edge with their toes clear of it
    tuck = Spline([0.0, 0.5, 1.0], [toe_off, np.array([24.0, 68.0]), on_box],
                  np.array([10.0, 60.0]), np.array([10.0, -40.0]))

    def flight(t):
        p = body(lerp(0.0, 36.0, t), lerp(101.0, 116.0, t) + 72.0 * t * (1 - t), lerp(12.0, 24.0, t),
                 lerp(22.0, 75.0, ease_out(t)))
        return both_feet(p, tuck(t), keyed(t, ((0.0, -34.0), (0.4, -12.0), (1.0, 0.0))))

    def absorb(t):
        e = ease_out(t)
        p = body(lerp(36.0, 38.0, e), lerp(116.0, 109.0, e), lerp(24.0, 30.0, e), lerp(75.0, 60.0, e))
        return both_feet(p, on_box)

    ABSORBED = absorb(1.0)

    step_r = Spline([0.0, 0.3, 0.65, 1.0], [on_box, np.array([40.0, 66.0]), np.array([12.0, 50.0]), on_floor],
                    np.zeros(2), np.zeros(2))
    step_l = Spline([0.0, 0.35, 0.7, 1.0], [on_box, np.array([38.0, 64.0]), np.array([10.0, 40.0]), on_floor],
                    np.zeros(2), np.zeros(2))

    def step_down_r(t):
        e = ease(t)
        p = body(lerp(BOX_X + 0.5, 24.0, e), lerp(BOX_TOP + HIP_H - 0.6, 91.0, e), lerp(0.0, 22.0, e),
                 lerp(0.0, 28.0, e))
        foot(p, 'L', on_box)
        return foot(p, 'R', step_r(e), keyed(t, ((0.0, 0.0), (0.3, -8.0), (0.75, -12.0), (1.0, 0.0))),
                    swing_margin(t, 0.3))

    def step_down_l(t):
        e = ease(t)
        p = body(lerp(24.0, FLOOR_X + 0.5, e), lerp(91.0, HIP_H - 0.6, e), lerp(22.0, 0.0, e), lerp(28.0, 0.0, e))
        foot(p, 'R', on_floor)
        return foot(p, 'L', step_l(e), keyed(t, ((0.0, 0.0), (0.3, -8.0), (0.75, -12.0), (1.0, 0.0))),
                    swing_margin(t, 0.3))

    rep_ = [(0.08, lambda t: STAND),
            (0.36, lambda t: blend(STAND, DIP, ease(t))),
            (0.2, push),
            (0.36, flight),
            (0.22, absorb),
            (0.36, lambda t: blend(ABSORBED, TOP, ease(t))),
            (0.12, lambda t: TOP),
            (0.55, step_down_r),
            (0.45, step_down_l)]
    seq = Seq(rep_ * 2)

    def equip(J, v, u):
        return eq.plyo_box(v, BOX_C, hx=25.0, hy=BOX_TOP / 2, hz=35.0)

    return seq, Cycle(seq.total, 1), equip


# ---- sled pull: facing the sled, hand over hand while stepping backwards --------------------------

SLED_HITCH = np.array([140.0, 13.0])
SLED_REACH = np.array([30.0, 100.0])        # where a hand grabs the rope
SLED_Z = 22.0                               # 3D: the runners, each side of the deck


def sled(v):
    frame = Union([Cone(V(140.0, 2.0), V(194.0, 2.0), 2.0), Cone(V(140.0, 2.0), V(133.0, 9.0), 2.0),
                   RBox(V(167.0, 7.5), 26.0, 3.2, 2.0)])
    plates = Union([RBox(V(167.0, 14.5), 23.0, 3.0, 2.2), RBox(V(167.0, 21.0), 23.0, 3.0, 2.2)])
    post = Cone(V(167.0, 10.0), V(167.0, 42.0), 2.2)
    # 3D: the deck on two runners, each turned up at the front, a hitch at the deck's front edge for
    # the rope; the loading post up the middle, two plates lying flat round it
    frame3 = (eq.box3d(v3(167.0, 7.5), X, Y, Z, 26.0, 3.2, SLED_Z + 2.0, 2.0, 'frame')
              + eq.rod3d(v3(141.5, 9.0), p3(SLED_HITCH), 1.2, 'frame'))
    for sg in (-1.0, 1.0):
        frame3 += (eq.rod3d(v3(140.0, 2.0, sg * SLED_Z), v3(194.0, 2.0, sg * SLED_Z), 2.0)
                   + eq.rod3d(v3(140.0, 2.0, sg * SLED_Z), v3(133.0, 9.0, sg * SLED_Z), 2.0))
    plates3 = eq.cyl3d(v3(167.0, 14.5), Y, 23.0, 3.0, 'plate_rim') + eq.plate3d(v3(167.0, 21.0), Y, 23.0, 3.0, gap=False)
    return [Item(frame, 'frame', 'back', spec3d=frame3),
            Item(post, 'metal', 'back', spec3d=eq.rod3d(v3(167.0, 10.0), v3(167.0, 42.0), 2.2, 'metal')),
            Item(plates, 'plate_rim', 'back', spec3d=plates3)]


@exercise('sledPull', 'back', 'side', muscles=['lats', 'biceps', 'forearms'])
def sled_pull():
    g = Tread(travel=-28.0, duty=0.66, x0=4.0, hip_x=-4.0, half=11.0, height=HIP_H - 5.0, lean=-13.0,
              neck=-6.0, roll=((0.0, -12.0), (0.22, 0.0), (0.62, 0.0), (1.0, 12.0)),
              via=((0.5, 0.0, 10.0),), relax=0.0, prep=0.3)
    d = unit(SLED_REACH - SLED_HITCH)               # along the rope, towards the puller
    up = np.array([-d[1], d[0]])
    if up[1] < 0:
        up = -up
    A = SLED_REACH
    B = A + d * 32.0                                  # end of a pull, in front of the chest
    hold = 0.56
    swing = 0.2                                       # of a cycle: the slack swinging to the other hand

    def hand(p):
        """Hand on (or returning above) the rope at its own phase p: 0 = grab at A."""
        if p < hold:
            return A + (B - A) * ease(p / hold), True
        e = ease((p - hold) / (1 - hold))
        return B + (A - B) * e + up * 9.0 * math.sin(math.pi * e), False

    def pose(u):
        p = g.pose(u, arms=False)
        hr, _ = hand(u)
        hl, _ = hand((u + 0.5) % 1.0)
        p.update(arms_ik(v3(hl[0], hl[1], -4.0), v3(hr[0], hr[1], 4.0), [-0.3, -1.0, -0.5], [-0.3, -1.0, 0.5]))
        return p

    def equip(J, v, u):
        held = [(h, on) for h, on in (hand(u), hand((u + 0.5) % 1.0)) if on]
        held.sort(key=lambda it: -np.dot(it[0] - A, -d))      # the one nearest the sled first
        rear = held[-1][0] if held else B
        # a hand lets go at the end of its pull (at B): the slack it held swings over to the other hand
        since = min((u - hold) % 1.0, (u + 0.5 - hold) % 1.0)
        top = B + (rear - B) * ease(min(since / swing, 1.0))
        pts = [V(*SLED_HITCH)] + [V(*h) for h, _ in held] + ([V(*top)] if since < swing else [])
        c0, c1, c2 = top, top + np.array([14.0, -40.0]), np.array([30.0, 1.4])
        slack = [V(*((1 - s) ** 2 * c0 + 2 * (1 - s) * s * c1 + s * s * c2)) for s in np.linspace(0.0, 1.0, 12)]
        slack += [V(46.0, 1.4)]
        rope = Union([polyline(pts, 1.1), polyline(slack, 1.1)])
        # the rope runs down the midline, between the hands and the knees: in front of the far leg
        # and arm, behind the body and the near leg
        cols = [('capsule', v3(a[0], a[1], 0.0), v3(b[0], b[1], 0.0), 1.1)
                for line in (pts, slack) for a, b in zip(line, line[1:])]
        # 3D: one rope from the hitch through both holding hands (the one hand twice when only one
        # holds: they lie on one straight line, so it never kinks) and down to the floor
        hs = [h for h, _ in held] or [rear]
        line3 = [SLED_HITCH] + (hs * 2)[:2] + slack
        return sled(v) + [Item(rope, 'plate_rim', ('before', 'base'), collider=cols, grip=True,
                               spec3d=eq.rope3d([p3(q) for q in line3], 1.1, 'plate_rim'))]

    return pose, Cycle(1.2, 4), equip


# ---- shuttle run: sprint, brake, plant and touch the floor, drive off, sprint again -----------------

def cr(t, keys):
    """Catmull-Rom through scalar (t, value) keys, held flat beyond the ends."""
    ts = [k[0] for k in keys]
    vs = [k[1] for k in keys]
    if t <= ts[0]:
        return vs[0]
    if t >= ts[-1]:
        return vs[-1]
    i = max(j for j in range(len(ts) - 1) if ts[j] <= t)
    t0, t1, v0, v1 = ts[i], ts[i + 1], vs[i], vs[i + 1]
    m0 = (v1 - vs[i - 1]) / (t1 - ts[i - 1]) if i > 0 else (v1 - v0) / (t1 - t0)
    m1 = (vs[i + 2] - v0) / (ts[i + 2] - t0) if i + 2 < len(ts) else (v1 - v0) / (t1 - t0)
    h = t1 - t0
    u = (t - t0) / h
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * h * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * h * m1


class Footfalls:
    """One foot's explicit contacts over a loop of T seconds: (t_on, t_off, x keys, roll keys).
    In contact the flat-foot ankle x follows the keys (the belt may brake and start again) while the
    foot rolls heel -> toes on the floor; between contacts it swings on a Hermite path through the
    via points (s, x, y), leaving and meeting the belt with its velocity."""

    def __init__(self, T, contacts, vias):
        self.T, self.c = T, contacts
        n = len(contacts)
        self.sw = []
        for i in range(n):
            a, b = contacts[i], contacts[(i + 1) % n]
            t1, t2 = a[1], b[0] + (T if i == n - 1 else 0.0)
            d = t2 - t1
            ts = [0.0] + [w[0] for w in vias[i]] + [1.0]
            ps = [self._at(a, 1.0)] + [np.array([w[1], w[2]]) for w in vias[i]] + [self._at(b, 0.0)]
            self.sw.append((t1, t2, Spline(ts, ps, self._vel(a, 1.0) * d, self._vel(b, 0.0) * d),
                            a[3][-1][1], b[3][0][1]))

    def _at(self, c, tau):
        return planted_ankle(cr(tau, c[2]), keyed(tau, c[3]))

    def _vel(self, c, tau, eps=1e-4):
        d = c[1] - c[0]
        if tau >= 1.0:
            return (self._at(c, 1.0) - self._at(c, 1.0 - eps)) / (eps * d)
        return (self._at(c, tau + eps) - self._at(c, tau)) / (eps * d)

    def at(self, t):
        """(ankle, pitch or None, in contact?, swing progress, (pitch at lift-off, at landing))."""
        t = t % self.T
        for c in self.c:
            if c[0] <= t < c[1]:
                tau = (t - c[0]) / (c[1] - c[0])
                return self._at(c, tau), keyed(tau, c[3]), True, 0.0, None
        for t1, t2, sp, fa, fb in self.sw:
            tt = t if t >= t1 else t + self.T
            if t1 <= tt < t2:
                s = (tt - t1) / (t2 - t1)
                return sp(s), None, False, s, (fa, fb)
        c = min(self.c, key=lambda c: min(abs(t - c[0]), abs(t + self.T - c[0]), abs(t - self.T - c[0])))
        return self._at(c, 0.0), keyed(0.0, c[3]), True, 0.0, None     # rounding at a landing

    def phase(self, t):
        """How far from the latest landing to the next (0..1), for the opposite arm's swing."""
        t = t % self.T
        ons = [c[0] for c in self.c]
        for i, a in enumerate(ons):
            b = ons[i + 1] if i + 1 < len(ons) else ons[0] + self.T
            tt = t if t >= a else t + self.T
            if a <= tt < b:
                return (tt - a) / (b - a)
        return 0.0


@exercise('shuttleRun', 'cardio', 'side', muscles=['quads', 'glutes', 'calves'])
def shuttle_run():
    from ..rig import solve
    T = 3.5
    SR = ((0.0, -6.0), (0.3, -2.0), (0.45, -4.0), (1.0, -44.0))       # sprint foot roll
    run = [(0.0, 21.0), (1.0, -53.0)]
    sv = ((0.28, -52.0, 58.0), (0.64, 24.0, 52.0))                     # sprint swing
    feet_ = {
        'R': Footfalls(T, [(0.0, 0.168, run, SR), (0.56, 0.728, run, SR),
                           (1.12, 1.36, [(0.0, 25.0), (1.0, -24.0)], ((0.0, 4.0), (0.25, 0.0), (0.6, 0.0), (1.0, -34.0))),
                           (1.84, 2.64, [(0.0, 44.0), (0.3, 42.0), (0.7, 40.0), (0.83, 30.0), (1.0, 0.0)],
                            ((0.0, 12.0), (0.12, 0.0), (0.8, 0.0), (1.0, -40.0))),
                           (3.0, 3.17, [(0.0, 21.0), (1.0, -50.0)], SR)],
                       [sv, sv, ((0.3, -38.0, 44.0), (0.66, 36.0, 42.0)), ((0.3, -22.0, 44.0), (0.66, 28.0, 42.0)), sv]),
        'L': Footfalls(T, [(0.28, 0.448, run, SR), (0.84, 1.008, run, SR),
                           (1.44, 2.5, [(0.0, 22.0), (0.38, -34.0), (0.9, -38.0), (1.0, -46.0)],
                            ((0.0, 2.0), (0.15, 0.0), (0.32, -30.0), (0.9, -34.0), (1.0, -48.0))),
                           (2.76, 2.94, [(0.0, 20.0), (1.0, -34.0)], ((0.0, -2.0), (0.3, 0.0), (0.5, -4.0), (1.0, -42.0))),
                           (3.2, 3.368, run, SR)],
                       [sv, sv, ((0.35, -32.0, 40.0), (0.7, 24.0, 36.0)), ((0.3, -42.0, 46.0), (0.66, 26.0, 44.0)), sv]),
    }
    Lmax = LEG * 0.99
    touch = v3(54.0, R_HAND, 32.0)          # beside the front foot, the arm outside the knee

    def pose(u):
        t = u * T
        ws = 1.0 - smooth(1.0, 1.3, t) + smooth(2.95, 3.3, t)
        # the bob of the sprint after the turn counts back from the loop's end, so it meets the
        # opening sprint without a step (both lie outside the turn, where the bob isn't used)
        sprint_y = HIP_H - 3.0 - 2.4 * math.cos(4 * math.pi * ((t - (T if t > 2.2 else 0.0)) / 0.56 - 0.15))
        man_y = cr(t, [(1.0, 92.0), (1.4, 91.5), (1.84, 88.0), (2.1, 55.0), (2.32, 55.0), (2.64, 84.0),
                       (2.95, 92.0), (3.3, 92.0)])
        px = cr(t, [(0.0, 0.0), (1.1, 0.0), (1.5, -3.0), (1.85, 0.0), (2.1, 5.0), (2.35, 5.0), (2.64, 3.0),
                    (3.0, 0.0), (T, 0.0)])
        py = ws * sprint_y + (1 - ws) * man_y
        f = {s: feet_[s].at(t) for s in 'LR'}
        for s, sg in (('L', -1.0), ('R', 1.0)):
            a = f[s][0]
            dz = 10.0 - HIP_HALF
            py = smin(py, a[1] + math.sqrt(max(Lmax ** 2 - (a[0] - px) ** 2 - dz * dz, 0.0)), 3.0)
        pitch = cr(t, [(0.0, 13.0), (1.1, 13.0), (1.45, 4.0), (1.84, 8.0), (2.08, 72.0), (2.34, 72.0),
                       (2.66, 36.0), (3.0, 18.0), (3.3, 13.0), (T, 13.0)])
        w = smooth(1.98, 2.12, t) - smooth(2.3, 2.46, t)
        p = {'pelvis': v3(px, py, 0.0), 'pitch': pitch, 'neck': 0.5 * pitch, 'protract': 6.0 * w}
        # folded over the front thigh, the knee comes in over the foot, between the ribs and the
        # arm that reaches down outside it (turned out, it would sit in the armpit)
        fold = smooth(1.84, 2.05, t) - smooth(2.4, 2.64, t)
        for s, sg in (('L', -1.0), ('R', 1.0)):
            a, fp, st, sw, fps = f[s]
            pole = v3(1.0, 0.0, 0.15 * sg * (1.0 - 0.57 * fold))
            foot3 = v3(a[0], a[1], sg * 10.0)
            if not st:
                nat = shank_pitch(v3(px, py, sg * HIP_HALF), foot3, pole) - 22.0
                fp = lerp(fps[0], nat, smooth(0.0, 0.35, sw))
                fp = clear_pitch(a[1], lerp(fp, fps[1], smooth(0.7, 1.0, sw)), swing_margin(sw))
            p['leg' + s] = {'foot': foot3, 'foot_pitch': fp, 'pole': pole}
        amp = cr(t, [(0.0, 58.0), (1.1, 58.0), (1.5, 30.0), (1.84, 20.0), (2.4, 20.0), (2.8, 45.0), (3.2, 58.0),
                     (T, 58.0)])
        for s, other in (('R', 'L'), ('L', 'R')):
            c = math.cos(2 * math.pi * feet_[other].phase(t))
            p['arm' + s] = {'flex': 10.0 + amp * c, 'abd': 8.0, 'elbow': 92.0 + 18.0 * c * amp / 58.0}
        if w > 0.0:
            J = solve(p)
            H, E, S = J.p['handR'], J.p['elbowR'], J.p['shoulderR']
            p['armR'] = {'hand': lerp(H, touch, w), 'pole': E - (S + H) / 2}
            fl = p['armL']
            p['armL'] = {'flex': lerp(fl['flex'], -35.0, w), 'abd': 8.0, 'elbow': lerp(fl['elbow'], 50.0, w)}
        return p

    return pose, Cycle(T, 1), None

