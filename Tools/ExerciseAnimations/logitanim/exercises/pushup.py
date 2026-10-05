"""Plank-based pressing: push-up variants, pike and handstand push-ups."""
from .common import *
from ..rig import solve
from ..spec import R_HEEL, TOE


def rot2(p, g):
    c, s = math.cos(g), math.sin(g)
    return v3(c * p[0] - s * p[1], s * p[0] + c * p[1])


class Plank:
    """A rigid body line pivoting about the toes. Plank frame: body along +x, front facing -y."""

    def __init__(self, toe_x=-132.0, hand_z=28.0, wrist_h=4.4, hand_x=None, chest_gap=6.0, top_reach=None):
        from ..spec import TOE
        self.TOE = v3(toe_x, R_TOE)
        self.toe_l = v3(TOE[0], -TOE[1])
        self.S_l = v3(SHANK + THIGH + TORSO, 0.0)
        self.hand_z, self.wrist_h = hand_z, wrist_h
        reach = top_reach or math.sqrt((UPPER + FORE_WRIST - 0.35) ** 2 - (hand_z - SHOULDER_HALF) ** 2)
        self.g_top = self._solve(lambda g: self.world(self.S_l, g)[1] - (wrist_h + reach))
        chest_l = v3(SHANK + THIGH + 36.0, -12.6)
        self.g_bot = self._solve(lambda g: self.world(chest_l, g)[1] - chest_gap)
        self.x_hand = hand_x if hand_x is not None else self.world(self.S_l, self.g_top)[0]

    def world(self, p, g):
        return self.TOE + rot2(np.asarray(p, float) - self.toe_l, g)

    def _solve(self, f):
        lo, hi = -0.2, 0.9
        for _ in range(60):
            mid = (lo + hi) / 2
            if f(mid) < 0:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2

    def pose(self, g, feet_half=9.0, arm_pole=(-0.75, 0.15, 0.65), neck=14.0):
        w = lambda x, y: self.world(v3(x, y), g)
        A = w(0, 0)
        H = w(SHANK + THIGH, 0)
        pitch = 90.0 - math.degrees(g)
        p = {'pelvis': H, 'pitch': pitch, 'neck': neck}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * feet_half), 'foot_pitch': math.degrees(g) - 90.0,
                            'pole': v3(0, -1, 0)}
        wr = v3(self.x_hand, self.wrist_h, self.hand_z)
        p.update(both(wr, list(arm_pole), palm=True, palm_dir=X))
        return p


@exercise('pushups', 'chest', 'side', muscles=['pecs'])
def pushups():
    pl = Plank()

    def pose(u):
        return pl.pose(lerp(pl.g_top, pl.g_bot, u))

    return pose, rep_down_first(1.35, 1.15, top=0.5, bottom=0.2), None


@exercise('diamondPushups', 'triceps', 'side', muscles=['triceps', 'pecs'])
def diamond_pushups():
    pl = Plank(hand_z=5.0)
    pl.x_hand -= 7.0

    def pose(u):
        return pl.pose(lerp(pl.g_top, pl.g_bot, u), arm_pole=(-1.0, 0.25, 0.3))

    return pose, rep_down_first(1.35, 1.15, top=0.5, bottom=0.2), None


RING_Y = 13.0


def rings_items(v, J, top_y=250.0, sides='LR', r=6.2, beam_y=None):
    """Gymnastic rings under the hands, straps running up out of frame. The straps run up the
    outside of the arms (a few cm out from the hand), so the near one passes in front of the arm and
    the far one behind the body; the hand holds the ring's bottom bar.
    beam_y: in 3D the straps hang from a beam at this height, just above the picture (everything in
    a 3D scene counts for its framing, so they can't run up to top_y)."""
    items = []
    near = 'R' if v.cam.depth(J.p['handR']) >= v.cam.depth(J.p['handL']) else 'L'
    beam_y = top_y if beam_y is None else beam_y
    for s in sides:
        h = J.p['hand' + s]
        out = Z * (6.0 if h[2] >= 0 else -6.0)
        c = v.cam.p(h)
        ring = Subtract(Circle(c, r), Circle(c, r - 2.0))
        s0, s1 = h + Y * (r - 0.5) + out, v3(h[0], top_y, h[2]) + out
        strap = Cone(v.cam.p(s0), v.cam.p(s1), 0.9)
        z = ('after', 'arm' + s) if s == near else ('before', 'arm' + s)
        spec = ring3d(h, out, v3(h[0], beam_y, h[2]) + out, r - 1.0)
        if s == sides[0]:
            spec += ring_beam(J, sides, beam_y)
        items.append(Item(ring, 'metal', z, gap=(s == near),
                          collider=('capsule', h - X * 4.0, h + X * 4.0, 1.2), grip=True, spec3d=spec))
        items.append(Item(strap, 'metal', z, frame=False, collider=('capsule', s0, s1, 0.9), spec3d=[]))
    return items


def ring3d(h, out, s1, radius, tube=1.0):
    """A gymnastic ring and its strap in 3D. The hand holds the ring's bottom bar (along x, the
    grip) and the strap, `out` to the side of the hand (it runs up outside the arm), ends at the
    ring's top: the ring rises from the fist leaning out to it, in the plane of the grip. The ring
    is the 2D one's size (radius to the middle of its 2 cm tube); both rings cut a band into what
    lies behind them, from whichever side. s1: the strap's top."""
    o = float(np.linalg.norm(out))
    lean = math.asin(min(o / (2.0 * radius), 1.0))
    w = Y * math.cos(lean) + unit(out) * math.sin(lean)        # up the ring, from the grip to the strap
    nrm = unit(np.cross(X, w))
    return eq.ring3d(h + w * radius, nrm, radius, tube, 'metal', True, n=10) + \
        eq.rod3d(h + w * 2.0 * radius, s1, 0.9, 'metal')


def ring_beam(J, sides, y):
    """The beam the rings' straps hang from (3D only), across above the hands, a little past them."""
    hs = [J.p['hand' + s] for s in sides]
    x = float(np.mean([h[0] for h in hs]))
    zs = [h[2] + (6.0 if h[2] >= 0 else -6.0) for h in hs]
    return eq.rod3d(v3(x, y, min(zs) - 10.0), v3(x, y, max(zs) + 10.0), 2.5, 'frame')


@exercise('ringPushups', 'chest', 'side', muscles=['pecs'])
def ring_pushups():
    pl = Plank(hand_z=26.0, wrist_h=RING_Y, top_reach=math.sqrt((ARM - 0.5) ** 2 - 8.0 ** 2), chest_gap=10.0)

    def pose(u):
        g = lerp(pl.g_top, pl.g_bot, u)
        p = pl.pose(g)
        # elbows back along the body, not flared out over the rings: there the straps ran through them
        for s, sg in (('L', -1), ('R', 1)):
            p['arm' + s] = {'hand': v3(pl.x_hand, RING_Y, sg * 26.0), 'pole': v3(-1.0, 0.1, 0.35 * sg)}
        return p

    def equip(J, v, u):
        # in 3D the straps hang from a beam just above the picture's top edge (y 181.8)
        return rings_items(v, J, beam_y=187.0)

    return pose, rep_down_first(1.4, 1.2, top=0.5, bottom=0.2), equip


def toe_ankle(toe, fp):
    """Ankle target for a foot pitched fp degrees (- = heel up) whose ball rests at `toe`."""
    a = math.radians(fp)
    t, n = v3(math.cos(a), math.sin(a)), v3(-math.sin(a), math.cos(a))
    return np.asarray(toe, float) - n * TOE[0] - t * TOE[1]


def inverted(pelvis, pitch, hands, feet_x, feet_y=R_TOE + 4.0, foot_pitch=-62.0, neck=-10.0, feet_on_wall=None,
             elbow_pole=(0.6, 0.2, 0.6)):
    """Hips-high positions (pike, handstand): palms on the floor, legs to the feet."""
    p = {'pelvis': np.asarray(pelvis, float), 'pitch': pitch, 'neck': neck}
    for s, sg in (('L', -1), ('R', 1)):
        if feet_on_wall is not None:
            # soles flat on the wall, toes down: with the shins pointing at the wall, a pitch of +90
            # turned the soles away from it and left the feet hanging in the air in front of it
            p['leg' + s] = {'foot': v3(feet_on_wall[0], feet_on_wall[1], sg * 9.0), 'foot_pitch': -90.0,
                            'pole': v3(1.0, 0.0, 0.1 * sg)}
        else:
            p['leg' + s] = {'foot': v3(feet_x, feet_y, sg * 10.0), 'foot_pitch': foot_pitch,
                            'pole': v3(1.0, -0.2, 0.1 * sg)}
    hx, hz = hands
    p.update(both(v3(hx, 4.4, hz), list(elbow_pole), palm=True, palm_dir=X))
    return p


@exercise('pikePushups', 'shoulders', 'side', muscles=['delts', 'triceps'])
def pike_pushups():
    # Hands and toes stay planted and the legs straight, so the hips swing a little forward over the
    # feet as the head goes down. (Placed by hand, the body hung above the floor at the top: the hips
    # were too high for the legs and the shoulders too high for the arms, and the toes of the pitched
    # feet went into the floor.)
    fp = -62.0
    ankle = toe_ankle(v3(-95.4, R_TOE), fp)
    hand = v3(10.0, 4.4)
    leg = math.sqrt(87.2 ** 2 - (10.0 - HIP_HALF) ** 2)
    arm = math.sqrt(56.8 ** 2 - (26.0 - SHOULDER_HALF) ** 2)
    hip = lambda phi: ankle + leg * v3(math.cos(math.radians(phi)), math.sin(math.radians(phi)))
    lo, hi = 20.0, 89.0                  # the top: as high as straight arms allow at pitch 128
    for _ in range(50):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if np.linalg.norm(shoulder_at(hip(mid), 128.0) - hand) < arm else (lo, mid)
    phi0 = lo
    phi1 = phi0 - 7.6                    # the bottom: the head about 10 cm off the floor

    def pose(u):
        # hips stay high; the head travels down and slightly forward between the hands
        pitch = lerp(128.0, 140.0, u)
        return inverted(hip(lerp(phi0, phi1, u)), pitch, (hand[0], 26.0), ankle[0], feet_y=ankle[1],
                        foot_pitch=fp, neck=lerp(-6.0, -24.0, u), elbow_pole=(-0.2, 0.6, 0.8))

    return pose, rep_down_first(1.4, 1.2, top=0.5, bottom=0.2), None


WALL_X = -36.0


def wall(v, x=WALL_X, h=400.0, h3d=None):
    """A wall filling x - 6 .. x, its face at x towards the figure (on its +x side).
    h3d: its height in 3D, a backdrop 120 cm wide: up past the picture's top edge, no further (the
    baked rig's framing counts backdrops too, so a 4 m wall would shrink the figure in the app)."""
    hh = (h if h3d is None else h3d) / 2
    spec = eq.box3d(v3(x - 3.0, hh, 0.0), X, Y, Z, 3.0, hh, 60.0, 2.0, 'frame', 'back')
    return [Item(RBox(v.cam.p(v3(x - 3.0, h / 2)), 3.0, h / 2, 2.0), 'frame', 'back', frame=False,
                 collider=('box', v3(x - 3.0, h / 2, 0.0), [X, Y, Z], [3.0, h / 2, 150.0]), spec3d=spec)]


def cruise(u, r=0.2):
    """0 -> 1 with smooth ramps and a steady middle (a trapezoidal speed profile). For a long move
    made of steps: the minimum-jerk ease runs the middle at almost twice the average speed, which
    turns the steps there into twitches."""
    v = 1.0 / (1.0 - r)
    if u <= r:
        x = u / r
        return v * r * (x ** 3 - x ** 4 / 2)
    if u >= 1.0 - r:
        return 1.0 - cruise(1.0 - u, r)
    return v * (r / 2 + u - r)


def walk_limbs(f, u, plan, steps=3):
    """Pose f(u) whose hands and feet walk instead of sliding: each limb in plan ({'armR': (phase,
    lift3), ...}) holds a place on its keyed path and moves on to the next in `steps` quick steps
    (the step slot is shared by two limbs: phase 0 or 0.5), lifted along lift3 at mid-step. Each
    place is where the path is halfway through the time the limb rests there, so the body moves over
    it rather than away from it. The body follows f(u) continuously; at u = 0 and 1 every limb is on
    its key."""
    p = f(u)
    for limb, (phase, lift) in plan.items():
        q, arc, prev = 0.0, 0.0, 0.0
        for k in range(steps):
            a = (k + phase) / steps
            b = a + 0.5 / steps
            nxt = 1.0 if k == steps - 1 else (k + phase + 0.75) / steps
            q += smooth(a, b, u) * (nxt - prev)
            prev = nxt
            if a < u < b:
                arc = math.sin(math.pi * (u - a) / (b - a))
        d = f(q)[limb]
        key = 'hand' if limb.startswith('arm') else 'foot'
        d[key] = np.asarray(d[key], float) + np.asarray(lift, float) * arc
        p[limb] = d
    return p


@exercise('handstandPushups', 'shoulders', 'side', muscles=['delts', 'triceps'])
def handstand_pushups():
    # Upside down with the back to the wall and the heels resting on it, facing the hands. Pitched
    # over alone the figure faced the wall, with the hands behind its back and the legs swinging off
    # the wall at the top and into it at the bottom; p_yaw turns it round, which puts its right side
    # at -z, so the targets are mirrored.
    wall_x = -26.0
    sh_x = -10.0
    hand = v3(12.0, 4.4, -26.0)                   # the right hand
    # at the top the arms are straight (higher, the hands hung above the floor)
    top = hand[1] + math.sqrt((UPPER + FORE_WRIST - 0.3) ** 2 - (hand[0] - sh_x) ** 2 - (26.0 - SHOULDER_HALF) ** 2)

    def body(u, lean):
        sh_y = lerp(top, 36.0, u)
        th = math.radians(180.0 - lean)
        P = v3(sh_x - math.sin(th) * TORSO, sh_y - math.cos(th) * TORSO)
        p = {'pelvis': P, 'p_pitch': 180.0 - lean, 'p_yaw': 180.0, 'pitch': 0.0, 'neck': 14.0}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'hip': lerp(-6.0, -2.0, u), 'abd': 2.0, 'knee': lerp(4.0, 8.0, u), 'ankle': 30.0}
        p.update(both(hand, [1.0, 0.1, -0.5], palm=True, palm_dir=X))
        return p

    def pose(u):
        # lean just so far that the heels rest on the wall as the body lowers and rises
        lo, hi = -6.0, 16.0
        for _ in range(28):
            mid = (lo + hi) / 2
            J = solve(body(u, mid))
            if min(J.p['heelL'][0], J.p['heelR'][0]) - R_HEEL < wall_x:
                hi = mid
            else:
                lo = mid
        return body(u, lo)

    def equip(J, v, u):
        # in 3D the wall reaches just past the picture's top edge (y 238.3)
        return wall(v, x=wall_x, h3d=244.0)

    return pose, rep_down_first(1.5, 1.3, top=0.5, bottom=0.25), equip


@exercise('wallClimbs', 'shoulders', 'side', muscles=['delts'])
def wall_climbs():
    wx = -120.0
    pl = Plank(toe_x=wx + 8.8)           # heels just touching the wall (at +5 they were in it)
    k0 = pl.pose(pl.g_top)
    # feet walk up the wall, hands walk back towards it
    # (hips at 104 held the hands 16 cm above the floor: the arms can't reach down that far)
    k1 = inverted(v3(-60.0, 86.0), 124.0, (8.0 - 38.0, 26.0), 0, feet_on_wall=(wx + 8.0, 58.0), neck=-8.0,
                  elbow_pole=(0.6, 0.1, 0.6))
    k2 = inverted(v3(wx + 38.0, 108.0), 172.0, (wx + 55.0, 26.0), 0, feet_on_wall=(wx + 8.0, 150.0), neck=-6.0,
                  elbow_pole=(1.0, 0.1, 0.5))
    f = keys(k0, k1, k2)
    # hands and feet step rather than slide, in diagonal pairs: right hand with left foot, then
    # left hand with right foot; hands lift off the floor, feet off the wall
    up, off = v3(0.0, 6.0), v3(6.0, 0.0)
    plan = {'armR': (0.0, up), 'legL': (0.0, off), 'armL': (0.5, up), 'legR': (0.5, off)}

    def pose(u):
        return walk_limbs(f, cruise(u), plan)

    def equip(J, v, u):
        # in 3D the wall reaches just past the picture's top edge (y 213.8)
        return wall(v, x=wx, h3d=220.0)

    return pose, Timeline([(0.6, 0, 0), (1.6, 0, 1), (0.7, 1, 1), (1.6, 1, 0)] * 2, linear=True), equip


# ---- dips ----------------------------------------------------------------------------------

DIP_Y = 118.0


def dip_bars(v, J, x0=-26.0, x1=34.0, y=DIP_Y, zs=(26.0,)):
    """Parallel bars and their posts, placed by depth at the hands' side, just behind the fists: the
    near bar and posts come in front of the legs swinging between them, the far ones stay behind."""
    items = []
    cam = v.cam
    for zz in zs:
        for sg in (1, -1):
            z = zz * sg
            bar = Cone(cam.p(v3(x0, y, z)), cam.p(v3(x1, y, z)), 2.4)
            xs = (x0 + 4, x1 - 4)
            posts = Union([Cone(cam.p(v3(x, y, z)), cam.p(v3(x, 0.8, z)), 2.2) for x in xs]
                          + [Cone(cam.p(v3(x - 9, 0.8, z)), cam.p(v3(x + 9, 0.8, z)), 1.4) for x in xs])
            d = cam.depth(v3(0.0, y, z)) - 0.5
            near = d > 0
            # 3D: this side's bar on its two posts (with their feet), one piece; both sides cut a
            # band into what lies behind them, from whichever side
            spec = eq.rod3d(v3(x0, y, z), v3(x1, y, z), 2.4, 'metal', True)
            for x in xs:
                spec += eq.rod3d(v3(x, y, z), v3(x, 0.8, z), 2.2, 'frame', True)
                spec += eq.rod3d(v3(x - 9, 0.8, z), v3(x + 9, 0.8, z), 1.4, 'frame', True)
            items.append(Item(posts, 'frame', depth=d - 0.1, gap=near,
                              collider=[('capsule', v3(x, y, z), v3(x, 0.8, z), 2.2) for x in xs], spec3d=spec))
            items.append(Item(bar, 'metal', gap=near, depth=d,
                              collider=('capsule', v3(x0, y, z), v3(x1, y, z), 2.4), grip=True, spec3d=[]))
    return items


def dip(key, group, muscles, lean0=4.0, lean1=10.0, depth=28.0, elbow=(-1.0, 0.0, 0.25), rings=False):
    @exercise(key, group, 'side', muscles=muscles)
    def build():
        hy = RING_Y + 105.0 if rings else DIP_Y
        hz = 26.0
        reach = math.sqrt((ARM - 0.4) ** 2 - (hz - SHOULDER_HALF) ** 2)

        def pose(u):
            lean = lerp(lean0, lean1, u)
            sy = hy + reach - depth * u
            sx = 3.0 + lerp(0.0, 3.0, u)
            th = math.radians(lean)
            P = v3(sx - math.sin(th) * TORSO, sy - math.cos(th) * TORSO)
            p = {'pelvis': P, 'pitch': lean, 'neck': 0.5 * lean, 'shrug': lerp(1.0, 2.5, u)}
            for s, sg in (('L', -1), ('R', 1)):
                p['leg' + s] = {'hip': lerp(-4.0, 6.0, u), 'abd': 1.0, 'knee': 72.0, 'ankle': 25.0}
            p.update(both(v3(0.0, hy, hz), list(elbow)))
            return p

        def equip(J, v, u):
            if rings:
                # in 3D the straps hang from a beam just above the picture's top edge (y 240)
                return rings_items(v, J, top_y=320.0, beam_y=245.0)
            return dip_bars(v, J)

        return pose, rep_down_first(1.5, 1.2, top=0.45, bottom=0.2), equip
    return build


dip('chestDips', 'chest', ['pecs', 'triceps'], lean0=18.0, lean1=32.0, depth=30.0, elbow=(-1.0, 0.0, 0.7))
dip('dips', 'triceps', ['triceps', 'pecs'], lean0=8.0, lean1=16.0)
dip('tricepDips', 'triceps', ['triceps'], lean0=2.0, lean1=6.0, depth=26.0, elbow=(-1.0, 0.0, 0.1))
dip('ringDips', 'triceps', ['triceps', 'pecs'], lean0=6.0, lean1=14.0, rings=True)


@exercise('benchDips', 'triceps', 'side', muscles=['triceps'])
def bench_dips():
    top = BENCH_H
    px = -5.0                     # the hips, lowered straight down in front of the bench
    # hands on the bench's end behind the hips, fingers over its edge: the end is behind the back
    # (the hips passed down through it) and the hands on it rather than beside it (it is 28 wide)
    hx, hz = -21.5, 12.5
    edge = hx + 3.0

    def pose(u):
        # hands on the bench behind the hips, heels on the floor out in front
        sy = top + 55.0 - 26.0 * u
        P = v3(px, sy - TORSO + lerp(0.0, 2.0, u))
        p = {'pelvis': P, 'pitch': lerp(-4.0, 2.0, u), 'neck': 4.0, 'shrug': lerp(1.0, 3.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(P[0] + 74.0, ANKLE_H + 1.0, sg * 11.0), 'foot_pitch': 12.0,
                            'pole': v3(0.4, 1.0, 0.0)}
        p.update(both(v3(hx, top + 3.0, hz), [-1.0, 0.1, 0.3]))
        return p

    def equip(J, v, u):
        return eq.bench(v, v3(edge - 35.0, top, 0.0), length=70.0)

    return pose, rep_down_first(1.4, 1.2, top=0.45, bottom=0.2), equip
