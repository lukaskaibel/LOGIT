"""Lying presses and flyes on a bench (or the floor). Side view, head to the left."""
from .common import *
from ..rig import solve
from ..spec import R_HAND, R_UPPER

PX = 0.0                    # pelvis x
BACK = 11.5                 # the torso's centreline (and the hip joint) above the pad it lies on
PY = BENCH_H + BACK         # pelvis (hip joint) height lying on the bench


def lying(pitch=-90.0, py=PY, px=PX, feet=(44.0, ANKLE_H), hook=False, knee_up=True):
    """Supine pose frame. pitch -90 = flat; larger (e.g. -55) = inclined (head up)."""
    pose = {'pelvis': v3(px, py, 0.0), 'pitch': pitch, 'neck': 0.0}
    for s, sg in (('L', -1), ('R', 1)):
        pose['leg' + s] = {'foot': v3(px + feet[0], feet[1], sg * 22.0), 'toe_out': 10.0,
                           'pole': v3(0.3, 1.0, 0.35 * sg) if knee_up else v3(1.0, 0.2, 0.2 * sg)}
    return pose


def shoulders(pose):
    return torso_point(pose['pelvis'], pose['pitch'], 0.0, TORSO)


def chest_point(pose, along=36.0, out=14.0):
    """A point on the front of the chest (torso-local forward/up)."""
    return torso_point(pose['pelvis'], pose['pitch'], out, along)


def bench_flat(v, px=PX, top=BENCH_H, head_end=-96.0):
    """A flat bench from head_end (relative to the hips) to under the thighs."""
    return eq.bench(v, v3(px + (head_end + 28.0) / 2, top, 0.0), length=28.0 - head_end)


def bench_incline(v, pitch=-54.0, px=PX, py=PY, seat_len=36.0, back_len=86.0, z='back'):
    """An adjustable bench with the back rest raised under the back of a torso lying at `pitch`: the
    seat top BACK below the hip joint, the back rest's top surface BACK under the spine, hinged where
    the two meet, just behind the hips. (eq.bench's incline hinges the back rest at the seat's far
    end, which runs it through the lifter sitting on the seat.)"""
    cam = v.cam
    th = math.radians(pitch)
    up = v3(math.sin(th), math.cos(th))              # up the back rest, towards the head
    n = v3(math.cos(th), -math.sin(th))              # its front, towards the lifter
    top = py - BACK
    q = v3(px, py) - n * BACK                        # on the back rest's surface, beside the hips
    hinge = q + up * ((top - q[1]) / up[1])          # ... where it meets the seat
    front = hinge + X * seat_len
    tip = hinge + up * back_len
    pads = [eq.pad(cam, hinge - X * 2.0, front), eq.pad(cam, hinge, tip)]
    cols = [eq.pad_box(hinge - X * 2.0, front), eq.pad_box(hinge, tip)]
    # a post under the front of the seat, a rear leg up into the back rest, a rail between them
    rear = hinge + up * (back_len * 0.45) - n * eq.PAD_T
    frame = eq.post(cam, front - X * 9.0 - Y * eq.PAD_T) + eq.post(cam, rear)
    rail = hinge - Y * eq.PAD_T, v3(rear[0], top - eq.PAD_T, 0.0)
    frame.append(Cone(cam.p(rail[0]), cam.p(rail[1]), 1.8))
    fspec = eq.post3d(front - X * 9.0 - Y * eq.PAD_T) + eq.post3d(rear) + eq.rod3d(*rail, 1.8)
    pspec = eq.pad3d(hinge - X * 2.0, front) + eq.pad3d(hinge, tip)
    return [Item(Union(frame), 'frame', z, spec3d=fspec), Item(Union(pads), 'pad', z, collider=cols, spec3d=pspec)]


DECLINE = 15.0


def bench_decline(v, px=PX, top=BENCH_H):
    return eq.bench(v, v3(px - 26.0, top, 0.0), length=124.0, decline=DECLINE)


def decline_py(px=PX):
    return BENCH_H + (px + 26.0) * math.tan(math.radians(DECLINE)) + BACK


def bar_press(key, group, muscles, pitch=-90.0, grip=40.0, top_ofs=0.0, chest_along=36.0,
              elbow_pole=(0.25, -1.0, 0.85), bench='flat', lower=1.6, press=1.25, floor=False,
              touch_out=14.5, bar_to=None):
    @exercise(key, group, 'side', muscles=muscles)
    def build():
        py = 12.0 if floor else (decline_py() if bench == 'decline' else PY)
        if bench == 'decline':
            # the backs of the lower legs rest on the leg hook's roller, the feet hooked over it
            base = lying(pitch, py=py, feet=(53.0, 75.0), knee_up=True)
        else:
            base = lying(pitch, py=py, feet=(44.0, ANKLE_H) if not floor else (40.0, ANKLE_H))
        S = shoulders(base)
        reach = math.sqrt((ARM - 0.6) ** 2 - (grip - SHOULDER_HALF) ** 2)
        up_dir = v3(math.cos(math.radians(pitch + 90.0)), math.sin(math.radians(pitch + 90.0)))
        # "up" for the lifter = the torso's forward axis
        th = math.radians(pitch)
        fwd = v3(math.cos(th), -math.sin(th))
        top = S + fwd * reach + v3(top_ofs, 0)
        if bar_to is not None:
            low = torso_point(base['pelvis'], pitch, *bar_to)
        else:
            low = chest_point(base, chest_along, touch_out)

        def pose(u):
            b = top + (low - top) * u
            # J-curve: the bar drifts towards the feet on the way down
            b = b + fwd * 0.0
            p = dict(base)
            p.update(both(v3(b[0], b[1], grip), list(elbow_pole)))
            return p

        def equip(J, v, u):
            B = (J.p['handL'] + J.p['handR']) / 2
            items = [] if floor else (bench_flat(v) if bench == 'flat' else bench_incline(v, pitch) if bench == 'incline'
                                      else bench_decline(v))
            return items + eq.barbell(v, v3(B[0], B[1], 0.0))

        return pose, rep_down_first(lower, press, top=0.45, bottom=0.2), equip
    return build


def dumbbells(v, J, axis=Z, axes=None):
    """A dumbbell in each hand. In the side view the near one sits in front of its hand."""
    items = []
    near = 'R' if v.cam.depth(J.p['handR']) >= v.cam.depth(J.p['handL']) else 'L'
    for s in 'LR':
        ax = axes[s] if axes else axis
        if v.cam.kind == 'side':
            z = 'front' if s == near else ('before', 'arm' + s)
        else:
            z = ('before', 'arm' + s)
        items += eq.dumbbell(v, J.p['hand' + s], ax, z)
    return items


def elbows_on_floor(base, hand, pole):
    """The hand target (raised from `hand`) at which the elbows come down onto the floor: the upper
    arm's underside touches it there, so a floor press stops where the floor stops the elbows."""
    lo, hi = float(hand[1]), float(hand[1]) + 60.0
    for _ in range(40):
        mid = (lo + hi) / 2
        p = dict(base)
        p.update(both(v3(hand[0], mid, hand[2]), list(pole)))
        if solve(p).p['elbowR'][1] - R_UPPER[1] < 0.0:
            lo = mid
        else:
            hi = mid
    return v3(hand[0], hi, hand[2])


def db_press(key, group, muscles, pitch=-90.0, bench='flat', floor=False, top_z=30.0, low_z=44.0,
             low_along=34.0, low_out=10.0, pole=(0.25, -1.0, 0.9), lower=1.6, press=1.25, axis=Z):
    @exercise(key, group, 'side', muscles=muscles)
    def build():
        py = 12.0 if floor else PY
        base = lying(pitch, py=py, feet=(40.0 if floor else 44.0, ANKLE_H))
        S = shoulders(base)
        th = math.radians(pitch)
        fwd = v3(math.cos(th), -math.sin(th))
        reach = math.sqrt((ARM - 1.0) ** 2 - (top_z - SHOULDER_HALF) ** 2)
        top = S + fwd * reach
        low = torso_point(base['pelvis'], pitch, low_out, low_along)
        if floor:
            low = elbows_on_floor(base, v3(low[0], low[1], low_z), pole)

        def pose(u):
            b = top + (low - top) * u
            z = lerp(top_z, low_z, u)
            p = dict(base)
            p.update(both(v3(b[0], b[1], z), list(pole)))
            return p

        def equip(J, v, u):
            items = [] if floor else (bench_flat(v) if bench == 'flat' else bench_incline(v, pitch))
            return items + dumbbells(v, J, axis)

        return pose, rep_down_first(lower, press, top=0.45, bottom=0.2), equip
    return build


db_press('dumbbellBenchPress', 'chest', ['pecs'])
db_press('inclinedDumbbellBenchPress', 'chest', ['pecs'], pitch=-54.0, bench='incline', low_along=39.0)
db_press('dumbbellFloorPress', 'chest', ['pecs'], floor=True, low_out=8.0, low_z=40.0)
db_press('tatePress', 'triceps', ['triceps'], top_z=26.0, low_z=30.0, low_along=34.0, low_out=19.0,
         pole=(0.0, 0.2, 1.0))


# Flyes open the arms sideways, straight at a side camera, where the arc foreshortens and the arm
# covers the chest. From above (flat) and from the front (incline) the arc is in the picture.
@exercise('dumbbellFly', 'chest', 'top', muscles=['pecs'], floor=False)
def dumbbell_fly():
    base = lying(-90.0)
    S = shoulders(base)
    top = v3(S[0] + 4.0, S[1] + 56.0, 12.0)
    low = v3(S[0] + 6.0, S[1] + 6.0, 62.0)

    def pose(u):
        a = math.radians(lerp(0.0, 82.0, u))                  # arms open around the shoulder
        r = lerp(56.0, 56.0, u)
        hand = v3(S[0] + lerp(4.0, 7.0, u), S[1] + r * math.cos(a), SHOULDER_HALF + r * math.sin(a) - lerp(6.0, 0, u))
        p = dict(base)
        p.update(both(hand, [0.0, -0.4, 1.0]))
        return p

    def equip(J, v, u):
        return bench_flat(v) + dumbbells(v, J, X)

    return pose, rep_down_first(1.7, 1.4, top=0.45, bottom=0.2), equip


@exercise('dumbbellPullover', 'chest', 'side', muscles=['pecs', 'lats'])
def dumbbell_pullover():
    base = lying(-90.0)
    S = shoulders(base)

    def pose(u):
        a = math.radians(lerp(8.0, 118.0, u))                  # from over the chest to behind the head
        r = 55.0
        hand = v3(S[0] - r * math.sin(a), S[1] + r * math.cos(a), 5.0)
        p = dict(base)
        # the soft elbows point out and back the way the arms came: towards the feet over the chest,
        # up at the ceiling behind the head (never down, which the elbow can't bend)
        p.update(both(hand, [0.45 * math.cos(a), 0.45 * math.sin(a), 0.8]))
        return p

    def equip(J, v, u):
        # both palms cup the inside of the far head, the handle and near head hang between the
        # forearms; at the midline, so behind the near arm and in front of the far one. The head
        # lies at the end of the bench, so the arms and the weight can go down past it.
        H = (J.p['handL'] + J.p['handR']) / 2
        e = (J.p['elbowL'] + J.p['elbowR']) / 2
        ax = unit(H - e)
        return bench_flat(v, head_end=-77.0) + eq.dumbbell(v, H - ax * 3.9, ax, ('before', 'armR'))

    return pose, rep_down_first(1.8, 1.5, top=0.45, bottom=0.25), equip


@exercise('skullCrushers', 'triceps', 'side', muscles=['triceps'])
def skull_crushers():
    base = lying(-90.0)
    S = shoulders(base)
    head = torso_point(base['pelvis'], -90.0, 3.0, 71.0)

    def pose(u):
        # upper arms stay put, tipped slightly towards the head; forearms fold down until the bar
        # is just short of the forehead (111 degrees leaves it a centimetre clear of the head)
        el_tilt = math.radians(12.0)
        E = S + v3(-math.sin(el_tilt), math.cos(el_tilt)) * UPPER
        a = math.radians(lerp(0.0, 111.0, u))
        d = v3(-math.sin(el_tilt + a), math.cos(el_tilt + a))
        hand = E + d * FORE
        p = dict(base)
        p.update(both(v3(hand[0], hand[1], 16.0), [1.0, 0.3, 0.2]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return bench_flat(v) + eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=14.0)

    return pose, rep_down_first(1.5, 1.2, top=0.45, bottom=0.2), equip


@exercise('inclineCableFly', 'chest', 'front', muscles=['pecs'])
def incline_cable_fly():
    pitch = -54.0
    base = lying(pitch)
    S = shoulders(base)
    th = math.radians(pitch)
    fwd = v3(math.cos(th), -math.sin(th))

    def pose(u):
        a = math.radians(lerp(0.0, 78.0, u))
        r = 56.0
        c = S + fwd * (r * math.cos(a))
        hand = v3(c[0] + 3.0, c[1], SHOULDER_HALF + r * math.sin(a) - lerp(6.0, 0.0, u))
        p = dict(base)
        p.update(both(hand, [0.0, -0.4, 1.0]))
        return p

    def equip(J, v, u):
        # a low pulley on a tower at each side of the bench. With the hands together the cable
        # climbs to the fist nearer the camera than the arm (which reaches back to the shoulder),
        # so it's drawn over the arm, up to where it enters the fist.
        items = bench_incline(v, pitch)
        for s, sg in (('L', -1.0), ('R', 1.0)):
            pulley, hand = v3(S[0] + 12.0, 12.0, sg * 82.0), J.p['hand' + s]
            d = unit(pulley - hand)
            end = hand + d * ((R_HAND - 0.6) / max(float(np.linalg.norm(v.cam.d(d))), 0.3))
            items += eq.cable_stack(v, pulley, end, z=('after', 'arm' + s), mount=X)
        return items

    return pose, rep_down_first(1.7, 1.4, top=0.45, bottom=0.2), equip


bar_press('barbellBenchPress', 'chest', ['pecs'])
bar_press('reverseGripBenchPress', 'chest', ['pecs'], grip=34.0, chest_along=31.0)
bar_press('closeGripBenchPress', 'triceps', ['triceps'], grip=22.0, elbow_pole=(0.9, -1.0, 0.3))
bar_press('inclinedBarbellBenchPress', 'chest', ['pecs'], pitch=-54.0, bench='incline', chest_along=41.0)
bar_press('declineBenchPress', 'chest', ['pecs'], pitch=-104.0, bench='decline', chest_along=33.0)
bar_press('jmPress', 'triceps', ['triceps'], grip=24.0, elbow_pole=(1.0, -0.2, 0.3), bar_to=(19.0, 55.0))
