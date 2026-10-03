"""Shoulder raises, rows and shrugs, cable and machine chest work.

Front view for movements out to the sides (lateral raises, flyes, bent-over raises), side view for
movements in the sagittal plane (front raises, rows, face pulls, presses).
"""
from .common import *
from ..rig import solve, rot_toward
from ..sdf import V, Circle, Cone, RBox, Union, Poly
from ..spec import HEEL, TOE, R_HEEL


# ---- helpers --------------------------------------------------------------------------------

def shoulders_of(pose):
    J = solve(pose)
    return J.p['shoulderL'], J.p['shoulderR'], J


def arc(S, a, b, deg, reach):
    """Point at `reach` from S, rotated from unit direction a towards b by deg (a great-circle arc)."""
    return np.asarray(S, float) + rot_toward(unit(a), unit(b), deg) * reach


def reach_for(bend):
    """Shoulder -> grip distance for an elbow bent by `bend` degrees."""
    return math.sqrt(UPPER ** 2 + FORE ** 2 + 2 * UPPER * FORE * math.cos(math.radians(bend)))


def perp_axis(fore, want):
    """Unit vector nearest to `want` that is perpendicular to the forearm direction."""
    d = unit(fore)
    w = np.asarray(want, float) - np.dot(want, d) * d
    return unit(w) if np.linalg.norm(w) > 1e-6 else unit(np.cross(d, Z))


def dumbbells(J, v, want, gap=True, sides='LR'):
    """A dumbbell in each hand whose handle points along `want` (made perpendicular to the forearm).
    want: vector or function(side) -> vector. eq.dumbbell turns continuously through the end-on
    view and brings its camera-side head in over the hand as it turns towards the camera."""
    items = []
    for s in sides:
        w = want(s) if callable(want) else want
        ax = perp_axis(J.p['hand' + s] - J.p['elbow' + s], w)
        items += eq.dumbbell(v, J.p['hand' + s], ax, ('before', 'arm' + s), gap=gap)
    return items


def behind_fists(v, items):
    """A bar held in both hands and seen along its length lies just behind the fists: the fingers
    close over it. eq.barbell slots it by its own depth, the hands' depth, but a forearm layer is
    ordered by the forearm's midpoint; when the forearms reach back from the bar (an upright row
    seen from the front) that puts the bar in front of both fists. Cap its depth just behind the
    nearer forearm layer."""
    fore = [L.depth for L in v.layers if L.name in ('foreL', 'foreR')]
    for it in items:
        if fore and it.depth is not None:
            it.depth = min(it.depth, min(fore) - 0.05)
    return items


def stand(half=11.0, bend=0.6, pitch=0.0, x=0.0, **extra):
    """Standing pose without arms (arms are added per exercise)."""
    p = {'pelvis': v3(x + 0.5, HIP_H - bend, 0.0), 'pitch': pitch}
    p.update(feet(x, half, 8.0))
    p.update(extra)
    return p


def fk(flex=0.0, abd=0.0, elbow=0.0):
    return {'flex': flex, 'abd': abd, 'elbow': elbow}


def hinge(A=-6.0, shin=6.0, knee=30.0, pitch=60.0, half=11.0, toe_out=6.0, neck=None):
    """Hip hinge over flat feet: ankles at x=A, shins inclined forward by `shin` degrees, knees
    bent by `knee` degrees, torso pitched forward by `pitch`. Returns the pose without arms."""
    K = v3(A, ANKLE_H) + SHANK * v3(math.sin(math.radians(shin)), math.cos(math.radians(shin)))
    b = math.radians(knee - shin)
    H = K + THIGH * v3(-math.sin(b), math.cos(b))
    p = {'pelvis': H, 'pitch': pitch, 'neck': 0.3 * pitch if neck is None else neck}
    p.update(feet(A, half, toe_out))
    return p


def raise_tl(up=1.3, down=1.55, hold_low=0.45, hold_high=0.3):
    """Two reps of a raise: arms low (0) -> high (1)."""
    return Timeline([(hold_low, 0, 0), (up, 0, 1), (hold_high, 1, 1), (down, 1, 0)] * 2)


def slerp(a, b, u):
    """Unit direction along the great circle from a to b."""
    a, b = unit(a), unit(b)
    ang = math.degrees(math.acos(float(np.clip(np.dot(a, b), -1.0, 1.0))))
    return rot_toward(a, b, ang * u)


# ---- standing raises, front view ------------------------------------------------------------

@exercise('lateralRaises', 'shoulders', 'front', muscles=['delts'])
def lateral_raises():
    def pose(u):
        p = stand()
        a = lerp(11.0, 86.0, u)
        e = lerp(10.0, 16.0, u)
        p['armL'] = fk(0.0, a, e)
        p['armR'] = fk(0.0, a, e)
        return p

    def equip(J, v, u):
        return dumbbells(J, v, X)

    return pose, raise_tl(), equip


@exercise('dumbbellScaption', 'shoulders', 'front', muscles=['delts'])
def dumbbell_scaption():
    base = stand()
    SL, SR, _ = shoulders_of(base)
    lo = math.radians(30.0)

    def pose(u):
        p = dict(base)
        e = lerp(6.0, 110.0, u)
        for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
            plane = unit(Z * sg * math.cos(lo) + X * math.sin(lo))
            H = arc(S, -Y, plane, e, reach_for(14.0))
            p['arm' + s] = {'hand': H, 'pole': unit(-X * 0.6 - Y + Z * sg * 0.35)}
        return p

    def equip(J, v, u):
        # thumbs up: the handle points forward when hanging and up when raised
        return dumbbells(J, v, lambda s: X * (1.0 - u) + Y * u * 1.4)

    return pose, raise_tl(1.35, 1.6), equip


@exercise('uprightRows', 'shoulders', 'front', muscles=['delts', 'traps'])
def upright_rows():
    base = stand()
    # a shoulder-width grip: narrower, the forearms lie along the bar as the elbows rise and run
    # into it at the wrists
    grip = 24.0
    _, SR, _ = shoulders_of(base)
    x0 = 12.5
    # arms hanging just short of locked: a straight arm is the IK's singular point (the elbow snaps)
    y0 = SR[1] - math.sqrt((ARM - 1.2) ** 2 - (x0 - SR[0]) ** 2 - (grip - SR[2]) ** 2)

    def bar(u):
        y = lerp(y0, 138.5, u)
        x = lerp(x0, 15.0, u)
        return v3(x, y, 0.0)

    def pose(u):
        p = dict(base)
        B = bar(u)
        pole = [lerp(-0.7, -0.1, u), lerp(-0.4, 0.3, u), 1.0]
        p.update(both(v3(B[0], B[1], grip), pole))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return behind_fists(v, eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0))

    return pose, raise_tl(1.25, 1.5), equip


def cable_lateral(key):
    """One arm, cable from a low pulley on the figure's left: the right hand starts in front of the
    hips and sweeps out to the side to shoulder height; the left hand holds the tower. The tower
    stands a step in front of the lifter, so the cable runs across the front of the legs rather
    than through them (depth only: it looks the same from the front)."""
    @exercise(key, 'shoulders', 'front', muscles=['delts'])
    def build():
        base = stand(half=10.0)
        SL, SR, _ = shoulders_of(base)
        TZ = -56.0                       # tower (figure's left)
        TX = 20.0
        PUL = v3(TX, 14.0, TZ + 5.0)
        d0 = unit(v3(0.3, -0.95, -0.24))  # in front of the hips, the forearm clear of the belly
        d1 = unit(v3(0.12, 0.03, 1.0))
        R = reach_for(14.0)
        hold = v3(TX, 112.0, TZ + 5.5)

        def pose(u):
            p = dict(base)
            H = SR + slerp(d0, d1, u) * R
            p['armR'] = {'hand': H, 'pole': unit(v3(-1.0, 0.25, 0.3))}
            p['armL'] = {'hand': hold, 'pole': unit(v3(-0.2, -1.0, -0.6))}
            return p

        def equip(J, v, u):
            return eq.cable_stack(v, PUL, J.p['handR'], z=('before', 'armR'), mount=X)

        return pose, raise_tl(1.3, 1.6), equip
    return build


cable_lateral('cableLateralRaises')
cable_lateral('cableRaises')


# ---- front raises, side view ------------------------------------------------------------------

def front_raise_pose(u, abd=4.0, lo=9.0):
    p = stand()
    fl = lerp(lo, 88.0, u)
    e = lerp(9.0, 12.0, u)
    p['armL'] = fk(fl, abd, e)
    p['armR'] = fk(fl, abd, e)
    return p


@exercise('frontRaises', 'shoulders', 'side', muscles=['delts'])
def front_raises():
    def pose(u):
        # the dumbbells start resting against the front of the thighs, not sunk into them
        return front_raise_pose(u, 2.0, lo=11.0)

    def equip(J, v, u):
        # palms facing the thighs, then down: the handle runs across (end-on from the side)
        return dumbbells(J, v, Z)

    return pose, raise_tl(1.3, 1.55), equip


def plate_edge(v, c3, axis3, r, z, half_t=3.2, gap=True, grip=False):
    """A bumper plate seen edge-on (eq.plate_disc's look, a little thicker so it holds up at icon
    size). Never turns end-on here, so no disc variant is needed. grip=True: held at its rim."""
    c3 = np.asarray(c3, float)
    return [Item(eq.cyl(v.cam, c3, axis3, r, half_t), 'plate_rim', z, gap,
                 collider=('cylinder', c3, unit(axis3), r, half_t), grip=grip,
                 spec3d=eq.plate3d(c3, axis3, r, half_t, gap))]


@exercise('plateFrontRaise', 'shoulders', 'side', muscles=['delts'])
def plate_front_raise():
    def pose(u):
        # hands just outside the plate's rim, closed around its edge: the forearms pass outside it
        return front_raise_pose(u, 4.0)

    def equip(J, v, u):
        C = (J.p['handL'] + J.p['handR']) / 2
        return plate_edge(v, C, X, 20.0, ('before', 'armR'), grip=True)

    return pose, raise_tl(1.3, 1.55), equip


@exercise('barbellFrontRaise', 'shoulders', 'side', muscles=['delts'])
def barbell_front_raise():
    def pose(u):
        return front_raise_pose(u, 2.0)

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)

    return pose, raise_tl(1.3, 1.55), equip


# ---- bent-over raises, front view (the arms open like wings) -----------------------------------

def wings(p, u, top=84.0, bend=16.0, fwd=0.12, pole=None, low=3.0):
    """Arms hanging down from the shoulders (`low` degrees out) open out to the sides, `top`
    degrees up."""
    SL, SR, _ = shoulders_of(p)
    R = reach_for(bend)
    out = dict(p)
    for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
        side = unit(Z * sg + X * fwd)
        d = rot_toward(unit(-Y + X * 0.03), side, lerp(low, top, u))
        out['arm' + s] = {'hand': S + d * R,
                          'pole': unit(pole if pole is not None else v3(-1.0, 0.15, 0.25 * sg))}
    return out


def bent_raise(key, group, muscles, pitch=81.0, knee=30.0, neck=-16.0):
    """Standing, hinged until the torso is nearly level. Seen from the front the torso foreshortens,
    so the head is tucked slightly: it sinks between the shoulders, which reads as bent over."""
    @exercise(key, group, 'front', muscles=muscles)
    def build():
        base = hinge(A=-6.0, shin=8.0, knee=knee, pitch=pitch, half=12.0, neck=neck)

        def pose(u):
            return wings(base, u)

        def equip(J, v, u):
            return dumbbells(J, v, X)

        return pose, raise_tl(1.3, 1.6), equip
    return build


bent_raise('rearDeltRaise', 'shoulders', ['delts'])
bent_raise('bentOverLateralRaises', 'shoulders', ['delts'], pitch=83.0, knee=32.0)
bent_raise('reverseFly', 'back', ['delts', 'traps'], pitch=80.0)


# Chest-supported work: an adjustable bench with the back rest raised, the lifter kneeling on the
# seat and lying chest down on the back rest, facing +x. (eq.bench's incline puts the seat under the
# back rest, the way you sit on it; kneeling needs the seat on the near side of the hinge.)
INCLINE = 35.0
HINGE_X = -16.5
REST_LEN = 86.0
SEAT_LEN = 50.0


def chest_bench(v, incline=INCLINE):
    """Side-on the bench lies behind the figure (it is narrower than the body resting on it). Seen
    from the front the back rest rises towards the camera: its underside hides the torso and the
    thighs lying on it, while the head and the hanging arms stay in front of its top end."""
    cam = v.cam
    a = math.radians(incline)
    d = v3(math.cos(a), math.sin(a))
    h = v3(HINGE_X, BENCH_H)
    seat = (h - X * SEAT_LEN, h + X * 1.0)
    rest = (h, h + d * REST_LEN)
    front, gap = (('after', 'base'), True) if cam.kind == 'front' else ('back', False)
    seat_post = h - X * (SEAT_LEN - 12.0) - Y * eq.PAD_T
    rest_post = h + d * (REST_LEN * 0.6) - Y * 3.0
    # 3D (any camera): real depth puts the back rest in front of the body from the front, and its band
    # cuts in only where it really stands in front
    return [Item(Union(eq.post(cam, seat_post)), 'frame', 'back', spec3d=eq.post3d(seat_post)),
            Item(eq.pad(cam, *seat), 'pad', 'back', collider=eq.pad_box(*seat), spec3d=eq.pad3d(*seat)),
            Item(Union(eq.post(cam, rest_post)), 'frame', front, gap, spec3d=eq.post3d(rest_post)),
            Item(eq.pad(cam, *rest), 'pad', front, gap, collider=eq.pad_box(*rest), spec3d=eq.pad3d(*rest, gap=True))]


def prone_incline(incline=INCLINE, slide=3.0):
    """Knees on the seat, chest on the back rest, shoulders just past its top so the arms hang free."""
    a = math.radians(incline)
    d = v3(math.cos(a), math.sin(a))
    n = v3(-math.sin(a), math.cos(a))                   # away from the pad, towards the back
    tip = v3(HINGE_X, BENCH_H) + d * REST_LEN
    # the spine 14 cm above the pad: the chest, the deepest point of the drawn torso, rests on it
    S = tip + n * 14.0 + d * slide                      # shoulder line
    P = S - d * TORSO
    p = {'pelvis': v3(P[0], P[1], 0.0), 'pitch': 90.0 - incline, 'neck': 0.0}
    ky = BENCH_H + 6.4                                  # knee joint resting on the seat
    kz = 10.0
    kx = P[0] - math.sqrt(THIGH ** 2 - (P[1] - ky) ** 2 - (kz - HIP_HALF) ** 2)
    for s, sg in (('L', -1), ('R', 1)):
        p['leg' + s] = {'foot': v3(kx - SHANK, ky - 1.2, sg * kz), 'foot_pitch': 194.0, 'toe_out': 0.0,
                        'pole': v3(0.3, -1.0, 0.0)}
    return p


@exercise('reverseDeclineFly', 'shoulders', 'front', muscles=['delts'])
def reverse_decline_fly():
    base = prone_incline()

    def pose(u):
        return wings(base, u, top=82.0)

    def equip(J, v, u):
        return chest_bench(v) + dumbbells(J, v, X)

    return pose, raise_tl(1.3, 1.6), equip


@exercise('seatedBentOverLateralRaises', 'shoulders', 'front', muscles=['delts'])
def seated_bent_over_lateral_raises():
    P = v3(0.0, BENCH_H + 9.0, 0.0)
    base = {'pelvis': P, 'pitch': 62.0, 'neck': 26.0}
    # the knees only a little apart (the seat still shows between them) and the arms hanging a
    # little out to the sides, so they pass outside the knees instead of through them
    base.update(feet(THIGH * 0.99 + 4.0, 14.0, 6.0))
    for s, sg in (('L', -1), ('R', 1)):
        base['leg' + s]['pole'] = v3(1.0, 0.0, 0.1 * sg)

    def pose(u):
        return wings(base, u, top=80.0, low=10.0)

    def equip(J, v, u):
        return eq.bench(v, v3(-50.0, BENCH_H, 0.0), length=110.0) + dumbbells(J, v, X)

    return pose, raise_tl(1.3, 1.6), equip


# ---- rows, side view --------------------------------------------------------------------------

PLATE_R = 22.5
ROW_POLE = (-0.35, 1.0, 0.5)          # elbows drive up and back, a little out


def from_shoulders(S, pitch, A=-6.0, half=12.0, toe_out=6.0, neck=None):
    """Hinged posture that puts the shoulder line at S (x, y) with the torso pitched by `pitch`;
    the legs reach down to flat feet at x=A."""
    th = math.radians(pitch)
    P = v3(S[0] - TORSO * math.sin(th), S[1] - TORSO * math.cos(th), 0.0)
    p = {'pelvis': P, 'pitch': pitch, 'neck': 0.3 * pitch if neck is None else neck}
    p.update(feet(A, half, toe_out))
    return p


def hang(S, reach, grip, lead):
    """Grip point hanging from the shoulder S (3D), arms angled `lead` degrees back from vertical."""
    dz = grip - abs(S[2])
    h = math.sqrt(max(reach ** 2 - dz ** 2, 1.0))
    b = math.radians(lead)
    return v3(S[0] - h * math.sin(b), S[1] - h * math.cos(b), 0.0)


def bar_row(key, pitch, knee=30.0, bar_top=(18.0, 27.0), lead=6.0, grip=25.0, floor=False,
            timeline=None, curve=1.0):
    """Bent-over barbell row: the torso holds its angle while the bar travels from arm's length to
    the torso. floor=True: the bar starts from (and returns to) the floor each rep. curve > 1: the
    bar rises first and comes back to the body late (x follows u ** curve), clearing the knees."""
    @exercise(key, 'back', 'side', muscles=['lats', 'traps'])
    def build():
        if floor:
            B0 = v3(1.5, PLATE_R, 0.0)
            reach = ARM - 0.3
            h = math.sqrt(reach ** 2 - (grip - SHOULDER_HALF) ** 2)
            b = math.radians(lead)
            base = from_shoulders(B0 + h * v3(math.sin(b), math.cos(b)), pitch, A=-8.0)
        else:
            base = hinge(A=-6.0, shin=8.0, knee=knee, pitch=pitch, half=12.0)
            _, SR, _ = shoulders_of(base)
            B0 = hang(SR, ARM - 0.3, grip, lead)
        B1 = torso_point(base['pelvis'], pitch, *bar_top)

        def pose(u):
            p = dict(base)
            B = v3(lerp(B0[0], B1[0], u ** curve), lerp(B0[1], B1[1], u))
            p.update(both(v3(B[0], B[1], grip), list(ROW_POLE)))
            return p

        def equip(J, v, u):
            B = (J.p['handL'] + J.p['handR']) / 2
            return eq.barbell(v, v3(B[0], B[1], 0.0))

        return pose, timeline or Timeline([(0.45, 0, 0), (1.2, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip
    return build


bar_row('barbellRows', pitch=58.0, knee=30.0)
# to the lower chest, the bar rising close to vertical first: a straight line from the floor to the
# torso cuts through the knees
bar_row('pendlayRows', pitch=84.0, bar_top=(17.0, 36.0), lead=4.0, floor=True, curve=1.5,
        timeline=Timeline([(0.7, 0, 0), (0.95, 0, 1), (0.3, 1, 1), (1.3, 1, 0)] * 2))


class Lever:
    """A bar pivoting on the floor behind the lifter (T-bar, landmine). The grip sits `off` cm
    off the bar (+ above, - below); its arc through the start and finish grips fixes the pivot."""

    def __init__(self, H0, H1, off, pivot_y=6.0):
        (x0, y0), (x1, y1) = (H0[0], H0[1] - pivot_y), (H1[0], H1[1] - pivot_y)
        px = ((x0 ** 2 - x1 ** 2) + y0 ** 2 - y1 ** 2) / (2 * (x0 - x1))
        self.O = v3(px, pivot_y)
        self.Rg = math.hypot(x0 - px, y0)
        self.b0, self.b1 = math.atan2(y0, x0 - px), math.atan2(y1, x1 - px)
        self.off = off
        self.R = math.sqrt(self.Rg ** 2 - off ** 2)

    def at(self, u):
        """(grip point, bar point below/above it, bar direction)."""
        b = lerp(self.b0, self.b1, u)
        a = b - math.asin(self.off / self.Rg)
        d = v3(math.cos(a), math.sin(a))
        G = self.O + self.Rg * v3(math.cos(b), math.sin(b))
        return G, self.O + d * self.R, d


def lever_row(key, off, grip_z, plate_r, plate_at, bar_end, base_kind, pitch=48.0, knee=30.0, stop=1.0):
    """The bar runs between the legs (z = 0): drawn over the torso and the far leg, under the near
    leg and the near arm. The grip's arc runs from arm's length to the torso; stop < 1 ends the
    pull that far along it (where the plate meets the chest)."""
    @exercise(key, 'back', 'side', muscles=['lats', 'traps'])
    def build():
        base = hinge(A=-6.0, shin=8.0, knee=knee, pitch=pitch, half=16.0, toe_out=10.0)
        _, SR, _ = shoulders_of(base)
        reach = ARM - 0.5
        h = math.sqrt(reach ** 2 - (SHOULDER_HALF - grip_z) ** 2)
        fwd = math.radians(9.0)
        H0 = v3(SR[0] + h * math.sin(fwd), SR[1] - h * math.cos(fwd))
        H1 = torso_point(base['pelvis'], pitch, 18.0, 24.0)
        lev = Lever(H0, H1, off)

        def pose(u):
            p = dict(base)
            G, _, _ = lev.at(u * stop)
            p.update(both(v3(G[0], G[1], grip_z), [-0.3, 1.0, 0.8]))
            return p

        def equip(J, v, u):
            cam = v.cam
            G, B, d = lev.at(u * stop)
            z = ('after', 'base')
            tip = lev.O + d * (lev.R + bar_end)
            bar = [Cone(cam.p(lev.O), cam.p(tip), 1.7)]
            cols = [('capsule', lev.O, tip, 1.7)]
            spec = eq.rod3d(lev.O, tip, 1.7, 'metal', True)
            if base_kind == 'tbar':
                # T handle standing on the bar; its cross grip runs across (end-on from the side)
                bar += [Cone(cam.p(B), cam.p(G), 1.5), Circle(cam.p(G), 2.2)]
                cols.append(('capsule', B, G, 1.5))
                grips = ('capsule', G - Z * (grip_z + 2.0), G + Z * (grip_z + 2.0), 2.2)   # ends inside the fists
                spec += eq.rod3d(B, G, 1.5, 'metal', True) + eq.rod3d(grips[1], grips[2], 2.2, 'metal', True)
            else:
                # V handle hooked under the bar
                bar += [Poly([cam.p(B - d * 5.0), cam.p(B + d * 5.0), cam.p(G)], r=1.2)]
                sleeve = lev.O + d * (lev.R + 4.0)
                bar.append(Cone(cam.p(sleeve), cam.p(tip), 2.6))
                cols += [('capsule', sleeve, tip, 2.6),
                         ('capsule', B - d * 5.0, G, 1.2), ('capsule', B + d * 5.0, G, 1.2)]
                grips = ('capsule', G - Z * (grip_z + 2.0), G + Z * (grip_z + 2.0), 1.5)
                # 3D: the V's two arms, a plate filling it under the bar (side-on it is a solid
                # triangle) and the cross grip at its point, held either side of the bar's plane
                down = unit(G - B)
                spec += (eq.rod3d(B - d * 5.0, G, 1.2, 'metal', True) + eq.rod3d(B + d * 5.0, G, 1.2, 'metal', True)
                         + eq.box3d(B + down * 2.75, d, down, Z, 3.0, 2.25, 0.8, 0.8, 'metal', True)
                         + eq.rod3d(grips[1], grips[2], 1.5, 'metal', True)
                         + eq.rod3d(sleeve, tip, 2.6, 'metal', True))
            plate = plate_edge(v, lev.O + d * (lev.R + plate_at), d, plate_r, z)
            # the plate rides on the bar: one piece in 3D, so the bar cuts no band where it runs through
            spec += plate[0].spec3d
            plate[0].spec3d = []
            items = [Item(Union(bar), 'metal', z, gap=True, collider=cols, spec3d=spec),
                     Item(None, 'metal', z, frame=False, collider=grips, grip=True)]
            items += plate
            O = cam.p(lev.O)
            foot = [RBox(O + V(-2.0, -1.5), 11.0, 4.2, 2.0), Circle(O, 3.0)]
            # 3D: a square base block on the floor and, across its whole width, the hinge tube the
            # bar pivots in with its pin (side-on the drawing's block, ring and pin)
            base = eq.box3d(lev.O + v3(-2.0, -1.5), X, Y, Z, 11.0, 4.2, 11.0, 2.0, 'frame')
            base += eq.cyl3d(lev.O, Z, 3.0, 11.5, 'frame') + eq.cyl3d(lev.O, Z, 1.4, 12.2, 'metal')
            if base_kind == 'landmine':
                foot = [RBox(O + V(-3.0, -2.5), 13.0, 3.4, 1.6), Circle(O, 4.2)]
                base = eq.box3d(lev.O + v3(-3.0, -2.5), X, Y, Z, 13.0, 3.4, 13.0, 1.6, 'frame')
                base += eq.cyl3d(lev.O, Z, 4.2, 13.5, 'frame') + eq.cyl3d(lev.O, Z, 1.4, 14.2, 'metal')
            items.append(Item(Union(foot), 'frame', 'back', spec3d=base))
            items.append(Item(Circle(O, 1.4), 'metal', 'back', spec3d=[]))
            return items

        return pose, Timeline([(0.45, 0, 0), (1.25, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip
    return build


lever_row('tBarRows', off=7.0, grip_z=13.0, plate_r=15.0, plate_at=16.0, bar_end=24.0, base_kind='tbar')
# the V handle hangs below the bar, so the bar and its plate reach the chest before the hands do:
# the pull ends when the plate touches the chest
lever_row('landmineRows', off=-8.0, grip_z=5.0, plate_r=17.0, plate_at=14.0, bar_end=32.0,
          base_kind='landmine', pitch=45.0, stop=0.62)


@exercise('dumbbellRows', 'back', 'side', muscles=['lats', 'traps'])
def dumbbell_rows():
    """Left knee and left hand on a flat bench (far side), the right arm rows (near side). The
    standing foot is planted a little behind the hip, so the thigh stays clear of the dumbbell's
    rear head as it comes up beside the waist."""
    pitch = 80.0
    P = v3(0.0, 90.0, 0.0)
    th = math.radians(pitch)
    u_t, f_t = v3(math.sin(th), math.cos(th)), v3(math.cos(th), -math.sin(th))
    knee = v3(-19.0, BENCH_H + 6.2, -9.5)
    base = {'pelvis': P, 'pitch': pitch, 'neck': 20.0,
            'legL': {'foot': knee + v3(-SHANK, -1.8, 0.0), 'pole': v3(0.25, -1.0, 0.0),
                     'foot_pitch': 194.0, 'toe_out': 0.0},
            'legR': {'foot': v3(-8.0, ANKLE_H, 25.0), 'pole': v3(1.0, 0.15, 0.3), 'toe_out': 10.0}}
    SL, SR, _ = shoulders_of(base)
    wrist = v3(SL[0] - 3.0, BENCH_H + 4.4, -15.0)
    base['armL'] = {'hand': wrist, 'pole': v3(-0.4, 0.0, -1.0), 'palm': True, 'palm_dir': X}
    grip = SR[2] + 6.0
    H0 = hang(SR, ARM - 0.6, grip, -2.0)
    H0[2] = grip
    # finish: elbow drawn back along the torso, forearm vertical, dumbbell at the waist
    H1 = P + u_t * 22.0 + f_t * 13.0
    H1[2] = grip

    def pose(u):
        p = dict(base)
        p['armR'] = {'hand': H0 + (H1 - H0) * u, 'pole': unit(v3(-0.8, 1.0, 0.45))}
        return p

    def equip(J, v, u):
        return (eq.bench(v, v3(-4.0, BENCH_H, -10.0), length=124.0)
                + dumbbells(J, v, X, sides='R'))

    return pose, Timeline([(0.45, 0, 0), (1.4, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip


@exercise('chestSupportedRows', 'back', 'side', muscles=['lats', 'traps'])
def chest_supported_rows():
    base = prone_incline()
    P, pitch = base['pelvis'], base['pitch']
    _, SR, _ = shoulders_of(base)
    grip = SHOULDER_HALF + 2.0
    H0 = hang(SR, ARM - 0.6, grip, -2.0)
    # finish at the lower ribs: any lower and the dumbbells' rear heads run into the thighs
    H1 = torso_point(P, pitch, 9.0, 22.0)

    def pose(u):
        p = dict(base)
        H = H0 + (H1 - H0) * u
        p.update(both(v3(H[0], H[1], grip), [-0.6, 1.0, 0.5]))
        return p

    def equip(J, v, u):
        return chest_bench(v) + dumbbells(J, v, X)

    return pose, Timeline([(0.45, 0, 0), (1.4, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip


def sole_line(ankle, foot_pitch):
    """World points (heel, toe) on the sole surface of a foot at `foot_pitch` (side view plane)."""
    fp = math.radians(foot_pitch)
    t = v3(math.cos(fp), math.sin(fp))
    n = v3(-math.sin(fp), math.cos(fp))
    heel = ankle + n * (HEEL[0] - R_HEEL) + t * HEEL[1]
    toe = ankle + n * (TOE[0] - R_TOE) + t * TOE[1]
    return heel, toe, n


@exercise('seatedCableRows', 'back', 'side', muscles=['lats', 'traps'])
def seated_cable_rows():
    seat = 42.0
    P = v3(0.0, seat + 9.0, 0.0)
    ANK = v3(84.0, 46.0)
    FP = 64.0
    base = {'pelvis': P, 'pitch': 0.0, 'neck': 0.0}
    for s, sg in (('L', -1), ('R', 1)):
        base['leg' + s] = {'foot': v3(ANK[0], ANK[1], sg * 12.0), 'foot_pitch': FP, 'toe_out': 4.0,
                           'pole': v3(0.1, 1.0, 0.2 * sg)}
    heel, toe, n = sole_line(ANK, FP)
    plate_lo = heel - (toe - heel) * 0.35
    plate_hi = toe + (toe - heel) * 0.2
    PUL = v3(ANK[0] + 17.0, 43.0, 0.0)
    grip = 6.0

    def torso(u):
        return lerp(13.0, -4.0, u)

    def pose(u):
        p = dict(base)
        p['pitch'] = torso(u)
        p['neck'] = -0.4 * p['pitch']
        S = torso_point(P, p['pitch'], 0.0, TORSO)
        H0 = S + v3(57.0, -21.0)
        H1 = torso_point(P, p['pitch'], 17.0, 19.0)
        H = H0 + (H1 - H0) * u
        p.update(both(v3(H[0], H[1], grip), [-0.5, -0.3, 1.0]))
        return p

    def equip(J, v, u):
        cam = v.cam
        H = (J.p['handL'] + J.p['handR']) / 2
        # the cable runs between the legs: over the torso and the far leg, under the near leg
        items = eq.cable_stack(v, PUL, H, z=('after', 'base'), tower_x=ANK[0] + 30.0)
        plate = (v3(plate_lo[0], plate_lo[1], 0.0), v3(plate_hi[0], plate_hi[1], 0.0))
        # 3D: a footplate under each foot, the cable running out between them (side-on the drawing's
        # one plate)
        feet = [e for sg in (-1, 1)
                for e in eq.pad3d(*(p + Z * sg * 11.0 for p in plate), up3=v3(n[0], n[1], 0.0), width=12.0)]
        items.append(Item(Union([eq.pad(cam, *plate, up3=v3(n[0], n[1], 0.0), width=34.0)]), 'pad', 'back',
                          collider=eq.pad_box(*plate, up3=v3(n[0], n[1], 0.0), width=34.0), spec3d=feet))
        post_top = v3(plate_lo[0] + 6.0, plate_lo[1], 0.0)
        # 3D: the post with a cross bar carrying both footplates, and the bracket that holds the low
        # pulley out from the tower
        items.append(Item(Union(eq.post(cam, post_top)), 'frame', 'back',
                          spec3d=eq.post3d(post_top) + eq.rod3d(post_top - Z * 17.0, post_top + Z * 17.0, 2.2)
                          + eq.rod3d(PUL, v3(ANK[0] + 30.0, PUL[1], 0.0), 1.6)))
        items += eq.bench(v, v3(-12.0, seat, 0.0), length=96.0)
        a, b = H - X * 1.0 - Y * 3.5, H + X * 5.5
        # 3D: a V handle, a grip through each fist meeting at its point in front (side-on, one bar)
        vee = [e for s in 'LR' for e in eq.rod3d(J.p['hand' + s] - X * 1.0 - Y * 3.5, b, 1.7, 'metal')]
        items.append(Item(Cone(cam.p(a), cam.p(b), 1.7), 'metal', ('before', 'armR'),
                          collider=('capsule', a, b, 1.7), grip=True, spec3d=vee))
        return items

    return pose, Timeline([(0.45, 0, 0), (1.3, 0, 1), (0.35, 1, 1), (1.55, 1, 0)] * 2), equip


@exercise('seatedRowMachine', 'back', 'side', muscles=['lats', 'traps'])
def seated_row_machine():
    seat = 48.0
    pitch = 6.0
    base = seated(0.0, seat_h=seat, pitch=pitch, half=13.0)
    base['neck'] = -3.0
    P = base['pelvis']
    S = torso_point(P, pitch, 0.0, TORSO)
    grip = SHOULDER_HALF + 3.0
    H0 = v3(S[0] + 57.0, S[1] - 16.0)
    H1 = torso_point(P, pitch, 8.0, 28.0)
    COL = S[0] + 92.0
    PUL = v3(COL - 5.0, H0[1], 0.0)
    pad_lo = torso_point(P, pitch, 14.2, 19.0)
    pad_hi = torso_point(P, pitch, 14.2, 45.0)
    back_n = v3(-math.cos(math.radians(pitch)), math.sin(math.radians(pitch)), 0.0)

    def pose(u):
        p = dict(base)
        H = H0 + (H1 - H0) * u
        p.update(both(v3(H[0], H[1], grip), [-0.9, -0.2, 0.6]))
        return p

    def equip(J, v, u):
        cam = v.cam
        # 3D: the column, the pulley wheel turning across it and its hub
        items = [Item(RBox(cam.p(v3(COL, 76.0, 0.0)), 4.5, 76.0, 3.0), 'frame', 'back',
                      spec3d=eq.box3d(v3(COL, 76.0, 0.0), X, Y, Z, 4.5, 76.0, 4.5, 3.0, 'frame')),
                 Item(Circle(cam.p(PUL), 4.6), 'metal', 'back',
                      spec3d=eq.cyl3d(PUL, Z, 4.6, 1.4, 'metal') + eq.cyl3d(PUL, Z, 1.6, 1.8, 'frame')),
                 Item(Circle(cam.p(PUL), 1.6), 'frame', 'back', spec3d=[])]
        mid = (pad_lo + pad_hi) / 2
        arm_y = mid[1] - 2.0
        frame = [Cone(cam.p(v3(mid[0] + 8.0, arm_y, 0.0)), cam.p(v3(COL, arm_y, 0.0)), 2.0)]
        frame += eq.post(cam, v3(0.0, seat - eq.PAD_T, 0.0))
        frame.append(Cone(cam.p(v3(0.0, 2.2, 0.0)), cam.p(v3(COL, 2.2, 0.0)), 1.8))
        fspec = (eq.rod3d(v3(mid[0] + 8.0, arm_y, 0.0), v3(COL, arm_y, 0.0), 2.0)
                 + eq.post3d(v3(0.0, seat - eq.PAD_T, 0.0))
                 + eq.rod3d(v3(0.0, 2.2, 0.0), v3(COL, 2.2, 0.0), 1.8))
        items.append(Item(Union(frame), 'frame', 'back', spec3d=fspec))
        chest = (v3(pad_lo[0], pad_lo[1], 0.0), v3(pad_hi[0], pad_hi[1], 0.0))
        seat_pad = (v3(-18.0, seat, 0.0), v3(18.0, seat, 0.0))
        # 3D: a machine seat is 35 cm wide (side-on its width doesn't show)
        items.append(Item(Union([eq.pad(cam, *chest, up3=back_n, width=30.0), eq.pad(cam, *seat_pad)]), 'pad', 'back',
                          collider=[eq.pad_box(*chest, up3=back_n, width=30.0), eq.pad_box(*seat_pad)],
                          spec3d=eq.pad3d(*chest, up3=back_n, width=30.0) + eq.pad3d(*seat_pad, width=35.0)))
        # a cable to each vertical grip, beside the chest pad; side-on the two coincide, so the
        # near one is drawn, just behind the near hand (3D: both)
        for s in 'LR':
            Hs = J.p['hand' + s]
            near = s == 'R'
            items.append(Item(Cone(cam.p(PUL), cam.p(Hs), 0.55) if near else None, 'metal', ('before', 'armR'),
                              frame=near, collider=('capsule', PUL, Hs, 0.4), grip=True,
                              spec3d=eq.rod3d(PUL, Hs, 0.55, 'metal')))
            items.append(Item(Cone(cam.p(Hs - Y * 6.5), cam.p(Hs + Y * 6.5), 1.8) if near else None, 'metal',
                              ('before', 'armR'), frame=near, collider=('capsule', Hs - Y * 6.5, Hs + Y * 6.5, 1.8),
                              grip=True, spec3d=eq.rod3d(Hs - Y * 6.5, Hs + Y * 6.5, 1.8, 'metal')))
        return items

    return pose, Timeline([(0.45, 0, 0), (1.25, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip


@exercise('facePulls', 'back', 'side', muscles=['delts', 'traps'])
def face_pulls():
    pitch = -4.0
    base = stand(half=11.0, bend=2.5, pitch=pitch)
    base['neck'] = 4.0
    _, SR, _ = shoulders_of(base)
    PUL = v3(128.0, 158.0, 0.0)
    H0 = v3(SR[0] + 57.0, 151.0, 7.0)
    H1 = v3(SR[0] + 13.0, 157.0, 25.0)

    def pose(u):
        p = dict(base)
        H = H0 + (H1 - H0) * u
        pole = unit(v3(lerp(-0.6, -0.35, u), lerp(-0.6, 0.25, u), 1.0))
        p.update(both(H, pole))
        return p

    def equip(J, v, u):
        cam = v.cam
        H = (J.p['handL'] + J.p['handR']) / 2
        knot = H + X * lerp(11.0, 17.0, u)
        knot[2] = 0.0
        items = eq.cable_stack(v, PUL, knot, z=('before', 'armR'), tower_x=PUL[0] + 4.0)
        rope = [Cone(cam.p(knot), cam.p(J.p['hand' + s]), 1.5) for s in 'LR']
        rope.append(Circle(cam.p(knot), 2.0))
        # 3D: the rope handle, a short rope from the knot at the cable's end to each fist
        spec = [e for s in 'LR' for e in eq.rod3d(knot, J.p['hand' + s], 1.5, 'plate_rim')]
        items.append(Item(Union(rope), 'plate_rim', ('before', 'armR'), spec3d=spec + eq.ball3d(knot, 2.0, 'plate_rim')))
        return items

    return pose, Timeline([(0.45, 0, 0), (1.2, 0, 1), (0.45, 1, 1), (1.5, 1, 0)] * 2), equip


# ---- chest: cables and machines ---------------------------------------------------------------

@exercise('cableCrossovers', 'chest', 'front', muscles=['pecs'])
def cable_crossovers():
    pitch = 12.0
    base = stand(half=13.0, bend=2.0, pitch=pitch)
    SL, SR, _ = shoulders_of(base)
    R = reach_for(24.0)
    TZ = 96.0
    PY = 206.0

    def pose(u):
        p = dict(base)
        for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
            d0 = unit(v3(-0.12, 0.42, sg * 1.0))
            d1 = unit(v3(0.78, -0.62, -sg * 0.24))
            H = S + slerp(d0, d1, u) * R
            p['arm' + s] = {'hand': H, 'pole': unit(v3(-0.8, lerp(0.6, 0.2, u), sg * 0.3))}
        return p

    def equip(J, v, u):
        cam = v.cam
        items = []
        for s, sg in (('L', -1), ('R', 1)):
            PUL, H = v3(0.0, PY, sg * TZ), J.p['hand' + s]
            items += eq.cable_stack(v, PUL, H, z=('before', 'arm' + s), mount=X)
            # the cable comes down to the handle from above and outside, in front of the arm (at the
            # finish it crosses in front of the forearm); only its last few cm run into the fist
            k = H + unit(PUL - H) * 7.0
            items[-1].shape = Cone(cam.p(k), cam.p(H), 0.55)
            # (3D: the tower's spec already runs the whole cable from the pulley to the hand)
            items.append(Item(Cone(cam.p(PUL), cam.p(k), 0.55), 'metal', ('after', 'arm' + s), spec3d=[]))
        return items

    return pose, Timeline([(0.4, 0, 0), (1.3, 0, 1), (0.4, 1, 1), (1.6, 1, 0)] * 2), equip


ARM_OUT, ARM_BACK = 40.0, 10.0     # 3D: where a fly machine's arm drops (along / behind its hand's line)


def fly_machine(key, bend, drop, pads):
    """Seated fly machine seen from the front: the handles swing on a vertical axis through each
    shoulder, from out at the sides to together in front of the chest."""
    @exercise(key, 'chest', 'front', muscles=['pecs'])
    def build():
        seat = 46.0
        base = seated(0.0, seat_h=seat, pitch=-3.0, half=15.0)
        base['neck'] = 3.0
        SL, SR, _ = shoulders_of(base)
        rh = math.sqrt(reach_for(bend) ** 2 - drop ** 2)       # horizontal radius of the handle

        def handle(S, sg, u):
            phi = math.radians(lerp(-10.0, 101.0, u))
            return v3(S[0] + rh * math.sin(phi), S[1] - drop, S[2] + sg * rh * math.cos(phi)), phi

        def pose(u):
            p = dict(base)
            for s, S, sg in (('L', SL, -1), ('R', SR, 1)):
                H, phi = handle(S, sg, u)
                tang = v3(math.cos(phi), 0.0, -sg * math.sin(phi))
                p['arm' + s] = {'hand': H, 'pole': unit(-tang - Y * 0.5)}
            return p

        def equip(J, v, u):
            cam = v.cam
            items = eq.bench(v, v3(-8.0, seat, 0.0), length=40.0)
            back_ab = v3(-16.0, seat + 4.0, 0.0), v3(-16.0, seat + 62.0, 0.0)
            back = [eq.pad(cam, *back_ab, up3=X, width=32.0)]
            # 3D: the back pad on a post standing behind the seat, a bracket into its back (both hidden
            # behind the seat's legs and the lifter from the front)
            brace = v3(-31.0, seat + 48.0, 0.0)
            items.append(Item(Union(back), 'pad', 'back', spec3d=eq.pad3d(*back_ab, up3=X, width=32.0)
                              + eq.post3d(brace) + eq.rod3d(brace, brace + X * 10.0, 2.2)))
            # the machine's frame: two uprights and a top beam carrying the arm pivots
            top = SR[1] + 44.0
            frame = [Cone(cam.p(v3(-22.0, 1.5, sg * 40.0)), cam.p(v3(-22.0, top, sg * 40.0)), 2.6) for sg in (-1, 1)]
            frame.append(Cone(cam.p(v3(-22.0, top, -40.0)), cam.p(v3(-22.0, top, 40.0)), 2.6))
            # 3D: each arm turns about the vertical through its shoulder (the handles' path), so its
            # hub sits on that axis at the beam's height, on a bracket reaching forward from the beam
            # (seen from the front the hub is the drawing's pivot)
            hubs = [v3(S[0], top, S[2]) for S in (SL, SR)]
            fspec = [e for sg in (-1, 1) for e in eq.rod3d(v3(-22.0, 1.5, sg * 40.0), v3(-22.0, top, sg * 40.0), 2.6)]
            fspec += eq.rod3d(v3(-22.0, top, -40.0), v3(-22.0, top, 40.0), 2.6)
            fspec += [e for hub in hubs for e in eq.rod3d(v3(-22.0, top, hub[2]), hub, 2.2)]
            items.append(Item(Union(frame), 'frame', 'back', spec3d=fspec))
            items += [Item(Circle(cam.p(v3(-22.0, top, S[2])), 4.0), 'metal', 'back', spec3d=[]) for S in (SL, SR)]
            for (s, S, sg), hub in zip((('L', SL, -1), ('R', SR, 1)), hubs):
                H, phi = handle(S, sg, u)
                tang = v3(math.cos(phi), 0.0, -sg * math.sin(phi))
                # 3D: the arm runs out from its hub at the beam's height, drops behind its hand's line
                # (out beside the head when the hands meet, behind the head when they are wide) to
                # below the chin and comes in to the handle: the face stays clear from the front
                knee = hub + v3(math.sin(phi), 0.0, sg * math.cos(phi)) * ARM_OUT - tang * ARM_BACK
                low = v3(knee[0], S[1] + 8.0, knee[2])
                arm = eq.ball3d(hub, 4.0, 'metal')
                if pads:
                    # upright pad on the leading side of the hand, facing the direction of the sweep
                    c = H + tang * 3.5 + Y * 2.0
                    ex = unit(np.cross(Y, tang))
                    shape = eq.box3(cam, c, ex, Y, tang, 6.5, 13.0, 3.2, 2.6)
                    # 3D: the arm from the hub down to the pad's top, the pad
                    arm += (eq.rope3d([hub, knee, low, c + Y * 11.0], 2.0, 'metal')
                            + eq.box3d(c, ex, Y, tang, 6.5, 13.0, 3.2, 2.6, 'pad', True))
                    items.append(Item(shape, 'pad', ('before', 'arm' + s), gap=True,
                                      collider=('box', c, [ex, Y, tang], [6.5, 13.0, 3.2]), grip=True, spec3d=arm))
                    # out at the sides the hand pushes the pad towards the camera, so the pad hides
                    # the fist; as the sweep turns it towards the midline the fist comes back in
                    # front (a copy fades in over the hand, like eq.dumbbell's head)
                    over = smooth(0.5, 2.0, cam.depth(c) - cam.depth(H))
                    if over > 0.0:
                        items.append(Item(shape, 'pad', ('after', 'arm' + s), alpha=over, spec3d=[]))
                else:
                    # 3D: the arm from the hub down to the top of the upright handle, the handle
                    arm += (eq.rope3d([hub, knee, low, H + Y * 7.5], 2.0, 'metal')
                            + eq.rod3d(H - Y * 7.5, H + Y * 7.5, 1.8, 'metal', True))
                    items.append(Item(Cone(cam.p(H - Y * 7.5), cam.p(H + Y * 7.5), 1.8), 'metal',
                                      ('before', 'arm' + s), gap=True,
                                      collider=('capsule', H - Y * 7.5, H + Y * 7.5, 1.8), grip=True, spec3d=arm))
            return items

        return pose, Timeline([(0.4, 0, 0), (1.3, 0, 1), (0.4, 1, 1), (1.6, 1, 0)] * 2), equip
    return build


fly_machine('pecDeckFly', bend=28.0, drop=8.0, pads=True)
fly_machine('machineFly', bend=16.0, drop=9.0, pads=False)


@exercise('singleArmCablePress', 'chest', 'side', muscles=['pecs'])
def single_arm_cable_press():
    pitch = 9.0
    P = v3(-2.0, HIP_H - 3.0, 0.0)
    base = {'pelvis': P, 'pitch': pitch, 'neck': -3.0,
            'legL': {'foot': v3(26.0, ANKLE_H, -11.0), 'pole': v3(1.0, 0.0, -0.2), 'toe_out': 6.0},
            'legR': {'foot': v3(-34.0, ANKLE_H + 1.5, 11.0), 'pole': v3(1.0, 0.0, 0.2), 'toe_out': 10.0,
                     'foot_pitch': -14.0}}
    _, SR, _ = shoulders_of(base)
    PUL = v3(-92.0, SR[1] - 12.0, 24.0)
    H0 = v3(SR[0] + 4.0, SR[1] - 12.0, 27.0)
    H1 = v3(SR[0] + 57.0, SR[1] - 6.0, 6.0)
    base['armL'] = {'hand': v3(SR[0] + 10.0, SR[1] - 58.0, -24.0), 'pole': v3(-1.0, 0.0, -0.3)}

    def pose(u):
        p = dict(base)
        H = H0 + (H1 - H0) * u
        p['armR'] = {'hand': H, 'pole': unit(v3(-1.0, lerp(-0.2, -0.7, u), lerp(0.9, 0.3, u)))}
        return p

    def equip(J, v, u):
        cam = v.cam
        H = J.p['handR']
        # the cable runs past the torso's side and in under the pressing arm to the foot of the
        # handle: in front of the body, behind both halves of the near arm. (Clipped to the handle's
        # centre it would lie along the forearm into the fist at lockout.)
        items = eq.cable_stack(v, PUL, H - Y * 6.0, z=('after', 'head'), tower_x=PUL[0] - 4.0)
        items.append(Item(Cone(cam.p(H - Y * 6.0), cam.p(H + Y * 6.0), 1.8), 'metal', ('before', 'armR'),
                          spec3d=eq.rod3d(H - Y * 6.0, H + Y * 6.0, 1.8, 'metal')))
        return items

    return pose, Timeline([(0.45, 0, 0), (1.2, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip


# ---- shrugs -----------------------------------------------------------------------------------

def shrug_pose(u, arms):
    p = stand()
    p['shrug'] = lerp(0.0, 7.0, u)
    p['armL'] = dict(arms)
    p['armR'] = dict(arms)
    return p


@exercise('dumbbellShrugs', 'back', 'back', muscles=['traps'])
def dumbbell_shrugs():
    def pose(u):
        return shrug_pose(u, fk(2.0, 9.0, 6.0))

    def equip(J, v, u):
        return dumbbells(J, v, X)

    return pose, Timeline([(0.45, 0, 0), (1.2, 0, 1), (0.45, 1, 1), (1.4, 1, 0)] * 2), equip


@exercise('barbellShrugs', 'back', 'back', muscles=['traps'])
def barbell_shrugs():
    def pose(u):
        return shrug_pose(u, fk(12.0, 3.5, 4.0))

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), z_front=('before', 'base'))

    return pose, Timeline([(0.45, 0, 0), (1.2, 0, 1), (0.45, 1, 1), (1.4, 1, 0)] * 2), equip
