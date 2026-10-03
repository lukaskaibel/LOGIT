"""Equipment drawn in the same language as the figure: rounded, flat, quiet greys.

Everything is described in 3D and projected by the view's camera, so one definition serves
the side, front and back views. Functions return lists of scene Items.
"""
import math
import numpy as np

from .sdf import V, Circle, Cone, RBox, Union, Subtract, Poly
from .scene import Item
from .rig import unit, v3
from .motion import smooth

X = np.array([1.0, 0, 0])
Y = np.array([0, 1.0, 0])
Z = np.array([0, 0, 1.0])


def cyl(cam, c3, axis3, radius, half_len):
    """Orthographic silhouette of a cylinder as a rounded box."""
    a = cam.d(unit(axis3))
    s = float(np.linalg.norm(a))
    ad = math.sqrt(max(0.0, 1.0 - min(s, 1.0) ** 2))
    along = half_len * s + radius * ad
    angle = math.atan2(a[1], a[0]) if s > 1e-3 else 0.0
    corner = min(radius, max(along, 0.01), radius * ad + min(radius, 1.6))
    return RBox(cam.p(c3), max(along, radius * 0.999 if s < 1e-3 else along), radius, corner, angle)


def endon(cam, axis3):
    return float(np.linalg.norm(cam.d(unit(axis3)))) < 0.35


# ---- free weights ------------------------------------------------------------------------

def barbell(v, c3, axis3=Z, z_front=('after', 'base'), plate_r=22.5, plates=2, sleeve=True, half3d=None):
    """Olympic barbell, placed by real depth (z_front no longer decides the order). Seen end-on it
    is the camera-side plate, in front of whatever lies behind it, arms and chest included (the far
    plate hides behind the figure). Seen along its length it lies at the hands' depth, just behind
    them, so the fists close around it. half3d (3D only): a shorter bar of that half length (a curl
    bar's 60 cm), its sleeves and plates moved in with its ends."""
    cam = v.cam
    c3 = np.asarray(c3, float)
    ax = unit(axis3)
    offs = [70.0 + 5.4 * k for k in range(plates)] if plates else []
    bar_col = ('capsule', c3 - ax * 102.0, c3 + ax * 102.0, 1.5)
    plate_cols = [('cylinder', c3 + ax * s * o, ax, plate_r, 2.5) for s in (-1, 1) for o in offs]
    half, sleeve_c, sleeve_h, offs3 = 102.0, 99.0, 12.0, offs
    if half3d is not None:
        half, sleeve_h = float(half3d), 9.5
        sleeve_c = half - sleeve_h
        offs3 = [half - 2 * sleeve_h + 4.0 + 5.4 * k for k in range(plates)] if plates else []
    spec = [('cyl', c3, ax, 1.5, half, 'metal', True)]
    if sleeve:
        spec += [('cyl', c3 + ax * s * sleeve_c, ax, 2.6, sleeve_h, 'metal', True) for s in (-1, 1)]
    for s in (-1, 1):
        for o in offs3:
            spec += plate3d(c3 + ax * s * o, ax, plate_r, 2.5, gap=True)
    if endon(cam, ax):
        near = ax if cam.depth(ax) >= 0 else -ax
        c = cam.p(c3)
        hidden_bar = Item(None, 'metal', frame=False, depth=-1e9, collider=bar_col, grip=True, spec3d=spec)
        if not offs:
            return [hidden_bar, Item(Circle(c, 2.6), 'metal', gap=True, depth=cam.depth(c3 + near * 111.0), spec3d=[])]
        d = cam.depth(c3 + near * (offs[-1] + 2.5))
        return [hidden_bar,
                Item(Circle(c, plate_r), 'plate_rim', gap=True, depth=d, collider=plate_cols, spec3d=[]),
                Item(Circle(c, plate_r - 2.6), 'plate', depth=d, spec3d=[]),
                Item(Circle(c, 5.2), 'plate_rim', depth=d, spec3d=[])]
    bar = cyl(cam, c3, ax, 1.5, 102.0)
    parts = [bar]
    if sleeve:
        parts += [cyl(cam, c3 + ax * s * 99.0, ax, 2.6, 12.0) for s in (-1, 1)]
    plate_shapes = [cyl(cam, c3 + ax * s * o, ax, plate_r, 2.5) for s in (-1, 1) for o in offs]
    d = cam.depth(c3) - 0.5
    items = [Item(Union(parts), 'metal', gap=True, depth=d, collider=bar_col, grip=True, spec3d=spec)]
    if plate_shapes:
        items.append(Item(Union(plate_shapes), 'plate_rim', gap=True, depth=d, collider=plate_cols, spec3d=[]))
    return items


def plate3d(c3, axis3, r, half, gap=True):
    """A plate as 3D primitives: the rim, the recessed face (a hair proud of the rim so it shows
    from the side the plate faces) and the hub."""
    ax = unit(axis3)
    return [('cyl', c3, ax, r, half, 'plate_rim', gap),
            ('cyl', c3, ax, r - 2.6, half + 0.06, 'plate', False),
            ('cyl', c3, ax, min(5.2, r * 0.3), half + 0.12, 'plate_rim', False)]


def post3d(top3, bottom_y=1.2, r=2.2, foot=8.0, color='frame'):
    """eq.post in 3D: an upright from top3 down to the floor and a foot across it."""
    top3 = np.asarray(top3, float)
    b = v3(top3[0], bottom_y, top3[2])
    return [('cap', top3, b, r, color, False), ('cap', b - X * foot, b + X * foot, 1.4, color, False)]


# ---- 3D specs (Item.spec3d) ------------------------------------------------------------------------
# Each returns a list of primitives. The last element of every primitive is its band: True cuts the
# knockout band into what lies behind it, False doesn't, and 'back' makes it a backdrop: drawn
# behind every other part from any side (walls, water, anything big the figure works against, which
# turned round would otherwise hide the figure).

def rod3d(a3, b3, r, color='frame', gap=False):
    """A rod, tube, strap or cable: a capsule from a3 to b3."""
    return [('cap', np.asarray(a3, float), np.asarray(b3, float), float(r), color, gap)]


def cone3d(a3, b3, ra, rb, color, gap=False):
    """A round cone (a capsule whose ends differ in radius)."""
    return [('cone', np.asarray(a3, float), np.asarray(b3, float), float(ra), float(rb), color, gap)]


def cyl3d(c3, axis3, r, half, color, gap=False):
    """A capped cylinder: a disc, drum, roller, wheel or plate."""
    return [('cyl', np.asarray(c3, float), unit(axis3), float(r), float(half), color, gap)]


def ball3d(c3, r, color, gap=False):
    return [('sph', np.asarray(c3, float), float(r), color, gap)]


def box3d(c3, ex, ey, ez, hx, hy, hz, rounding=3.0, color='pad', gap=False):
    """A rounded box: centre, three orthogonal axes and the half sizes along them (what box3 draws)."""
    return [('box', np.asarray(c3, float), [unit(ex), unit(ey), unit(ez)], [float(hx), float(hy), float(hz)],
             float(rounding), color, gap)]


def pad3d(a3, b3, up3=Y, width=28.0, t=None, color='pad', rounding=3.0, gap=False):
    """A cushioned pad whose top surface runs from a3 to b3 (what pad() draws)."""
    _, c, axes, half = pad_box(a3, b3, up3, width, PAD_T if t is None else t)
    return [('box', c, axes, half, float(rounding), color, gap)]


def rope3d(points, r, color='metal', gap=False):
    """A rope or chain through 3D points: capsules end to end."""
    pts = [np.asarray(p, float) for p in points]
    return [('cap', p, q, float(r), color, gap) for p, q in zip(pts, pts[1:])]


def ring3d(c3, normal3, radius, tube, color='metal', gap=False, n=16):
    """A ring (a torus: gymnastic ring, tyre, kettlebell handle) as capsules round its centre line."""
    c3, nrm = np.asarray(c3, float), unit(normal3)
    a = unit(np.cross(nrm, X if abs(nrm[0]) < 0.9 else Y))
    b = np.cross(nrm, a)
    pts = [c3 + (a * math.cos(t) + b * math.sin(t)) * radius for t in np.linspace(0.0, 2 * math.pi, n + 1)]
    return rope3d(pts, tube, color, gap)


def plate_disc(v, c3, axis3, r=22.5, z='back', gap=False, depth=None):
    """A lone plate (held, loaded on a machine, lying on the floor). depth=True places it by its
    own camera depth instead of z."""
    cam = v.cam
    c3 = np.asarray(c3, float)
    col = ('cylinder', c3, unit(axis3), r, 2.6)
    d = cam.depth(c3) if depth is True else depth
    spec = plate3d(c3, axis3, r, 2.6, gap)
    if endon(cam, axis3):
        c = cam.p(c3)
        return [Item(Circle(c, r), 'plate_rim', z, gap, depth=d, collider=col, spec3d=spec),
                Item(Circle(c, r - 2.6), 'plate', z, depth=d, spec3d=[]),
                Item(Circle(c, min(5.2, r * 0.3)), 'plate_rim', z, depth=d, spec3d=[])]
    return [Item(cyl(cam, c3, axis3, r, 2.6), 'plate_rim', z, gap, depth=d, collider=col, spec3d=spec)]


def _hand_layer(z):
    """'foreR' for z = ('before', 'armR') etc.: the layer of the hand that holds the implement."""
    if isinstance(z, (tuple, list)) and len(z) == 2 and isinstance(z[1], str):
        name = z[1]
        if name.startswith('arm') or name.startswith('fore'):
            return 'fore' + name[-1]
    return None


def dumbbell(v, hand3, axis3, z, head_r=9.4, half=12.6, gap=True):
    """Dumbbell centred on the grip, drawn as projected cylinders so it turns continuously: seen
    end-on it rounds into its head's disc and the hub fades in (a pressing dumbbell that rotates,
    as in the Arnold press, never pops between two drawings).

    z places it just behind the holding hand, so the fist closes around the handle. As the head on
    the camera side turns towards the camera it comes in front of the hand, as in 3D: a copy of that
    head fades in over the hand (from 1.5 to 6 cm in front of it), until end-on it covers the grip."""
    cam = v.cam
    hand3 = np.asarray(hand3, float)
    ax = unit(axis3)
    if cam.depth(ax) < 0:
        ax = -ax                                  # +ax: the camera-side head
    heads = [cyl(cam, hand3 + ax * s * half, ax, head_r, 4.2) for s in (-1, 1)]
    handle = cyl(cam, hand3, ax, 1.9, half)
    cols = [('cylinder', hand3 + ax * s * half, ax, head_r, 4.2) for s in (-1, 1)]
    spec = ([('cyl', hand3 + ax * s * half, ax, head_r, 4.2, 'metal', gap) for s in (-1, 1)]
            + [('cyl', hand3, ax, 1.9, half, 'metal', gap)]
            + [('cyl', hand3 + ax * s * (half + 4.2), ax, 3.0, 0.12, 'plate_rim', False) for s in (-1, 1)])
    items = [Item(Union(heads + [handle]), 'metal', z, gap, collider=cols, spec3d=spec),
             Item(None, 'metal', z, frame=False, collider=('capsule', hand3 - ax * half, hand3 + ax * half, 1.9),
                  grip=True, spec3d=[])]
    side_on = float(np.linalg.norm(cam.d(ax)))
    hub = 3.0 * (1.0 - smooth(0.12, 0.35, side_on))
    hand = _hand_layer(z)
    lead = cam.depth(hand3 + ax * half) - cam.depth(hand3)
    over = smooth(1.5, 6.0, lead) if hand else 0.0
    if over > 0.0:
        items.append(Item(heads[1], 'metal', ('after', hand), alpha=over, spec3d=[]))
    if hub > 0.05:
        items.append(Item(Circle(cam.p(hand3 + ax * half), hub), 'plate_rim', ('after', hand) if over > 0.5 else z,
                          spec3d=[]))
    return items


def kettlebell(v, hand3, down3, z, gap=True):
    """Kettlebell hanging from the grip along `down3` (the bell below the handle)."""
    cam = v.cam
    hand3 = np.asarray(hand3, float)
    d = unit(down3)
    bell_c = cam.p(hand3 + d * 13.0)
    bell = Circle(bell_c, 10.5)
    handle = Subtract(Circle(cam.p(hand3 + d * 4.0), 6.2), Circle(cam.p(hand3 + d * 4.0), 3.6))
    # 3D: the bell, and the handle as a hoop of short bars round the grip, across the fist: in the
    # plane of the bell's direction and the grip axis (z), so it never turns or flips as the bell swings
    side = unit(Z - d * float(np.dot(Z, d))) if abs(float(np.dot(Z, d))) < 0.95 else unit(np.cross(d, X))
    ring = [hand3 + d * 4.0 + (d * math.cos(a) + side * math.sin(a)) * 4.9
            for a in np.linspace(0.0, 2 * math.pi, 9)]
    spec = [('sph', hand3 + d * 13.0, 10.5, 'metal', gap)]
    spec += [('cap', a, b, 1.3, 'metal', False) for a, b in zip(ring, ring[1:])]
    return [Item(Union([bell, handle]), 'metal', z, gap, collider=('sphere', hand3 + d * 13.0, 10.5), spec3d=spec),
            Item(None, 'metal', z, frame=False, collider=('sphere', hand3 + d * 4.0, 4.0), grip=True, spec3d=[])]


def medball(v, c3, z, r=12.0, gap=True):
    return [Item(Circle(v.cam.p(c3), r), 'plate_rim', z, gap, collider=('sphere', np.asarray(c3, float), r),
                 spec3d=[('sph', np.asarray(c3, float), r, 'plate_rim', gap)])]


# ---- fixed equipment ---------------------------------------------------------------------

def fixed_bar(v, c3, axis3=Z, half=78.0, r=2.3, z='back'):
    cam = v.cam
    c3 = np.asarray(c3, float)
    ax = unit(axis3)
    col = ('capsule', c3 - ax * half, c3 + ax * half, r)
    # 3D: the bar and a bracket rising from each end
    spec = [('cyl', c3, ax, r, half, 'metal', True)]
    spec += [('cap', c3 + ax * s * (half - 1.6), c3 + ax * s * (half - 1.6) + Y * 120.0, 1.6, 'frame', False)
             for s in (-1, 1)]
    if endon(cam, axis3):
        c = cam.p(c3)
        near = ax if cam.depth(ax) >= 0 else -ax
        # seen end-on: the bar's round end on a bracket running up out of frame. The bar reaches
        # past the near hand towards the camera, so its end is in front of the figure (the fists
        # close round it); the bracket it hangs from is the far one, behind
        return [Item(RBox(c + V(0, 60), 1.6, 60, 1.6), 'frame', z, frame=False, spec3d=spec),
                Item(Circle(c, r + 1.2), 'metal', gap=True, depth=cam.depth(c3 + near * half), collider=col,
                     grip=True, spec3d=[])]
    return [Item(cyl(cam, c3, axis3, r, half), 'metal', z, collider=col, grip=True, spec3d=spec)]


PAD_T = 7.0


def pad_box(a3, b3, up3=Y, width=28.0, t=PAD_T):
    """The 3D box (collider) of a pad whose top surface runs from a3 to b3."""
    a3, b3 = np.asarray(a3, float), np.asarray(b3, float)
    d = unit(b3 - a3)
    n = unit(np.asarray(up3, float) - np.dot(up3, d) * d)
    c = (a3 + b3) / 2 - n * t / 2
    w = unit(np.cross(d, n))
    return ('box', c, [d, n, w], [np.linalg.norm(b3 - a3) / 2, t / 2, width / 2])


def pad(cam, a3, b3, up3=Y, width=28.0, t=PAD_T):
    """A cushioned pad whose top surface runs from a3 to b3 (3D)."""
    _, c, (d, n, w), (hx, hy, hz) = pad_box(a3, b3, up3, width, t)
    return box3(cam, c, d, n, w, hx, hy, hz, 3.0)


def post(cam, top3, bottom_y=1.2, r=2.2, foot=8.0):
    top3 = np.asarray(top3, float)
    b = v3(top3[0], bottom_y, top3[2])
    return [Cone(cam.p(top3), cam.p(b), r),
            Cone(cam.p(b - X * foot), cam.p(b + X * foot), 1.4)]


def bench(v, top_c3, length=124.0, z='back', incline=None, seat_len=36.0, back_len=86.0, decline=None,
          head='left'):
    """A gym bench whose seat top is centred at top_c3.
    incline: back rest raised by that many degrees towards the head end.
    decline: the whole pad tilted head-down by that many degrees (with a leg hook)."""
    cam = v.cam
    top = np.asarray(top_c3, float)
    hs = -1.0 if head == 'left' else 1.0
    shapes, frame, cols = [], [], []
    spec = []
    if incline is not None:
        a0 = top - X * hs * seat_len / 2        # the seat's foot end
        a1 = top + X * hs * seat_len / 2        # ... and its head end, where the back rest hinges
        shapes.append(pad(cam, a0, a1))
        cols.append(pad_box(a0, a1))
        hinge = a1 - X * hs * 1.5
        a = math.radians(incline)
        tip = hinge + (X * hs * math.cos(a) + Y * math.sin(a)) * back_len
        shapes.append(pad(cam, hinge, tip))
        cols.append(pad_box(hinge, tip))
        frame += post(cam, top - Y * PAD_T - X * hs * (seat_len / 2 - 4))
        spec += post3d(top - Y * PAD_T - X * hs * (seat_len / 2 - 4))
        # the rear leg stands under the back rest, a little over halfway up it
        brace = hinge + (X * hs * math.cos(a) + Y * math.sin(a)) * (back_len * 0.55) - Y * PAD_T
        frame += post(cam, brace)
        spec += post3d(brace)
    elif decline is not None:
        a = math.radians(decline)
        d = X * math.cos(a) * (-hs) + Y * math.sin(a)       # rising towards the feet end
        a0 = top - d * length / 2
        a1 = top + d * length / 2
        shapes.append(pad(cam, a0, a1))
        cols.append(pad_box(a0, a1))
        for p3 in (a0 + d * 16, a1 - d * 22):
            frame += post(cam, p3 - Y * PAD_T)
            spec += post3d(p3 - Y * PAD_T)
        hook = a1 + d * 6 + Y * 10
        frame.append(Cone(cam.p(a1 - Y * PAD_T), cam.p(hook), 1.8))
        shapes.append(Circle(cam.p(hook), 5.2))
        spec += [('cap', a1 - Y * PAD_T, hook, 1.8, 'frame', False), ('cyl', hook, Z, 5.2, 26.0, 'pad', False)]
        # the roller runs across under both lower legs (only its end is drawn): give it its volume
        cols.append(('cylinder', hook, Z, 5.2, 26.0))
    else:
        a0 = top - X * length / 2
        a1 = top + X * length / 2
        shapes.append(pad(cam, a0, a1))
        cols.append(pad_box(a0, a1))
        frame += post(cam, top - Y * PAD_T - X * (length / 2 - 14))
        frame += post(cam, top - Y * PAD_T + X * (length / 2 - 14))
        spec += post3d(top - Y * PAD_T - X * (length / 2 - 14)) + post3d(top - Y * PAD_T + X * (length / 2 - 14))
    spec += [('box',) + tuple(c[1:]) + (3.0, 'pad', False) for c in cols if c[0] == 'box']
    return [Item(Union(frame), 'frame', z, spec3d=spec), Item(Union(shapes), 'pad', z, collider=cols, spec3d=[])]


def box3(cam, c3, ex, ey, ez, hx, hy, hz, r):
    """Rounded box in 3D projected: the silhouette of its projected corners, rounded."""
    c3 = np.asarray(c3, float)
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corners.append(cam.p(c3 + ex * sx * (hx - r) + ey * sy * (hy - r) + ez * sz * (hz - r)))
    pts = np.array(corners)
    hull = _hull(pts)
    return Poly(hull, r=r)


def _hull(pts):
    pts = sorted(set((round(p[0], 6), round(p[1], 6)) for p in pts))
    if len(pts) <= 2:
        p = np.array(pts)
        if len(p) == 1:
            return np.array([p[0], p[0] + [1e-3, 0], p[0] + [0, 1e-3]])
        return np.array([p[0], p[1], p[1] + [1e-3, 1e-3]])

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])


def plyo_box(v, c3, hx=30.0, hy=25.0, hz=35.0, z='back'):
    c3 = np.asarray(c3, float)
    return [Item(box3(v.cam, c3, X, Y, Z, hx, hy, hz, 3.0), 'pad', z, collider=('box', c3, [X, Y, Z], [hx, hy, hz]),
                 spec3d=[('box', c3, [X, Y, Z], [hx, hy, hz], 3.0, 'pad', False)])]


def cable_stack(v, pulley3, handle3, z='back', tower_x=None, stack=True, rope=False, handle='d', mount=None):
    """A cable tower with its pulley at pulley3 and the cable running to handle3. mount (3D only, a
    world direction the exercise's camera looks along): a pulley drawn over the middle of its tower
    stands proud of the tower's face on that side, on a bracket, instead of inside the tower."""
    cam = v.cam
    p = cam.p(pulley3)
    h = cam.p(handle3)
    items = []
    tx = pulley3[0] if tower_x is None else tower_x
    top = max(pulley3[1] + 12, 200.0)
    tower = RBox(cam.p(v3(tx, top / 2, pulley3[2])), 4.5, top / 2, 3.0)
    pulley3, handle3 = np.asarray(pulley3, float), np.asarray(handle3, float)
    if mount is None:
        wheel = pulley3
        pulley = [('sph', pulley3, 4.6, 'metal', False)]
    else:
        m = unit(mount)
        wheel = pulley3 + m * 6.5
        pulley = [('cap', pulley3 + m * 4.0, wheel, 1.2, 'frame', False),
                  ('cyl', wheel, m, 4.6, 1.4, 'metal', False),
                  ('cyl', wheel, m, 1.6, 1.6, 'frame', False)]
    spec = ([('box', v3(tx, top / 2, pulley3[2]), [X, Y, Z], [4.5, top / 2, 4.5], 3.0, 'frame', False)] + pulley
            + [('cap', wheel, handle3, 0.55, 'metal', False)])
    items.append(Item(tower, 'frame', 'back', spec3d=spec))
    items.append(Item(Circle(p, 4.6), 'metal', 'back', spec3d=[]))
    items.append(Item(Circle(p, 1.6), 'frame', 'back', spec3d=[]))
    # the cable is a thin line in 3D too: it may meet the hand at its handle, but not cut through
    # the arm or body on its way to the pulley
    items.append(Item(Cone(p, h, 0.55), 'metal', z,
                      collider=('capsule', pulley3, handle3, 0.4), grip=True, spec3d=[]))
    return items
