"""Hinge pattern: deadlift family, good mornings, swings, hip thrusts, back extensions."""
from .common import *

PLATE_R = 22.5
# A bar pulled up the legs brushes them: its centre stays this far from the shank's axis, and from
# the knee and the thigh's axis (the body's capsules in clip.py plus the bar's radius, less the
# 1.7 cm a loaded bar presses in; the checker allows 2).
GRAZE_SHIN = 5.0
GRAZE_THIGH = 6.8
KNEES = 0.1         # knee pole outwards: knees over the toes, inside the arms of a conventional grip


def seg_dist(p, a, b):
    ab = b - a
    t = min(max(float(np.dot(p - a, ab) / max(np.dot(ab, ab), 1e-12)), 0.0), 1.0)
    return float(np.linalg.norm(p - (a + ab * t)))


def smin(a, b, k=2.0):
    """Smooth minimum: never above either, within k/2 of the smaller, no kink where they cross."""
    return (a + b - math.sqrt((a - b) ** 2 + k * k)) / 2


class DeadliftPath:
    """Bar path over mid-foot; the knees move back as the bar passes them, the hips finish.
    The shins lean forward no further than the bar allows: at every height it brushes the shins,
    the knees and the thighs in front of them (graze=False for handles beside the legs)."""

    def __init__(self, ankle_x=-7.5, shin0=14.0, arm_lead=4.5, bar_y0=PLATE_R, grip_z=22.0, ankle_y=ANKLE_H,
                 bar_x0=0.0, bar_dx=4.0, graze=True):
        self.A = ankle_x
        self.ay = ankle_y
        self.shin0, self.lead, self.y0 = shin0, arm_lead, bar_y0
        self.bx0, self.bdx = bar_x0, bar_dx
        self.graze = graze
        self.arm = math.sqrt(ARM ** 2 - (grip_z - SHOULDER_HALF) ** 2) - 0.05
        self.y_lock = self._lock()

    def bar_x(self, y):
        return self.bx0 + self.bdx * smooth(40.0, 80.0, y)

    def _chain(self, S, ph):
        K = v3(self.A, self.ay) + SHANK * v3(math.sin(ph), math.cos(ph))
        d = min(np.linalg.norm(S - K), THIGH + TORSO - 1e-6)
        ex = (S - K) / np.linalg.norm(S - K)
        a = (THIGH ** 2 - TORSO ** 2 + d * d) / (2 * d)
        h = math.sqrt(max(THIGH ** 2 - a * a, 0))
        base = K + ex * a
        ey = v3(-ex[1], ex[0])
        return K, min(base + ey * h, base - ey * h, key=lambda p: p[0])

    def _clear(self, B, S, ph):
        K, H = self._chain(S, ph)
        return min(seg_dist(B, v3(self.A, self.ay), K) - GRAZE_SHIN, seg_dist(B, K, H) - GRAZE_THIGH)

    def shin_limit(self, B, S):
        """The most the shins may lean (rad) with the bar at B still in front of the legs: leaning
        them further from upright, the first lean at which they reach the bar."""
        lo = math.radians(-8.0)
        if self._clear(B, S, lo) < 0.0:
            return lo
        step = math.radians(2.0)
        while lo < math.radians(40.0):
            hi = lo + step
            if self._clear(B, S, hi) < 0.0:
                for _ in range(24):
                    mid = (lo + hi) / 2
                    if self._clear(B, S, mid) >= 0.0:
                        lo = mid
                    else:
                        hi = mid
                return lo
            lo = hi
        return lo

    def solve(self, y):
        B = v3(self.bar_x(y), y)
        b = math.radians(lerp(self.lead, 0.0, smooth(self.y0, 78.0, y)))
        S = B + self.arm * v3(math.sin(b), math.cos(b))
        ph = math.radians(lerp(self.shin0, 1.0, smooth(self.y0, max(52.0, self.y0 + 12.0), y)))
        if self.graze:
            ph = smin(ph, self.shin_limit(B, S), math.radians(2.0))
        K, H = self._chain(S, ph)
        return B, S, K, H

    def _lock(self):
        lo, hi = 40.0, 110.0
        for _ in range(60):
            mid = (lo + hi) / 2
            B, S, K, _ = self.solve(mid)
            if np.linalg.norm(S - K) < THIGH + TORSO - 0.6:
                lo = mid
            else:
                hi = mid
        return lo


LIFT = Timeline([(0.6, 0, 0), (1.45, 0, 1), (0.55, 1, 1), (1.6, 1, 0)] * 2)


PLATE_Z = 72.7      # the loaded plates' middle along the bar (eq.barbell: 70 and 75.4, 2.5 thick)


def pull_from(path, grip_z=22.0, block=None, platform=None, knees=0.25):
    """Pose + equipment for a conventional pull along `path` (u: 0 = bar low, 1 = locked out).
    knees: the knee pole's outward part (KNEES keeps them over the toes; 0.25 pushes them out,
    where the grip leaves room). block: the plates start on blocks this tall."""
    def pose(u):
        y = lerp(path.y0, path.y_lock, u)
        B, S, K, H = path.solve(y)
        d = S - H
        th = math.degrees(math.atan2(d[0], d[1]))
        p = {'pelvis': H, 'pitch': th, 'neck': 0.12 * th}
        p.update(feet(path.A, 11.0, 6.0, y=path.ay))
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s]['pole'] = np.array([1.0, 0.0, knees * sg])
        p.update(both(v3(B[0], B[1], grip_z), [-0.2, -0.1, 1.0]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        items = []
        if block is not None:
            # one block under each plate: the near one stands in front of the legs
            for s in (-1.0, 1.0):
                c = v3(path.bar_x(path.y0), block / 2, s * PLATE_Z)
                half = [7.0, block / 2, 9.0]
                items.append(Item(eq.box3(v.cam, c, X, Y, Z, *half, 2.0), 'pad', gap=True, depth=v.cam.depth(c),
                                  collider=('box', c, [X, Y, Z], half),
                                  spec3d=eq.box3d(c, X, Y, Z, *half, 2.0, 'pad', True)))
        if platform is not None:
            # the lifter stands on it; the plates rest on the floor beyond its ends
            c = v3(path.A + 4.0, platform / 2, 0.0)
            items.append(Item(eq.box3(v.cam, c, X, Y, Z, 34.0, platform / 2, 40.0, 1.5), 'pad', 'back',
                              spec3d=eq.box3d(c, X, Y, Z, 34.0, platform / 2, 40.0, 1.5, 'pad')))
        return items + eq.barbell(v, v3(B[0], B[1], 0.0))

    return pose, equip


@exercise('deadlift', 'back', 'side', muscles=['erectors', 'glutes', 'hamstrings'])
def deadlift():
    pose, equip = pull_from(DeadliftPath(), knees=KNEES)
    return pose, LIFT, equip


@exercise('snatchGripDeadlift', 'back', 'side', muscles=['erectors', 'traps', 'glutes', 'hamstrings'])
def snatch_grip_deadlift():
    path = DeadliftPath(grip_z=56.0, shin0=17.0, arm_lead=3.0)
    pose, equip = pull_from(path, grip_z=56.0)
    return pose, LIFT, equip


@exercise('deficitDeadlift', 'back', 'side', muscles=['erectors', 'glutes', 'hamstrings'])
def deficit_deadlift():
    path = DeadliftPath(ankle_y=ANKLE_H + 7.0, shin0=17.0, arm_lead=3.0)
    # standing on the platform raises the knees to the elbows: the knees stay in, over the ankles
    pose, equip = pull_from(path, platform=7.0, knees=0.07)
    return pose, LIFT, equip


@exercise('rackPulls', 'back', 'side', muscles=['erectors', 'traps', 'glutes'])
def rack_pulls():
    path = DeadliftPath(bar_y0=50.0, shin0=4.0, arm_lead=2.0)
    pose, equip = pull_from(path, block=50.0 - PLATE_R, knees=KNEES)
    return pose, Timeline([(0.6, 0, 0), (1.2, 0, 1), (0.55, 1, 1), (1.4, 1, 0)] * 2), equip


@exercise('trapBarDeadlift', 'back', 'side', muscles=['quads', 'glutes', 'erectors'])
def trap_bar_deadlift():
    # the handles sit beside the body, so the shins may travel forward: more knee, taller torso
    path = DeadliftPath(ankle_x=-4.0, shin0=24.0, arm_lead=0.0, grip_z=30.0, bar_x0=1.5, bar_dx=0.0, graze=False)
    pose, _ = pull_from(path, grip_z=30.0)
    plate_z = 52.0      # the plates ride on sleeves out from the hexagon's side corners

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        near = 1.0 if v.cam.depth(Z) >= 0 else -1.0
        # beside the lifter: the near plate is in front of the hands and legs, the far one hidden
        # behind the figure (and the near plate)
        far = v3(B[0], B[1], -near * plate_z)
        plate = eq.plate_disc(v, v3(B[0], B[1], near * plate_z), Z, gap=True, depth=True)
        for it in plate:
            it.spec3d = []          # 3D: the whole bar below, the same from every side
        return (plate + [Item(None, 'plate', depth=-1e9, collider=('cylinder', far, Z, PLATE_R, 2.6)),
                         Item(None, 'metal', spec3d=trap_bar3d(B, plate_z))])

    return pose, LIFT, equip


TRAP_HEX = 42.0     # the trap bar's hexagon: centre to corner, its side corners on the sleeves' axis


def trap_bar3d(B, plate_z, grip_z=30.0):
    """The trap bar in 3D, centred on the hands' midpoint B: the hexagon round the lifter at hand
    height (corners out to the sides, where the sleeves carry a plate each), and a handle across it
    through each fist (hands at z = +-grip_z)."""
    c = np.asarray(B, float)
    ring = [c + v3(TRAP_HEX * math.sin(a), 0.0, TRAP_HEX * math.cos(a))
            for a in np.linspace(0.0, 2 * math.pi, 7)]
    # where the hexagon's front and back edges cross the handles' line
    hx = TRAP_HEX * math.sin(math.pi / 3) * (1.0 - (grip_z - TRAP_HEX / 2) / (TRAP_HEX / 2))
    spec = eq.rope3d(ring, 1.6, 'metal', True)
    for s in (-1.0, 1.0):
        spec += eq.rod3d(c + v3(-hx, 0.0, s * grip_z), c + v3(hx, 0.0, s * grip_z), 1.8, 'metal', True)
        spec += eq.cyl3d(c + Z * s * (TRAP_HEX + 12.0), Z, 2.6, 12.0, 'metal', True)
        spec += eq.plate3d(c + Z * s * plate_z, Z, PLATE_R, 2.6, gap=True)
    return spec


def leg_clear(B, A, K, H):
    """How far a bar at B (side-on) stays out of the legs: + = clear of the shins (GRAZE_SHIN from
    the ankle->knee line) and of the knees and thighs (GRAZE_THIGH from the knee->hip line)."""
    return min(seg_dist(B, A, K) - GRAZE_SHIN, seg_dist(B, K, H) - GRAZE_THIGH)


def graze_bar(S, reach, A, K, H):
    """The bar at the end of straight arms (reach, side-on) from the shoulder S, swung back from
    in front until it meets the legs: it slides along them, as a bar kept close does."""
    def bar(a):
        a = math.radians(a)
        return S + reach * v3(math.sin(a), -math.cos(a))
    a = 60.0
    while a > -30.0:
        b = a - 2.0
        if leg_clear(bar(b), A, K, H) < 0.0:
            for _ in range(24):
                mid = (a + b) / 2
                if leg_clear(bar(mid), A, K, H) < 0.0:
                    b = mid
                else:
                    a = mid
            return bar(a)
        a = b
    return bar(a)


@exercise('romanianDeadlift', 'back', 'side', muscles=['hamstrings', 'glutes', 'erectors'])
def romanian_deadlift():
    A = -6.0
    grip = 22.0
    reach = math.sqrt(ARM ** 2 - (grip - SHOULDER_HALF) ** 2) - 0.05

    def pose(u):
        th = lerp(2.0, 80.0, u)                           # hinge
        # soft knees, bending a little as the hips go back; the shins come to vertical
        ph = math.radians(lerp(2.0, 0.0, u))
        K = v3(A, ANKLE_H) + SHANK * v3(math.sin(ph), math.cos(ph))
        al = math.radians(lerp(8.0, 24.0, u)) - ph       # knee bend less the shin lean: the thigh's lean back
        H = K + THIGH * v3(-math.sin(al), math.cos(al))
        S = shoulder_at(H, th)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.15 * th}
        p.update(feet(A, 11.0, 6.0))
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s]['pole'] = np.array([1.0, 0.0, KNEES * sg])
        # straight arms; the bar slides down the thighs and shins, brushing them
        bar = graze_bar(S, reach, v3(A, ANKLE_H), K, H)
        p.update(both(v3(bar[0], bar[1], grip), [-0.2, -0.1, 1.0]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0))

    return pose, rep_down_first(1.8, 1.4, top=0.5, bottom=0.25), equip


@exercise('goodMornings', 'back', 'side', muscles=['hamstrings', 'glutes', 'erectors'])
def good_mornings():
    A = -6.0
    BAR_L = (-7.0, 53.5)

    def pose(u):
        th = lerp(6.0, 78.0, u)
        ph = math.radians(lerp(0.0, 8.0, u))
        K = v3(A, ANKLE_H) + SHANK * v3(math.sin(ph), math.cos(ph))
        # hips travel back to keep the bar over the feet
        B_off = torso_point(v3(0, 0), th, *BAR_L)
        hx = A + 4.0 - B_off[0] * 0.55
        dx = min(max((K[0] - hx) / THIGH, -1.0), 1.0)
        H = K + THIGH * v3(-dx, math.sqrt(1 - dx * dx))
        B = torso_point(H, th, *BAR_L)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.35 * th}
        p.update(feet(A, 12.0, 8.0))
        p.update(both(v3(B[0], B[1], 40.0), [-1.0, -0.7, 0.35]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)     # on the back: the face stays readable

    return pose, rep_down_first(1.7, 1.4, top=0.5, bottom=0.25), equip


@exercise('sumoDeadlift', 'back', 'front', muscles=['glutes', 'adductors', 'quads', 'erectors'])
def sumo_deadlift():
    A, half, grip = -6.0, 40.0, 17.0
    reach = math.sqrt(ARM ** 2 - (grip - SHOULDER_HALF) ** 2) - 0.05
    th0 = 50.0
    # the bar starts on the floor over mid-foot with the arms hanging straight down, which sets
    # how low the hips sit; locked out, the hips stand as tall as the wide stance lets the feet
    # stay planted, and the bar rests against the front of the thighs
    P0 = v3(A + 5.0 - TORSO * math.sin(math.radians(th0)), PLATE_R + reach - TORSO * math.cos(math.radians(th0)))
    P1 = v3(-1.0, HIP_H - 6.6)

    def pose(u):
        P = P0 + (P1 - P0) * u
        th = lerp(th0, 0.0, smooth(0.0, 1.0, u))
        p = {'pelvis': P, 'pitch': th, 'neck': 0.1 * th}
        # knees pushed out to the sides, so the bar rises in front of them
        knee_fwd = lerp(0.0, 0.3, smooth(0.0, 1.0, u))
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A, ANKLE_H, sg * half), 'toe_out': 32.0,
                            'pole': np.array([knee_fwd, 0.0, 1.0 * sg])}
        S = shoulder_at(P, th)
        bx = lerp(A + 5.0, P1[0] + 10.0, smooth(0.35, 1.0, u))
        bar = v3(bx, S[1] - math.sqrt(reach ** 2 - (S[0] - bx) ** 2), 0.0)
        p.update(both(v3(bar[0], bar[1], grip), [-0.3, 0.0, 1.0]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), z_front=('after', 'base'))

    return pose, LIFT, equip


@exercise('singleLegDeadlift', 'legs', 'side', muscles=['hamstrings', 'glutes'])
def single_leg_deadlift():
    A = -2.0

    def pose(u):
        th = lerp(3.0, 80.0, u)
        # stand on the far leg. The near foot rests beside it at the top; it lifts straight up off the
        # floor first, then the leg swings back in line with the torso (a soft knee), and once the
        # foot is clear its toes turn down, square to the leg
        P = v3(A + 1.0 - lerp(0.0, 10.0, u), HIP_H - lerp(0.8, 4.0, u))
        p = {'pelvis': P, 'pitch': th, 'neck': 0.1 * th}
        p['legL'] = {'foot': v3(A, ANKLE_H, -9.0), 'toe_out': 4.0, 'pole': np.array([1.0, 0.0, -0.1])}
        lean = math.radians((th - 3.0) * smooth(0.0, 0.12, u))
        hip = P + v3(0.0, 0.0, HIP_HALF)
        foot = hip + 86.4 * v3(-math.sin(lean), -math.cos(lean)) + v3(0.0, 3.0 * math.sin(math.pi * min(u / 0.2, 1.0)))
        p['legR'] = {'foot': v3(foot[0], foot[1], 9.0), 'toe_out': 4.0,
                     'foot_pitch': -(math.degrees(lean) + 10.0 * u) * smooth(0.15, 0.45, u),
                     'pole': np.array([math.cos(lean), -math.sin(lean), 0.1])}
        S = shoulder_at(P, th)
        # the dumbbells hang beside the thighs, not through them
        p.update(both(v3(S[0] + 2.0, S[1] - (ARM - 2.0), 25.0), [-1.0, 0.0, 0.3]))
        return p

    def equip(J, v, u):
        items = []
        for s in 'LR':
            items += eq.dumbbell(v, J.p['hand' + s], X, ('before', 'arm' + s))
        return items

    return pose, rep_down_first(1.7, 1.4, top=0.5, bottom=0.3), equip


@exercise('kettlebellSwings', 'legs', 'side', muscles=['glutes', 'hamstrings'])
def kettlebell_swings():
    A = -6.0

    def pose(u):
        # u 0: hinged, bell back between the legs; 1: standing tall, bell at chest height
        th = lerp(58.0, 1.0, smooth(0.0, 0.75, u))
        ph = math.radians(lerp(12.0, 1.0, u))
        K = v3(A, ANKLE_H) + SHANK * v3(math.sin(ph), math.cos(ph))
        hx = A + 2.0 - TORSO * math.sin(math.radians(th)) * 0.62
        dx = min(max((K[0] - hx) / THIGH, -1.0), 1.0)
        H = K + THIGH * v3(-dx, math.sqrt(1 - dx * dx))
        p = {'pelvis': H, 'pitch': th, 'neck': 0.2 * th}
        p.update(feet(A, 18.0, 16.0))
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s]['pole'] = np.array([1.0, 0.0, 0.45 * sg])     # knees out over the toes
        # straight arms; world angle from hanging down: bell back between the legs -> chest height.
        # Both hands on the one handle: the arms close in from the shoulders to meet at it, so the
        # forearms pass inside the thighs on the backswing.
        a_world = lerp(-26.0, 86.0, u)
        for s in 'LR':
            p['arm' + s] = {'flex': a_world + th, 'abd': -12.5, 'elbow': 3.0}
        return p

    def equip(J, v, u):
        h = (J.p['handL'] + J.p['handR']) / 2
        e = (J.p['elbowL'] + J.p['elbowR']) / 2
        # on the midline: in front of the far leg, behind the near leg and the near hand
        return eq.kettlebell(v, h, unit(h - e), ('after', 'legL'))

    tl = Timeline([(0.5, 0, 1), (0.14, 1, 1), (0.5, 1, 0), (0.06, 0, 0)] * 3)
    return pose, tl, equip


# ---- bench- and machine-supported hinges ----------------------------------------------------

def crossed_arms(pelvis, pitch, along=36.0, out=15.0):
    """Hands crossed on the chest (both hands just in front of the sternum)."""
    c = torso_point(pelvis, pitch, out, along)
    return both(v3(c[0], c[1], 4.0), [0.2, -1.0, 0.8])


@exercise('hipThrust', 'legs', 'side', muscles=['glutes', 'hamstrings'])
def hip_thrust():
    bench_top = 42.0
    edge = -40.0
    S = v3(edge + 3.0, bench_top + 10.5)            # upper back on the bench edge
    BAR = (15.0, 4.5)       # the bar on the front of the pelvis (torso-local), above the thighs

    def pose(u):
        pitch = lerp(-52.0, -92.0, u)
        th = math.radians(pitch)
        up = v3(math.sin(th), math.cos(th))
        P = S - up * TORSO
        # chin tucked, eyes over the knees: the head stays clear of the bench as the hips rise
        p = {'pelvis': P, 'pitch': pitch, 'neck': lerp(-12.0, -28.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(S[0] + TORSO + 40.0, ANKLE_H, sg * 15.0), 'toe_out': 8.0,
                            'pole': np.array([0.5, 1.0, 0.25 * sg])}
        bar = torso_point(P, pitch, *BAR)
        p.update(both(v3(bar[0] - 3.0, bar[1] + 1.0, 30.0), [0.0, 1.0, 0.8]))
        return p

    def equip(J, v, u):
        P = J.p['pelvis']
        pitch = lerp(-52.0, -92.0, u)
        bar = torso_point(P, pitch, *BAR)
        return eq.bench(v, v3(edge - 30.0, bench_top, 0.0), length=60.0) + eq.barbell(v, v3(bar[0], bar[1], 0.0))

    return pose, rep(1.1, 1.4, top=0.35, bottom=0.45), equip


FOOT_HALF = 22.0    # 3D: a bench's posts stand on feet across it, as wide as its pad


def posts3d(tops, r=2.4, foot=FOOT_HALF):
    """3D: uprights on the midline from each (x, y) top down to the floor, each on a foot across
    the bench (seen side-on the foot is end-on, inside the post's foot)."""
    spec = []
    for x, y in tops:
        spec += eq.rod3d(v3(x, y, 0.0), v3(x, 1.0, 0.0), r, 'frame')
        spec += eq.rod3d(v3(x, 1.2, -foot), v3(x, 1.2, foot), 1.6, 'frame')
    return spec


def roller3d(c3, r, half=20.0):
    """3D: an ankle roller across both legs (what the 2D draws end-on), with the 2D roller's
    knockout band."""
    return eq.cyl3d(c3, Z, r, half, 'pad', True)


def roman_chair(v, hip, leg_dir, ankle, pad_from=14.0, pad_len=28.0, pad_off=8.8):
    """Thigh pad along the legs from pad_from below the hips to above the knees (its top pad_off
    from the legs' line, where the thighs rest on it), so the hips are free to fold over its top
    end; and an ankle roller behind the ankles, over the Achilles."""
    cam = v.cam
    n = unit(v3(-leg_dir[1], leg_dir[0]))           # pad normal, facing the thighs' front
    if n[1] > 0:
        n = -n
    a = hip - leg_dir * pad_from + n * pad_off
    b = hip - leg_dir * (pad_from + pad_len) + n * pad_off
    a3, b3 = v3(a[0], a[1], 0), v3(b[0], b[1], 0)
    pad = eq.pad(cam, a3, b3, up3=-n, width=44.0)
    rc = v3(*(ankle - n * 10.0 + leg_dir * 3.0)[:2])
    roller = Circle(cam.p(rc), 5.0)
    base = Cone(cam.p(b3 + n * 6.0), cam.p(v3(ankle[0], ankle[1] - 12.0, 0)), 2.6)
    posts = Union([Cone(cam.p(v3(x, y, 0)), cam.p(v3(x, 1.0, 0)), 2.4) for x, y in
                   ((a[0] + n[0] * 8.0, a[1] + n[1] * 8.0), (ankle[0], ankle[1] - 12.0))])
    # 3D: the base runs on the midline under the legs to the post under the feet, and a stem rises
    # from there between the ankles to the roller. The upright under the pad's top end stands
    # beside the body on the far side, a bracket across to the pad: folded, the trunk hangs on the
    # midline there and the crossed arms' elbows reach out to both sides, and the 2D draws this
    # upright behind all of them (a near twin would cross in front of the arms side-on)
    top = v3(a[0] + n[0] * 8.0, a[1] + n[1] * 8.0, 0.0)
    foot = v3(ankle[0], ankle[1] - 12.0, 0)
    side = -31.0
    frame3 = (eq.rod3d(top + Z * side, v3(top[0], 1.0, side), 2.4, 'frame')
              + eq.rod3d(top + Z * side, top - Z * (FOOT_HALF - 3.0), 1.8, 'frame')
              + eq.rod3d(v3(top[0], 1.2, side - 9.0), v3(top[0], 1.2, side + 9.0), 1.6, 'frame')
              + posts3d([(ankle[0], ankle[1] - 12.0)]) + eq.rod3d(b3 + n * 6.0, foot, 2.6, 'frame')
              + eq.rod3d(foot, rc, 1.6, 'frame'))
    return [Item(Union([posts, base]), 'frame', 'back', spec3d=frame3),
            Item(pad, 'pad', 'back', collider=eq.pad_box(a3, b3, -n, 44.0), spec3d=eq.pad3d(a3, b3, -n, 44.0)),
            Item(roller, 'pad', ('after', 'base'), gap=True, collider=('capsule', rc - Z * 20.0, rc + Z * 20.0, 5.0),
                 spec3d=roller3d(rc, 5.0))]


@exercise('backExtensions', 'back', 'side', muscles=['erectors', 'glutes', 'hamstrings'])
def back_extensions():
    ang = math.radians(45.0)
    leg_dir = v3(math.cos(ang), math.sin(ang))       # from the ankles up to the hips
    A = v3(-66.0, 26.0)
    H = A + leg_dir * (THIGH + SHANK - 0.2)           # legs long, the knees just unlocked

    def pose(u):
        pitch = lerp(45.0, 153.0, u)          # folded over the pad's top end, the belly against it
        p = {'pelvis': H, 'pitch': pitch, 'neck': lerp(0.0, 10.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            # the knees bend to the front of the legs (towards the pad), never backwards
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 9.0), 'foot_pitch': -45.0, 'pole': np.array([0.7, -0.7, 0.0])}
        p.update(crossed_arms(H, pitch))
        return p

    def equip(J, v, u):
        return roman_chair(v, H, leg_dir, A)

    return pose, rep_down_first(1.6, 1.3, top=0.45, bottom=0.25), equip


@exercise('hyperextensions', 'back', 'side', muscles=['erectors', 'glutes'])
def hyperextensions():
    leg_dir = v3(1.0, 0.0)
    A = v3(-88.0, 98.0)
    H = A + leg_dir * (THIGH + SHANK - 0.2)           # legs long, the knees just unlocked

    def pose(u):
        pitch = lerp(90.0, 172.0, u)
        p = {'pelvis': H, 'p_pitch': 90.0, 'pitch': pitch - 90.0, 'neck': lerp(8.0, 14.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            # face down: the knees bend towards the floor, not backwards
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 9.0), 'foot_pitch': -90.0, 'pole': np.array([0.0, -1.0, 0.0])}
        p.update(crossed_arms(H, pitch))
        return p

    def equip(J, v, u):
        cam = v.cam
        # the thighs rest on the pad; the roller sits on the backs of the ankles
        a3, b3 = v3(H[0] - 10.0, H[1] - 9.0, 0), v3(H[0] - 42.0, H[1] - 9.0, 0)   # hips free to fold
        pad = eq.pad(cam, a3, b3, width=44.0)
        rc = v3(A[0] + 3.0, A[1] + 10.0, 0)
        roller = Circle(cam.p(rc), 5.0)
        frame = Union([Cone(cam.p(v3(x, y, 0)), cam.p(v3(x, 1.0, 0)), 2.4) for x, y in
                       ((H[0] - 20.0, H[1] - 18.0), (A[0] + 3.0, A[1] + 3.0))] +
                      [Cone(cam.p(v3(H[0] - 20.0, 30.0, 0)), cam.p(v3(A[0] + 3.0, 30.0, 0)), 2.0)])
        # 3D: the frame on the midline under the body; the ankle post rises between the ankles to
        # the roller
        frame3 = (posts3d([(H[0] - 20.0, H[1] - 18.0), (A[0] + 3.0, A[1] + 3.0)])
                  + eq.rod3d(v3(H[0] - 20.0, 30.0, 0), v3(A[0] + 3.0, 30.0, 0), 2.0, 'frame'))
        return [Item(frame, 'frame', 'back', spec3d=frame3),
                Item(pad, 'pad', 'back', collider=eq.pad_box(a3, b3, Y, 44.0), spec3d=eq.pad3d(a3, b3, Y, 44.0)),
                Item(roller, 'pad', ('after', 'base'), gap=True, collider=('capsule', rc - Z * 20.0, rc + Z * 20.0, 5.0),
                     spec3d=roller3d(rc, 5.0))]

    return pose, rep_down_first(1.6, 1.3, top=0.45, bottom=0.25), equip


@exercise('reverseHyperextensions', 'back', 'side', muscles=['glutes', 'hamstrings', 'erectors'])
def reverse_hyperextensions():
    pad_y = 100.0
    P = v3(0.0, pad_y + 12.0)

    def pose(u):
        # chest on the pad (head right), legs hang off the end and swing up behind
        p = {'pelvis': P, 'pitch': 90.0, 'neck': 10.0}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'hip': lerp(0.0, -86.0, u), 'abd': 2.0, 'knee': lerp(10.0, 2.0, u), 'ankle': 20.0}
        S = shoulder_at(P, 90.0)
        p.update(both(v3(S[0] + 24.0, pad_y - 6.0, 22.0), [0.0, 1.0, 0.8]))
        return p

    def equip(J, v, u):
        cam = v.cam
        a3, b3 = v3(P[0] + 6.0, pad_y, 0), v3(P[0] + 62.0, pad_y, 0)     # the hips just off its end
        pad = eq.pad(cam, a3, b3, width=44.0)
        hc = v3(P[0] + TORSO + 24.0, pad_y - 6.0, 0)          # the handle bar, across, under the hands
        handles = Circle(cam.p(hc), 3.0)
        frame = Union([Cone(cam.p(v3(x, pad_y - 7.0, 0)), cam.p(v3(x, 1.0, 0)), 2.4) for x in (P[0] + 14.0, P[0] + 58.0)]
                      + [Cone(cam.p(v3(P[0] + 62.0, pad_y - 7.0, 0)), cam.p(hc), 1.8)])
        # 3D: the frame on the midline under the pad, a strut out to the middle of the handle bar;
        # the bar runs across under both hands (its collider), a foam grip in each fist (the 2D's
        # end-on disc, hidden by the near fist side-on; slimmer than the disc so the forearms clear it)
        frame3 = (posts3d([(x, pad_y - 7.0) for x in (P[0] + 14.0, P[0] + 58.0)])
                  + eq.rod3d(v3(P[0] + 62.0, pad_y - 7.0, 0), hc, 1.8, 'frame'))
        bar3 = eq.rod3d(hc - Z * 24.4, hc + Z * 24.4, 1.6, 'metal')
        for s in (-1.0, 1.0):
            bar3 += eq.rod3d(hc + Z * (s * 18.5), hc + Z * (s * 23.5), 2.5, 'metal')
        return [Item(frame, 'frame', 'back', spec3d=frame3),
                Item(pad, 'pad', 'back', collider=eq.pad_box(a3, b3, Y, 44.0), spec3d=eq.pad3d(a3, b3, Y, 44.0)),
                Item(handles, 'metal', 'back', collider=('capsule', hc - Z * 26.0, hc + Z * 26.0, 1.6), grip=True,
                     spec3d=bar3)]

    return pose, rep(1.1, 1.4, top=0.35, bottom=0.4), equip


@exercise('gluteHamRaise', 'legs', 'side', muscles=['hamstrings', 'glutes'])
def glute_ham_raise():
    K = v3(0.0, 96.0)
    A = K - v3(SHANK - 0.3, 0.0)

    def pose(u):
        # face down over the pad, then the hamstrings curl the body up to kneeling tall
        a = math.radians(lerp(0.0, 88.0, u))
        line = v3(math.cos(a), math.sin(a))
        H = K + line * THIGH
        pitch = 90.0 - math.degrees(a)
        p = {'pelvis': H, 'pitch': pitch, 'neck': lerp(8.0, 0.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A[0], A[1] + 1.0, sg * 9.0), 'foot_pitch': -90.0, 'pole': np.array([0.0, -1.0, 0.0])}
        p.update(crossed_arms(H, pitch))
        return p

    PC = K + v3(6.0, -19.0)             # knee pad: the lower thighs rest on it, the knees ride over it
    RC = A + v3(2.0, 9.5)               # ankle roller on the backs of the ankles

    def equip(J, v, u):
        cam = v.cam
        pad = Circle(cam.p(PC), 11.0)
        plate = RBox(cam.p(v3(A[0] - 9.0, A[1] - 2.0, 0)), 1.6, 12.0, 1.4)
        roller = Circle(cam.p(RC), 4.6)
        frame = Union([Cone(cam.p(PC - Y * 8.0), cam.p(v3(PC[0], 1.0, 0)), 2.6),
                       Cone(cam.p(v3(A[0] - 9.0, A[1] - 12.0, 0)), cam.p(v3(A[0] - 9.0, 1.0, 0)), 2.4),
                       Cone(cam.p(v3(PC[0], 26.0, 0)), cam.p(v3(A[0] - 9.0, 26.0, 0)), 2.0)])
        # 3D: the frame on the midline under the legs; the round knee pad, the foot plate and the
        # ankle roller run across both legs (the roller on a stem from the plate, between the feet)
        frame3 = (eq.rod3d(PC - Y * 8.0, v3(PC[0], 1.0, 0), 2.6, 'frame')
                  + eq.rod3d(v3(PC[0], 1.2, -FOOT_HALF), v3(PC[0], 1.2, FOOT_HALF), 1.6, 'frame')
                  + posts3d([(A[0] - 9.0, A[1] - 12.0)])
                  + eq.rod3d(v3(PC[0], 26.0, 0), v3(A[0] - 9.0, 26.0, 0), 2.0, 'frame'))
        pc = v3(A[0] - 9.0, A[1] - 2.0, 0)
        # the foot plate 1.2 cm thicker at its back than the 2D's (3.2 cm), so seen from behind it
        # stands 4 cm proud of the soles pressed on it (nearer, view3d lets the legs' muscle
        # highlight show through it)
        plate3 = (eq.box3d(pc - X * 0.6, X, Y, Z, 2.2, 12.0, 20.0, 1.4, 'frame')
                  + eq.rod3d(pc + Y * 10.0, v3(RC[0], RC[1], 0), 1.4, 'frame'))
        return [Item(frame, 'frame', 'back', spec3d=frame3),
                Item(pad, 'pad', ('after', 'base'), gap=True, collider=('cylinder', PC, Z, 11.0, 22.0),
                     spec3d=eq.cyl3d(PC, Z, 11.0, 22.0, 'pad', True)),
                Item(plate, 'frame', 'back', collider=('box', v3(A[0] - 9.0, A[1] - 2.0), [X, Y, Z], [1.6, 12.0, 20.0]),
                     spec3d=plate3),
                Item(roller, 'pad', ('after', 'base'), gap=True, collider=('cylinder', RC, Z, 4.6, 20.0),
                     spec3d=roller3d(RC, 4.6))]

    return pose, rep(1.4, 1.8, top=0.4, bottom=0.35), equip


@exercise('nordics', 'legs', 'side', muscles=['hamstrings'])
def nordics():
    K = v3(0.0, 9.0)           # the knees rest on the pad
    A = K - v3(SHANK - 0.3, -1.0)

    def pose(u):
        # lower slowly from kneeling tall, catch with the hands, push back up
        a = math.radians(lerp(2.0, 72.0, u))
        line = v3(math.sin(a), math.cos(a))
        H = K + line * THIGH
        pitch = math.degrees(a)
        p = {'pelvis': H, 'pitch': pitch, 'neck': 6.0}
        for s, sg in (('L', -1), ('R', 1)):
            # feet pointed back, the tips of the toes on the pad
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 9.0), 'foot_pitch': -150.0, 'pole': np.array([0.0, -1.0, 0.0])}
        S = shoulder_at(H, pitch)
        catch = smooth(0.55, 1.0, u)
        chest = torso_point(H, pitch, 16.0, 38.0)
        floor = v3(S[0] + 18.0, 4.4)
        hand = chest + (floor - chest) * catch
        p.update(both(v3(hand[0], hand[1], 22.0), [-0.6, 0.2, 0.7]))
        return p

    RC = A + v3(7.0, 9.4)               # a roller holds the ankles down, resting on the lower shins

    def equip(J, v, u):
        cam = v.cam
        pad = RBox(cam.p(v3(-20.0, 1.5, 0)), 42.0, 1.5, 1.4)
        roller = Circle(cam.p(RC), 4.2)
        # 3D: a kneeling mat 50 cm wide; the roller across both lower shins, on a stem rising from
        # the mat between them
        mat3 = eq.box3d(v3(-20.0, 1.5, 0), X, Y, Z, 42.0, 1.5, 25.0, 1.4, 'pad')
        roller3 = roller3d(RC, 4.2) + eq.rod3d(v3(RC[0], 2.0, 0), v3(RC[0], RC[1], 0), 1.4, 'frame')
        return [Item(pad, 'pad', 'back', collider=('box', v3(-20.0, 1.5), [X, Y, Z], [42.0, 1.5, 25.0]), spec3d=mat3),
                Item(roller, 'pad', ('after', 'base'), gap=True, collider=('cylinder', RC, Z, 4.2, 20.0),
                     spec3d=roller3)]

    return pose, Timeline([(0.5, 0, 0), (2.4, 0, 1), (0.25, 1, 1), (1.0, 1, 0)] * 2), equip
