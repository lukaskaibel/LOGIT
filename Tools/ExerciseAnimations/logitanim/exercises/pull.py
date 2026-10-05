"""Vertical pulls: pull-up family, pulldowns, muscle-ups, rope climbs."""
from .common import *

BAR_Y = 232.0


class Hang:
    """Hanging from the bar, pulling up until the shoulders are `top_below_bar` under it.

    The head has to get past the bar: while rising, the body swings back under it and leans back,
    and the chin comes up as the face passes, so the bar goes by in front of the face and ends up in
    front of the neck, never through the head. Seen from the back this is depth, so the picture
    hardly changes."""

    def __init__(self, grip=40.0, top_below_bar=8.0, lean=14.0):
        self.grip, self.lean = grip, lean
        dz = grip - SHOULDER_HALF
        self.y_hang = BAR_Y - math.sqrt((ARM - 0.35) ** 2 - dz ** 2)
        self.y_top = BAR_Y - top_below_bar

    def at(self, below):
        """The phase at which the shoulders are `below` cm under the bar."""
        return (BAR_Y - below - self.y_hang) / (self.y_top - self.y_hang)

    def pose(self, u, legs=None, pole=(0.25, -1.0, 1.3)):
        ys = lerp(self.y_hang, self.y_top, u)
        back = smooth(0.0, self.at(26.0), u)          # all the way back before the face reaches the bar
        lean = -self.lean * back
        lift = lerp(4.0, 0.0, smooth(0.0, 0.4, u))
        up = v3(math.sin(math.radians(lean)), math.cos(math.radians(lean)))
        chin = 20.0 * smooth(self.at(38.0), self.at(26.0), u) - 12.0 * smooth(self.at(18.0), 1.0, u)
        p = {'pelvis': v3(-10.0 * back, ys) - up * (TORSO + lift), 'pitch': lean, 'neck': chin, 'shrug': lift}
        p.update(both(v3(0.0, BAR_Y, self.grip), list(pole)))
        for s in 'LR':
            p['leg' + s] = dict(legs or {'hip': 0.0, 'abd': 1.2, 'knee': 0.0, 'ankle': 20.0})
        return p


PULL = Timeline([(0.6, 0, 0), (1.3, 0, 1), (0.35, 1, 1), (1.7, 1, 0)] * 2)


def bar_equip(J, v, u):
    return eq.fixed_bar(v, v3(0.0, BAR_Y, 0.0))


@exercise('pullups', 'back', 'back', muscles=['lats'], floor=False)
def pullups():
    h = Hang()
    return h.pose, PULL, bar_equip


@exercise('chinups', 'back', 'back', muscles=['lats', 'biceps'], floor=False)
def chinups():
    # chest up, shoulders back: a little more lean. It also keeps the back view from switching the
    # forward-pointing arms behind the body halfway up (a switch pops); they stay drawn over it
    h = Hang(grip=25.0, top_below_bar=9.0, lean=18.0)
    return (lambda u: h.pose(u, pole=(0.9, -1.0, 0.45))), PULL, bar_equip


@exercise('widegripPullups', 'back', 'back', muscles=['lats'], floor=False)
def widegrip_pullups():
    h = Hang(grip=56.0, top_below_bar=11.0)
    return (lambda u: h.pose(u, pole=(0.1, -1.0, 1.4))), PULL, bar_equip


@exercise('closegripPullups', 'back', 'back', muscles=['lats', 'biceps'], floor=False)
def closegrip_pullups():
    h = Hang(grip=12.0, top_below_bar=10.0)
    return (lambda u: h.pose(u, pole=(0.9, -1.0, 0.5))), PULL, bar_equip


@exercise('assistedPullups', 'back', 'back', muscles=['lats'])
def assisted_pullups():
    h = Hang(grip=38.0)
    kneel = {'hip': 0.0, 'abd': 3.0, 'knee': 92.0, 'ankle': 10.0}

    def pose(u):
        return h.pose(u, legs=kneel)

    def equip(J, v, u):
        cam = v.cam
        k = (J.p['kneeL'] + J.p['kneeR']) / 2
        # the knees rest on the pad (and the shins along it, back towards the camera)
        pc = k + v3(-12.0, -10.0, 0)
        pad = RBox(cam.p(k + v3(0, -10.0, 0)), 20.0, 3.4, 3.0)
        lever = Cone(cam.p(k + v3(0, -13.5, 0)), cam.p(v3(k[0], 22.0, 0)), 2.2)
        frame = Union([RBox(cam.p(v3(0, (BAR_Y + 12) / 2, s * 64.0)), 3.2, (BAR_Y + 12) / 2, 2.2) for s in (-1, 1)])
        # 3D: the two uprights (square tubes), a base along the floor between their feet and the
        # sleeve the lever slides in, standing on it; the lever and the knee pad on it are one
        # piece, the carriage (the pad as its collider: under the knees and along the shins)
        hh = (BAR_Y + 12) / 2
        frame3d = [e for s in (-1, 1) for e in eq.box3d(v3(0, hh, s * 64.0), X, Y, Z, 3.2, hh, 3.2, 2.2, 'frame')]
        frame3d += eq.rod3d(v3(0, 1.4, -64.0), v3(0, 1.4, 64.0), 1.4, 'frame')
        frame3d += eq.rod3d(v3(1.0, 1.4, 0), v3(1.0, 26.0, 0), 3.2, 'frame')
        carriage = (eq.rod3d(k + v3(0, -13.5, 0), v3(k[0], 22.0, 0), 2.2, 'metal')
                    + eq.box3d(pc, X, Y, Z, 18.0, 3.4, 20.0, 3.0, 'pad'))
        return [Item(frame, 'frame', 'back', spec3d=frame3d), Item(lever, 'metal', 'back', spec3d=carriage),
                Item(pad, 'pad', 'back', collider=('box', pc, [X, Y, Z], [18.0, 3.4, 20.0]), spec3d=[])] + \
            bar_equip(J, v, u)

    return pose, PULL, equip


LAT_TOWER_X = 72.0          # the lat machine's tower, in front of the feet (3D only)


def lat_machine(seat_h, sc, top):
    """The lat machine as one 3D piece: the seat post (the 2D post) and the seat, a floor rail to the
    tower in front of the feet (the 2D back view has it hidden behind the figure), the top beam the
    pulley hangs from, and the thigh pad on an arm from the tower. The pad rests on the thighs: the
    2D one, seen only from behind, sits a hand above them."""
    tx = LAT_TOWER_X
    beam_y = top[1] + 4.4 + 2.2
    tower_h = beam_y + 2.0
    thigh = v3(30.0, seat_h + 15.5, 0.0)          # its underside on the thighs' top
    spec = eq.box3d(v3(12.0, (seat_h - 8) / 2, 0.0), X, Y, Z, 3.0, (seat_h - 8) / 2, 3.0, 2.0, 'frame')
    spec += eq.rod3d(v3(12.0, 1.2, 0.0), v3(tx - 4.5, 1.2, 0.0), 1.4, 'frame')
    spec += eq.box3d(v3(tx, tower_h / 2, 0.0), X, Y, Z, 4.5, tower_h / 2, 4.5, 3.0, 'frame')
    spec += eq.rod3d(v3(top[0] - 2.0, beam_y, 0.0), v3(tx, beam_y, 0.0), 2.2, 'frame')
    spec += eq.rod3d(thigh + X * 5.0, v3(tx - 4.5, thigh[1], 0.0), 1.8, 'frame')
    spec += eq.box3d(sc, X, Y, Z, 15.0, 3.5, 20.0, 3.0, 'pad')
    spec += eq.box3d(thigh, X, Y, Z, 5.0, 4.0, 24.0, 3.8, 'pad')
    return spec


def pulldown(key, grip, pole, muscles, fwd=13.0):
    """fwd: how far in front of the shoulders the bar ends up (it passes the face at a distance and,
    for a close grip, keeps the forearms in front of the chest, so from behind they stay hidden)."""
    @exercise(key, 'back', 'back', muscles=muscles)
    def build():
        seat_h = 50.0
        P = v3(0.0, seat_h + 9.0, 0.0)
        top_y = P[1] + TORSO + ARM - 1.5

        def pose(u):
            lean = lerp(-4.0, -14.0, u)
            p = {'pelvis': P, 'pitch': lean, 'neck': lerp(0.0, 6.0, u)}
            for s, sg in (('L', -1), ('R', 1)):
                p['leg' + s] = {'foot': v3(40.0, ANKLE_H, sg * 14.0), 'pole': v3(1.0, 0.3, 0.2 * sg), 'toe_out': 6.0}
            S = shoulder_at(P, lean)
            hy = lerp(top_y, S[1] + 8.0, u)
            hx = lerp(4.0, S[0] + fwd, u)
            p.update(both(v3(hx, hy, grip), list(pole)))
            p['shrug'] = lerp(3.5, 0.0, smooth(0.0, 0.35, u))
            return p

        def equip(J, v, u):
            cam = v.cam
            B = (J.p['handL'] + J.p['handR']) / 2
            c = v3(B[0], B[1], 0.0)
            half = max(grip + 12.0, 18.0)
            bar = eq.cyl(cam, c, Z, 1.8, half)
            top = v3(4.0, 262.0, 0.0)
            items = [Item(Cone(cam.p(c), cam.p(top), 0.55), 'metal', 'back', frame=False,
                          collider=('capsule', c, top, 0.4), grip=True, spec3d=eq.rod3d(c, top, 0.55, 'metal')),
                     Item(Circle(cam.p(top), 4.4), 'metal', 'back', frame=False, spec3d=eq.ball3d(top, 4.4, 'metal')),
                     Item(bar, 'metal', 'back', collider=('capsule', c - Z * half, c + Z * half, 1.8), grip=True,
                          spec3d=eq.cyl3d(c, Z, 1.8, half, 'metal', True))]
            # the seat ends a hand short of the knees (the thighs slope down to them) and sits a
            # touch lower, so the thighs rest on it rather than sink into its front edge
            sc, tc = v3(9.0, seat_h - 4.5, 0.0), v3(30.0, seat_h + 25.0, 0.0)
            seat = eq.box3(cam, sc, X, Y, Z, 15.0, 3.5, 20.0, 3.0)
            thigh_pad = eq.box3(cam, tc, X, Y, Z, 5.0, 4.0, 24.0, 3.8)
            post = RBox(cam.p(v3(12.0, (seat_h - 8) / 2, 0.0)), 3.0, (seat_h - 8) / 2, 2.0)
            items += [Item(post, 'frame', 'back', spec3d=lat_machine(seat_h, sc, top)),
                      Item(seat, 'pad', 'back', collider=('box', sc, [X, Y, Z], [15.0, 3.5, 20.0]), spec3d=[]),
                      Item(thigh_pad, 'pad', 'back', collider=('box', tc, [X, Y, Z], [5.0, 4.0, 24.0]), spec3d=[])]
            return items

        return pose, PULL, equip
    return build


pulldown('latPulldowns', 44.0, (0.2, -1.0, 1.4), ['lats'])
pulldown('cablePulldowns', 9.0, (0.8, -1.0, 0.5), ['lats', 'biceps'], fwd=17.0)


@exercise('muscleUps', 'back', 'side', muscles=['lats', 'triceps'], floor=False)
def muscle_ups():
    bar = v3(0.0, BAR_Y, 0.0)
    grip = 28.0
    hang_y = BAR_Y - math.sqrt((ARM - 0.4) ** 2 - (grip - SHOULDER_HALF) ** 2)

    def body(sx, sy, pitch, pole, legs_hip=6.0, knee=10.0, neck=0.0):
        th = math.radians(pitch)
        P = v3(sx - math.sin(th) * TORSO, sy - math.cos(th) * TORSO)
        p = {'pelvis': P, 'pitch': pitch, 'neck': neck}
        for s in 'LR':
            p['leg' + s] = {'hip': legs_hip, 'abd': 1.0, 'knee': knee, 'ankle': 25.0}
        p.update(both(v3(bar[0] + 1.0, bar[1], grip), list(pole)))
        return p

    def on_bar(pitch, below, pole, **kw):
        """The body goes round the bar, never through it: the torso, leaning `pitch`, rests with its
        front against the bar `below` cm under the shoulders (the chest after the pull, the belly
        in the turn)."""
        th = math.radians(pitch)
        up, fwd = v3(math.sin(th), math.cos(th)), v3(math.cos(th), -math.sin(th))
        S = bar - fwd * 13.5 + up * below
        return body(S[0], S[1], pitch, pole, **kw)

    pull = dict(pitch=-10.0, below=15.0, pole=np.array([-1.0, -0.6, 0.5]), legs_hip=22.0, knee=20.0, neck=6.0)
    turn = dict(pitch=40.0, below=22.0, pole=np.array([-1.0, 0.6, 0.4]), legs_hip=16.0, knee=18.0, neck=-6.0)
    k_hang = body(-3.0, hang_y, -4.0, (0.5, -1.0, 0.6), legs_hip=4.0)
    k_swing = body(-12.0, hang_y + 6.0, -14.0, (0.3, -1.0, 0.6), legs_hip=28.0, knee=14.0)
    k_pull = on_bar(**pull)
    k_turn = on_bar(**turn)
    # support on straight arms: leaning forward over the bar, so the hips stay behind it and the bar
    # rests against the front of the thighs
    k_top = body(4.0, BAR_Y + ARM - 5.0, 18.0, (-1.0, 0.1, 0.4), legs_hip=2.0, knee=6.0)
    rise = keys(k_hang, k_swing, k_pull, spans=[0.18, 0.28])

    def f(u):
        if u <= 0.46:
            return rise(u)
        if u <= 0.68:
            # the turn rolls the torso over the bar, keeping it against the bar all the way
            return on_bar(**blend(pull, turn, (u - 0.46) / 0.22))
        return blend(k_turn, k_top, (u - 0.68) / 0.32)

    def equip(J, v, u):
        # seen end-on, the bar's end is in front of the figure (it shows the body going round it)
        return eq.fixed_bar(v, bar)

    tl = Timeline([(0.6, 0, 0), (0.55, 0, 0.18), (0.45, 0.18, 0.46), (0.35, 0.46, 0.68), (0.45, 0.68, 1.0),
                   (0.5, 1, 1), (1.6, 1, 0)] * 2)
    return f, tl, equip


ROPE_LO, ROPE_HI = 10.0, 300.0      # the climbing rope in 3D: just past both edges of the picture


class Rounds(Cycle):
    """A Cycle that counts its cycles: the phase runs from 0 to `cycles` over the loop (u % 1 is the
    cycle's own phase), so something can keep moving through all of them."""

    def __call__(self, t):
        return (t % self.total) / self.period


def climbing_rope3d(rope_x, off):
    """The climbing rope in 3D, one piece: the rope, hanging from a beam above the climber's reach and
    ending just above the floor (left out of the framing, it runs off the picture as in 2D), and its
    markers every 30 cm, scrolled down by `off` as the 2D ones. Each marker
    keeps its place in a 3 m loop as it scrolls, so the app, which interpolates between frames,
    moves it smoothly; near the rope's ends it shrinks into the rope (hidden) and wraps round."""
    spec = eq.rod3d(v3(rope_x, ROPE_LO, 0.0), v3(rope_x, ROPE_HI, 0.0), 2.2, 'frame')
    spec += eq.rod3d(v3(rope_x, ROPE_HI, -40.0), v3(rope_x, ROPE_HI, 40.0), 3.0, 'frame')
    for j in range(10):
        y = 300.0 - (30.0 * j + off) % 300.0
        f = smooth(ROPE_LO + 2.0, 20.0, y) * (1.0 - smooth(292.0, ROPE_HI - 2.0, y))
        y = min(max(y, ROPE_LO + 2.0), ROPE_HI - 2.0)
        spec += eq.cyl3d(v3(rope_x, y, 0.0), Y, 2.0 + 0.8 * f, 1.0, 'plate_rim')
    return spec


@exercise('ropeClimbs', 'back', 'side', muscles=['lats', 'biceps'], floor=False)
def rope_climbs():
    rope_x = 12.0
    period = 1.6
    cycles = 4
    bob = 11.0                       # the hips sink as the reaching hand goes up
    scroll = 300.0 / cycles          # the rope runs down 3 m per loop: the markers' 30 cm and the 3D
    #                                  rope's 3 m marker loop come round with it, and the gripping hand
    #                                  (40 cm a stroke, two strokes a cycle) slides little

    def pose(u):
        # u in [0,1) is the climbing cycle: reach with one hand, pull, pinch the feet, stand up
        ph = u % 1.0
        side_up = 'R' if ph < 0.5 else 'L'
        q = (ph % 0.5) / 0.5
        base_y = 150.0 - bob * (0.5 - 0.5 * math.cos(2 * math.pi * ph))
        P = v3(-8.0, base_y, 0.0)
        p = {'pelvis': P, 'pitch': -6.0, 'neck': 6.0}
        knee_up = 0.5 - 0.5 * math.cos(2 * math.pi * ph)
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'hip': 40.0 + 30.0 * knee_up, 'abd': 2.0, 'knee': 50.0 + 45.0 * knee_up, 'ankle': 20.0}
        hi = P[1] + TORSO + 52.0
        lo = P[1] + TORSO + 12.0
        for s, sg in (('L', -1), ('R', 1)):
            up = (s == side_up)
            y = lerp(lo, hi, ease(q)) if up else lerp(hi, lo, ease(q))
            p['arm' + s] = {'hand': v3(rope_x, y, sg * 3.0), 'pole': np.array([-0.3, -1.0, 0.7 * sg])}
        return p

    def equip(J, v, u):
        cam = v.cam
        # the rope hangs on the midline, between the hands (z = -3 and +3) and between the legs: in
        # front of the far arm and leg, behind the near ones
        d = cam.depth(v3(rope_x, 0.0, 0.0))
        lo, hi = v3(rope_x, -40.0, 0), v3(rope_x, 400.0, 0)
        off = u * scroll
        items = [Item(Cone(cam.p(lo), cam.p(hi), 2.2), 'frame', frame=False, depth=d,
                      collider=('capsule', lo, hi, 2.2), grip=True, spec3d=climbing_rope3d(rope_x, off),
                      frame3d=False)]
        for k in range(-3, 12):
            y = 30.0 * k - off % 30.0
            items.append(Item(RBox(cam.p(v3(rope_x, y, 0)), 2.8, 1.0, 1.0), 'plate_rim', frame=False, depth=d,
                              spec3d=[]))
        return items

    return pose, Rounds(period, cycles), equip


def inverted_row(key, bar_y, rings=False, muscles=('lats', 'biceps'), sternum=9.0, chest=14.0):
    """A rigid body pivoting on the ankles (heels down, toes up), pulled from hanging (arms straight)
    until the lower chest meets the bar. The setup is solved from that top: the bar touches the
    chest `sternum` cm below the shoulder line (`chest` cm from the body's centre line), and the
    ankles sit where that straight body line meets the floor. The bottom is where the arms are
    straight again; the hands never leave the bar and the feet never move."""
    @exercise(key, 'back', 'side', muscles=list(muscles))
    def build():
        grip = 24.0
        hx = 0.0
        B = v3(hx, bar_y)
        reach = math.sqrt((ARM - 0.4) ** 2 - (grip - SHOULDER_HALF) ** 2)
        LEG = SHANK + THIGH - 0.5                # just short of locked, so the ankles never drag
        ANK_Y = 9.0                              # ankle height with the heel down, toes up
        # the body pivots on the ankles. Top: B = A + d*(LEG + TORSO - sternum) + n*chest, with d
        # the body line, n its chest side and the ankle A at ANK_Y
        along = LEG + TORSO - sternum
        R = math.hypot(along, chest)
        a_top = math.asin((bar_y - ANK_Y) / R) - math.atan2(chest, along)
        d_top = v3(math.cos(a_top), math.sin(a_top))
        n_top = v3(-math.sin(a_top), math.cos(a_top))
        ank = B - d_top * along - n_top * chest
        ank = v3(ank[0], ANK_Y)

        def arm_gap(a):
            S = ank + v3(math.cos(a), math.sin(a)) * (LEG + TORSO)
            return float(np.linalg.norm(S - B)) - reach

        lo, hi = math.radians(0.0), a_top
        for _ in range(60):                     # bottom: lowered until the arms hang straight
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if arm_gap(mid) > 0 else (lo, mid)
        a_bot = hi

        def pose(u):
            # a rigid body line pivoting at the ankles; the hands never leave the bar
            a = lerp(a_bot, a_top, u)
            d = v3(math.cos(a), math.sin(a))
            P = ank + d * LEG
            S = P + d * TORSO
            # face up with the head to the right: turned round (p_yaw 180), then tipped back. The
            # turn swaps the figure's left and right in the world, so the right foot and hand go to
            # -z and the left ones to +z (otherwise the limbs cross through each other)
            p = {'pelvis': P, 'p_yaw': 180.0, 'pitch': math.degrees(a) - 90.0, 'neck': 4.0}
            for s, sg in (('L', 1), ('R', -1)):
                p['leg' + s] = {'foot': v3(ank[0], ank[1], sg * 9.0), 'foot_pitch': 70.0,
                                'pole': v3(0.0, 1.0, 0.0)}
            p.update(both(v3(hx, bar_y, -grip), [0.3, -1.0, -0.6]))
            return p

        def equip(J, v, u):
            cam = v.cam
            if rings:
                from .pushup import rings_items
                # in 3D the straps hang from a beam just above the picture's top edge (y 194.3)
                return rings_items(v, J, top_y=320.0, beam_y=199.5)
            # 3D: the bar across a rack, an upright at each end
            spec = [('cyl', v3(hx, bar_y, 0.0), Z, 2.3, 60.0, 'metal', True)]
            spec += [('cap', v3(hx, 1.0, s * 60.0), v3(hx, bar_y, s * 60.0), 2.6, 'frame', False) for s in (-1, 1)]
            return [Item(RBox(cam.p(v3(hx, bar_y / 2)), 2.6, bar_y / 2, 2.0), 'frame', 'back', spec3d=spec),
                    Item(Circle(cam.p(v3(hx, bar_y)), 2.8), 'metal', 'back',
                         collider=('capsule', v3(hx, bar_y, -60.0), v3(hx, bar_y, 60.0), 2.3), grip=True,
                         spec3d=[])]

        return pose, PULL, equip
    return build


inverted_row('australianPullups', 96.0)
inverted_row('ringRows', 100.0, rings=True)
