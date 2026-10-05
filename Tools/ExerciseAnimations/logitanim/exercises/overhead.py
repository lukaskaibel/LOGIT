"""Overhead pressing."""
from .common import *


@exercise('dumbbellShoulderPress', 'shoulders', 'front', muscles=['delts'])
def dumbbell_shoulder_press():
    def hands(u):
        return v3(lerp(5.0, 3.0, u), lerp(159.5, SH_Y + 60.6, u), lerp(45.0, 22.0, u ** 1.35))

    def pose(u):
        return standing(0.0, half=10.6, hands=hands(u), arm_pole=[0.1, -1.0, 0.6])

    def equip(J, v, u):
        items = []
        for s in 'LR':
            items += eq.dumbbell(v, J.p['hand' + s], Z, ('before', 'arm' + s))
        return items

    return pose, Timeline([(0.5, 0, 0), (1.2, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2), equip


PRESS = Timeline([(0.5, 0, 0), (1.2, 0, 1), (0.35, 1, 1), (1.5, 1, 0)] * 2)


def front_press_path(S, reach, u, rack_y=5.0):
    """Bar from the front rack to overhead, around the face: it rises in front of the face and
    only comes back over the shoulders once it is past the forehead, while the chin comes up (the
    head moves back) as it passes. Returns (bar x, bar y, neck)."""
    y = lerp(S[1] + rack_y, S[1] + reach, u)
    x = lerp(S[0] + 12.0, S[0] + 1.0, smooth(0.42, 0.95, u))
    passing = math.sin(math.pi * min(max((u - 0.05) / 0.6, 0.0), 1.0))
    return x, y, 20.0 * passing


@exercise('militaryPress', 'shoulders', 'side', muscles=['delts', 'triceps'])
def military_press():
    grip = 26.0
    reach = math.sqrt((ARM - 0.8) ** 2 - (grip - SHOULDER_HALF) ** 2)

    def pose(u):
        base = standing(0.0, half=12.0)
        S = shoulder_at(base['pelvis'], 0.0)
        x, y, neck = front_press_path(S, reach, u)
        passing = neck / 20.0
        base['neck'] = neck
        base['pelvis'] = base['pelvis'] + v3(-0.8 * passing, 0, 0)
        pole = [lerp(1.0, 0.2, u), -1.0, lerp(0.35, 0.9, u)]
        base.update(both(v3(x, y, grip), pole))
        return base

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)     # racked: the face stays readable

    return pose, PRESS, equip


@exercise('shoulderPress', 'shoulders', 'front', muscles=['delts', 'triceps'])
def shoulder_press():
    grip = 28.0
    reach = math.sqrt((ARM - 0.8) ** 2 - (grip - SHOULDER_HALF) ** 2)

    def pose(u):
        base = standing(0.0, half=12.0)
        S = shoulder_at(base['pelvis'], 0.0)
        x, y, base['neck'] = front_press_path(S, reach, u, rack_y=6.0)
        base.update(both(v3(x, y, grip), [lerp(1.0, 0.1, u), -1.0, lerp(0.35, 0.9, u)]))
        return base

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), z_front=('after', 'head'))

    return pose, PRESS, equip


def upright_seat(v, x=0.0, seat_h=BENCH_H, back_h=62.0, widths3d=(28.0, 28.0)):
    """Bench with a vertical back rest, drawn for any camera. widths3d: the seat's and the back
    rest's widths in 3D (a machine's seat is wider than a bench; side-on the width doesn't show)."""
    cam = v.cam
    seat_ab = v3(x - 16.0, seat_h, 0.0), v3(x + 20.0, seat_h, 0.0)
    back_ab = v3(x - 14.0, seat_h + 2.0, 0.0), v3(x - 14.0, seat_h + back_h, 0.0)
    seat = eq.pad(cam, *seat_ab)
    back = eq.pad(cam, *back_ab, up3=X)
    legs = v3(x - 4.0, seat_h - 7.0, 0.0), v3(x + 12.0, seat_h - 7.0, 0.0)
    frame = eq.post(cam, legs[0]) + eq.post(cam, legs[1])
    return [Item(Union(frame), 'frame', 'back', spec3d=eq.post3d(legs[0]) + eq.post3d(legs[1])),
            Item(Union([seat, back]), 'pad', 'back', collider=[eq.pad_box(*seat_ab), eq.pad_box(*back_ab, up3=X)],
                 spec3d=eq.pad3d(*seat_ab, width=widths3d[0]) + eq.pad3d(*back_ab, up3=X, width=widths3d[1]))]


@exercise('seatedDumbbellPress', 'shoulders', 'front', muscles=['delts'])
def seated_dumbbell_press():
    def pose(u):
        sy = BENCH_H + 9.0 + TORSO
        hand = v3(lerp(5.0, 3.0, u), lerp(sy + 15.0, sy + 60.6, u), lerp(45.0, 22.0, u ** 1.35))
        return seated(0.0, hands=hand, arm_pole=[0.1, -1.0, 0.6], half=16.0)

    def equip(J, v, u):
        items = upright_seat(v)
        for s in 'LR':
            items += eq.dumbbell(v, J.p['hand' + s], Z, ('before', 'arm' + s))
        return items

    return pose, PRESS, equip


@exercise('arnoldPress', 'shoulders', 'front', muscles=['delts'])
def arnold_press():
    def pose(u):
        # start: dumbbells in front of the chin, palms facing the body, elbows in front, the inner
        # heads just apart. The elbows swing out first, so the dumbbells travel out past the sides
        # of the head (never through the face) before they rise, and come together above it
        e = smooth(0.0, 0.7, u)
        w = 1.0 - (1.0 - min(u / 0.9, 1.0)) ** 2
        hand = v3(lerp(18.0, 3.0, e), lerp(148.0, SH_Y + 60.6, smooth(0.04, 1.0, u)),
                  lerp(18.0, 22.0, u) + 14.0 * math.sin(math.pi * w))
        pole = [lerp(1.0, 0.1, e), -1.0, lerp(0.05, 0.7, e)]
        return standing(0.0, half=11.0, hands=hand, arm_pole=pole)

    def equip(J, v, u):
        # the palms turn from facing the body to facing forward (through facing out), so the
        # handle turns half a turn about the forearm, square to it: the thumb end leads forward
        th = math.pi * smooth(0.05, 0.9, u)
        items = []
        for s, sg in (('L', -1.0), ('R', 1.0)):
            fore = unit(J.p['hand' + s] - J.p['elbow' + s])
            ax = v3(math.sin(th), 0.0, sg * math.cos(th))
            ax = unit(ax - np.dot(ax, fore) * fore)
            items += eq.dumbbell(v, J.p['hand' + s], ax, ('before', 'arm' + s))
        return items

    return pose, Timeline([(0.5, 0, 0), (1.4, 0, 1), (0.35, 1, 1), (1.6, 1, 0)] * 2), equip


@exercise('behindTheNeckPress', 'shoulders', 'back', muscles=['delts', 'triceps'])
def behind_the_neck_press():
    grip = 36.0
    reach = math.sqrt((ARM - 0.8) ** 2 - (grip - SHOULDER_HALF) ** 2)

    def pose(u):
        base = standing(0.0, half=12.0)
        S = shoulder_at(base['pelvis'], 0.0)
        y = lerp(S[1] + 7.0, S[1] + reach, u)
        # the bar travels behind the head: the chin is tucked (the head forward) until the bar is
        # past it, then the head comes back through
        base['neck'] = -20.0 * (1.0 - smooth(0.5, 0.8, u))
        base.update(both(v3(S[0] - 7.0, y, grip), [-0.2, -1.0, 0.8]))
        return base

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), z_front=('after', 'head'))

    return pose, PRESS, equip


@exercise('machineShoulderPress', 'shoulders', 'side', muscles=['delts', 'triceps'])
def machine_shoulder_press():
    pivot = v3(-40.0, 214.0)

    def at(swing, u):
        sy = BENCH_H + 9.0 + TORSO
        # the handles travel on the lever's arc around the pivot behind the head
        a0 = math.atan2(sy + 8.0 - pivot[1], 10.0 - pivot[0])
        L = math.hypot(10.0 - pivot[0], sy + 8.0 - pivot[1])
        a = a0 + lerp(0.0, swing, u)
        h = pivot + L * v3(math.cos(a), math.sin(a))
        return seated(0.0, hands=v3(h[0], h[1], 30.0), arm_pole=[0.8, -1.0, 0.5], half=16.0)

    # pressed up to where the arms are straight: past it the hands would leave the handles and the
    # lever, drawn to the hands, would shrink
    swing = reach_limit(lambda x: at(x, 1.0), 0.0, 0.62)

    def pose(u):
        return at(swing, u)

    def equip(J, v, u):
        items = upright_seat(v, back_h=70.0, widths3d=(35.0, 30.0))
        cam = v.cam
        h = J.p['handL']
        # the lever drawn is the far one: it runs beside the head at the far handle's width (a
        # single lever down the middle would pass through the head); the near one is left out
        a3, b3 = v3(pivot[0], pivot[1], h[2]), v3(h[0], h[1], h[2])
        lever = Cone(cam.p(a3), cam.p(b3), 2.0)
        column = v3(pivot[0], pivot[1] / 2 + 2.0)
        items.append(Item(RBox(cam.p(column), 3.2, pivot[1] / 2, 2.0), 'frame', 'back',
                          spec3d=eq.box3d(column, X, Y, Z, 3.2, pivot[1] / 2, 3.2, 2.0, 'frame')))
        # 3D: both levers (each with its handle, below), on an axle through the column's top
        items.append(Item(lever, 'metal', 'back', collider=('capsule', a3, b3, 2.0), grip=True, spec3d=[]))
        out = max(abs(J.p['hand' + s][2]) for s in 'LR') + 8.0         # the levers' planes, beside the fists
        items.append(Item(Circle(cam.p(pivot), 3.6), 'metal', 'back',
                          spec3d=eq.cyl3d(v3(pivot[0], pivot[1], 0.0), Z, 3.6, out + 2.5, 'metal')))
        near = 'R'
        for s, sg in (('L', -1.0), ('R', 1.0)):
            z = 'front' if s == near else ('before', 'arm' + s)
            hs = J.p['hand' + s]
            # 3D: the lever runs down beside the fist to a boss (side-on, the drawing's ring) carrying
            # the grip, which runs in through the fist
            end = v3(hs[0], hs[1], sg * out)
            spec = (eq.rod3d(v3(pivot[0], pivot[1], sg * out), end, 2.0, 'metal')
                    + eq.cyl3d(end - Z * sg * 1.0, Z, 3.4, 1.5, 'metal', True)
                    + eq.rod3d(end - Z * sg * 1.0, hs - Z * sg * 8.0, 1.7, 'metal'))
            items.append(Item(Circle(cam.p(hs), 3.4), 'metal', z, gap=(s == near), spec3d=spec))
        return items

    return pose, PRESS, equip


@exercise('singleArmKettlebellPress', 'shoulders', 'front', muscles=['delts', 'triceps'])
def single_arm_kettlebell_press():
    def pose(u):
        p = standing(0.0, half=11.0)
        rack = v3(10.0, SH_Y + 6.0, 21.0)
        top = v3(2.0, SH_Y + 60.0, 21.0)
        h = rack + (top - rack) * u
        p['armR'] = {'hand': h, 'pole': np.array([lerp(1.0, 0.2, u), -1.0, lerp(0.2, 0.7, u)])}
        p['armL'] = {'flex': 0.0, 'abd': lerp(10.0, 22.0, u), 'elbow': 6.0}
        p['roll'] = lerp(0.0, -2.5, u)
        return p

    def equip(J, v, u):
        # in the rack the bell sits on the outside of the forearm (not down inside the elbow's
        # crook); pressed, it rolls round to rest on the back of the forearm
        down = unit(v3(-0.3, -0.1, 0.95) * (1 - u) + v3(-0.95, -0.3, 0.0) * u)
        return eq.kettlebell(v, J.p['handR'], down, ('before', 'armR'))

    return pose, PRESS, equip


@exercise('landminePress', 'chest', 'side', muscles=['pecs', 'delts'])
def landmine_press():
    anchor = v3(150.0, 3.0, 0.0)

    def at(swing, u):
        p = standing(-6.0, half=12.0)
        p['legL'] = dict(p['legL'], foot=v3(-24.0, ANKLE_H, -12.0))      # staggered stance
        p['legR'] = dict(p['legR'], foot=v3(10.0, ANKLE_H, 12.0))
        p['pelvis'] = v3(-6.0, HIP_H - 3.0, 0.0)
        p['pitch'] = 8.0
        S = shoulder_at(p['pelvis'], 8.0)
        start = v3(S[0] + 12.0, S[1] + 2.0)
        L = np.linalg.norm(start - anchor)
        a0 = math.atan2(start[1] - anchor[1], start[0] - anchor[0])
        a = a0 - lerp(0.0, swing, u)
        h = anchor + L * v3(math.cos(a), math.sin(a))
        p['armR'] = {'hand': v3(h[0], h[1], 4.0), 'pole': np.array([0.3, -1.0, 0.5])}
        p['armL'] = {'hand': v3(h[0] - 4.0, h[1] - 4.0, -4.0), 'pole': np.array([0.3, -1.0, -0.5])}
        return p

    # the bar swings on its floor pivot until the arms are straight (further, the hands would leave
    # the bar and the bar, drawn to the hands, would shrink)
    swing = reach_limit(lambda x: at(x, 1.0), 0.0, 0.3)

    def pose(u):
        return at(swing, u)

    def equip(J, v, u):
        cam = v.cam
        h = J.p['handR']
        d = unit(v3(h[0], h[1], 0.0) - anchor)
        tip = v3(h[0], h[1], 0.0) + d * 6.0
        bar = Cone(cam.p(anchor), cam.p(tip), 1.6)
        # the plate sits on the sleeve a hand's length below the grip (closer, the forearms go
        # through it); it lies on the midline, so it is in front of the far arm, behind the near one
        pc = v3(h[0], h[1], 0.0) - d * 28.0
        plate = eq.cyl(cam, pc, d, 16.0, 2.4)
        # 3D: the anchor is a hinge drum lying across the bar's end; the plate turns with the bar
        return [Item(Circle(cam.p(anchor), 4.0), 'frame', 'back', spec3d=eq.cyl3d(anchor, Z, 4.0, 4.0, 'frame')),
                Item(bar, 'metal', ('before', 'armL'), collider=('capsule', anchor, tip, 1.6), grip=True,
                     spec3d=eq.rod3d(anchor, tip, 1.6, 'metal')),
                Item(plate, 'plate_rim', depth=cam.depth(pc), collider=('cylinder', pc, d, 16.0, 2.4),
                     spec3d=eq.plate3d(pc, d, 16.0, 2.4, gap=False))]

    return pose, PRESS, equip
