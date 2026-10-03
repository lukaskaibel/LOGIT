"""Squat pattern: back, front, box, goblet, zercher, pistol, sissy, hack, thrusters, wall balls."""
from .common import *
from ..rig import rot_toward
from ..spec import TOE

WR = FORE - FORE_WRIST          # wrist -> grip centre


def toe_planted(toe, fp, heading=X):
    """Ankle target for a foot pitched fp degrees (- = heel up) about its planted ball: the toe stays
    where it is (pitching about the ankle would push the toes into the floor and slide them).
    heading: the foot's horizontal direction (turned out by toe_out)."""
    a = math.radians(fp)
    t = heading * math.cos(a) + Y * math.sin(a)
    n = Y * math.cos(a) - heading * math.sin(a)
    return np.asarray(toe, float) - n * TOE[0] - t * TOE[1]


def toe_of(ankle, heading=X):
    """Where the ball of a flat foot with its ankle at `ankle` rests."""
    return np.asarray(ankle, float) + Y * TOE[0] + heading * TOE[1]


def squat_chain(u, ankle_x, shin_top, shin_bot, thigh_top, thigh_bot):
    phi = math.radians(lerp(shin_top, shin_bot, u))
    alpha = math.radians(lerp(thigh_top, thigh_bot, u))
    K = v3(ankle_x, ANKLE_H) + SHANK * v3(math.sin(phi), math.cos(phi))
    H = K + THIGH * v3(-math.cos(alpha), math.sin(alpha))
    return K, H


@exercise('squats', 'legs', 'side', muscles=['quads', 'glutes'])
def squats():
    A = -6.0
    XBAR = -1.5
    BAR_L = (-7.0, 53.5)            # bar on the traps, torso-local (forward, up)

    def pose(u):
        K, H = squat_chain(u, A, 0.0, 33.0, 90.5, -3.0)
        th = solve_torso_for(BAR_L, H, XBAR)
        B = torso_point(H, th, *BAR_L)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.4 * th}
        p.update(feet(A, 12.0, 10.0))
        p.update(both(v3(B[0], B[1], 40.0), [-1.0, -0.7, 0.35]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)

    return pose, rep_down_first(1.6, 1.3, top=0.55, bottom=0.22), equip


SQUAT = rep_down_first(1.6, 1.3, top=0.55, bottom=0.22)


def upright_squat(u, load_local, x_target=-1.5, A=-6.0, shin=(0.0, 36.0), thigh=(90.5, -6.0), lean=(3.0, 20.0)):
    """Squat with the load carried in front (front rack, goblet, zercher): the torso stays tall,
    leaning only a little at the bottom, which keeps the load over mid-foot."""
    K, H = squat_chain(u, A, shin[0], shin[1], thigh[0], thigh[1])
    th = lerp(lean[0], lean[1], smooth(0.0, 1.0, u))
    return K, H, th


def grip_arm(S, G, aim, wf):
    """Rig arm dict that puts the grip centre exactly on G, the wrist bent by wf (deg, - = extended,
    as under a racked bar) and the elbow on the `aim` side of the shoulder->grip line. rig.solve bends
    the hand against the upper arm, which lines up with the forearm at a right-angled elbow, so the
    flex fades out within 12 deg of 90 and the hand never flips sides."""
    S, G, aim = (np.asarray(x, float) for x in (S, G, aim))

    def solve(wf):
        a = math.radians(wf)
        Lf = math.sqrt(FORE_WRIST ** 2 + WR ** 2 + 2 * FORE_WRIST * WR * math.cos(a))   # elbow -> grip
        E, Gc = ik2(S, G, UPPER, Lf, aim)
        d_u = unit(E - S)
        e_g = unit(Gc - E)
        ins = e_g - np.dot(e_g, d_u) * d_u              # inside of the elbow bend
        if np.linalg.norm(ins) < 0.05:
            q = aim - np.dot(aim, d_u) * d_u
            if np.linalg.norm(q) > 1e-6:
                ins = -q
        ins = unit(ins)
        beta = math.degrees(math.asin(min(1.0, WR * abs(math.sin(a)) / Lf)))
        d_f = rot_toward(e_g, -ins if wf > 0 else ins, beta) if beta > 1e-6 else e_g
        W = E + d_f * FORE_WRIST
        bend = math.degrees(math.acos(float(np.clip(np.dot(d_u, d_f), -1.0, 1.0))))
        return W, (E - S) - unit(W - S) * (0.5 * UPPER), bend

    W, pole, bend = solve(wf)
    k = smooth(0.0, 12.0, abs(bend - 90.0))
    if k < 1.0 and wf != 0.0:
        wf *= k
        W, pole, bend = solve(wf)
    return {'hand': W, 'pole': pole, 'wrist_flex': wf}


def grip_arms(p, G, aim, wf):
    """Both arms on a bar: G and aim for the right arm (world), mirrored for the left."""
    for s, sg in (('L', -1.0), ('R', 1.0)):
        S = shoulder_at(p['pelvis'], p['pitch']) + Z * (sg * SHOULDER_HALF)
        p['arm' + s] = grip_arm(S, G * np.array([1.0, 1.0, sg]), np.asarray(aim, float) * np.array([1.0, 1.0, sg]), wf)
    return p


FRONT_RACK = (9.0, 56.0)            # the bar on the front delts, against the throat (torso-local)
RACK_ELBOW = 22.0                   # elbows forward and high: aimed this far below horizontal
RACK_WF = -85.0                     # wrists extended under the bar, the bar on the fingers
RACK_Z = 25.0                       # grip just outside the shoulders


def rack_aim(deg=RACK_ELBOW):
    b = math.radians(deg)
    return v3(math.cos(b), -math.sin(b), 0.45)


@exercise('frontSquats', 'legs', 'side', muscles=['quads', 'glutes'])
def front_squats():
    def pose(u):
        K, H, th = upright_squat(u, FRONT_RACK)
        B = torso_point(H, th, *FRONT_RACK)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.3 * th}
        p.update(feet(-6.0, 12.0, 12.0))
        # elbows stay up as the torso leans: aimed higher by the lean
        return grip_arms(p, v3(B[0], B[1], RACK_Z), rack_aim(RACK_ELBOW - th), RACK_WF)

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)

    return pose, SQUAT, equip


@exercise('boxSquats', 'legs', 'side', muscles=['quads', 'glutes', 'hamstrings'])
def box_squats():
    A = -6.0
    XBAR = -3.0
    BAR_L = (-7.0, 53.5)

    def pose(u):
        # sit back onto the box: shins stay nearly vertical, hips travel back
        K, H = squat_chain(u, A, 0.0, 16.0, 90.5, 4.0)
        th = solve_torso_for(BAR_L, H, XBAR)
        B = torso_point(H, th, *BAR_L)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.4 * th}
        p.update(feet(A, 14.0, 12.0))
        p.update(both(v3(B[0], B[1], 40.0), [-1.0, -0.7, 0.35]))
        return p

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        K, H = squat_chain(1.0, A, 0.0, 16.0, 90.5, 4.0)
        box_top = H[1] - 9.5
        box = eq.plyo_box(v, v3(H[0] - 10.0, box_top / 2, 0.0), hx=20.0, hy=box_top / 2, hz=24.0)
        return box + eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)

    return pose, rep_down_first(1.7, 1.3, top=0.55, bottom=0.45), equip


@exercise('zercherSquats', 'legs', 'side', muscles=['quads', 'glutes'])
def zercher_squats():
    BAR_L = (27.0, 22.0)                 # cradled in the elbows in front of the belly

    def pose(u):
        K, H, th = upright_squat(u, BAR_L, shin=(0.0, 34.0), thigh=(90.5, -2.0), lean=(4.0, 22.0))
        B = torso_point(H, th, *BAR_L)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.3 * th}
        p.update(feet(-6.0, 14.0, 14.0))
        S = shoulder_at(H, th)
        # elbows under the bar, forearms up, hands clasped in front of the chest
        hand = torso_point(H, th, 22.0, 44.0)
        p.update(both(v3(hand[0], hand[1], 7.0), [0.2, -1.0, 0.3]))
        return p

    def equip(J, v, u):
        # the bar lies in the crooks of the elbows: up the bisector of the elbow's bend, between the
        # forearm and the upper arm (not in the joint itself, which put it through both)
        E = J.p['elbowR']
        bis = unit(J.p['shoulderR'] - E) + unit(J.p['handR'] - E)
        c = E + unit(v3(bis[0], bis[1], 0.0)) * 7.5
        return eq.barbell(v, v3(c[0], c[1], 0.0))

    return pose, SQUAT, equip


def goblet(key, kettle=False):
    @exercise(key, 'legs', 'side', muscles=['quads', 'glutes'])
    def build():
        LOAD = (22.0, 38.0)

        def pose(u):
            K, H, th = upright_squat(u, LOAD, shin=(0.0, 36.0), thigh=(90.5, -8.0))
            p = {'pelvis': H, 'pitch': th, 'neck': 0.3 * th}
            p.update(feet(-6.0, 16.0, 16.0))
            hand = torso_point(H, th, 20.0, 40.0)
            p.update(both(v3(hand[0], hand[1], 6.0), [0.3, -1.0, 0.6]))
            return p

        def equip(J, v, u):
            h = (J.p['handL'] + J.p['handR']) / 2
            up = J.torso_frame.u
            # held on the midline against the chest: in front of the body, behind both hands and
            # arms and, at the bottom, behind the near thigh that comes up beside it
            z = ('after', 'base')
            if kettle:
                # hands on the horns, the bell hanging just below them (not sunk into it)
                return eq.kettlebell(v, h + up * 1.0, -up, z)
            # cupped under the top head: the head rests on the palms, the handle runs between them
            return eq.dumbbell(v, h - up * 4.9, up, z)

        return pose, SQUAT, equip
    return build


goblet('gobletSquats')
goblet('gobletSquatWithKettlebell', kettle=True)


HACK_RAIL_Z = 16.0          # 3D: the sled's two rails, behind the back pad's edges


@exercise('hackSquats', 'legs', 'side', muscles=['quads', 'glutes'])
def hack_squats():
    # back on a sled whose rails run parallel to the back pad; feet on an angled platform in front.
    # The sled can only travel along its rails, so the hips slide down the line of the back and the
    # knees travel forward over the toes (hips moving back across the rails carried the pad
    # through them).
    A = v3(26.0, 12.0)
    lean = -30.0
    down = v3(math.sin(math.radians(-lean)), -math.cos(math.radians(-lean)))    # down the rails
    f = v3(math.cos(math.radians(lean)), -math.sin(math.radians(lean)))         # the back pad's normal
    # the bottom: shins 20 deg forward (knees over the toes), thighs rising 10 deg to the knee
    K1 = A + SHANK * v3(math.sin(math.radians(20.0)), math.cos(math.radians(20.0)))
    H1 = K1 - THIGH * v3(math.cos(math.radians(10.0)), math.sin(math.radians(10.0)))
    # the top: up the rails until the legs are all but straight (knees soft by ~8 deg)
    reach = math.sqrt((2 * 43.65 * math.sin(math.radians(86.0))) ** 2 - (14.0 - HIP_HALF) ** 2)
    lo, hi = 0.0, 120.0
    for _ in range(60):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if np.linalg.norm(H1 - down * mid - A) < reach else (lo, mid)
    H0 = H1 - down * lo
    # the rails, fixed: parallel to the pad, just behind it, from the floor to above the top position
    back = H0 - f * 23.5
    rail_a = back + down * ((back[1] - 1.0) / -down[1])
    rail_b = back - down * 92.0

    def pose(u):
        H = H0 + (H1 - H0) * u
        p = {'pelvis': H, 'pitch': lean, 'neck': -0.3 * lean}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 14.0), 'foot_pitch': 18.0, 'pole': v3(1.0, 0.5, 0.2 * sg)}
        S = shoulder_at(H, lean)
        p.update(both(v3(S[0] + 6.0, S[1] + 8.0, 26.0), [0.4, -1.0, 0.5]))
        return p

    def equip(J, v, u):
        cam = v.cam
        H = J.p['pelvis']
        tf = J.torso_frame
        # the back pad rides on the sled: from below the hips to above the head, behind the back
        a = H - tf.u * 14.0 - tf.f * 12.5
        b = H + tf.u * 82.0 - tf.f * 12.5
        a, b = v3(a[0], a[1], 0), v3(b[0], b[1], 0)
        pad = eq.pad(cam, a, b, up3=tf.f, width=40.0)
        # the shoulder pads rest on top of both shoulders (one drawing): the near one lies in front
        # of the head between them and behind the near arm, whose hand holds the handle outside it
        sh = J.p['shoulder_c'] + tf.u * 9.0 - tf.f * 2.0
        shoulder_pad = Circle(cam.p(sh), 6.0)
        pa, pb = v3(A[0] - 14.0, A[1] - 11.5, 0), v3(A[0] + 20.0, A[1] - 2.0, 0)
        plat = eq.pad(cam, pa, pb, width=40.0)
        ra, rb = v3(rail_a[0], rail_a[1], 0), v3(rail_b[0], rail_b[1], 0)
        # 3D: a rail under each edge of the sled, joined across at both ends (end-on from the side);
        # a short roll on each shoulder (end-on from the side: the drawn circle), each on an arm
        # back to the pad
        rails = [e for sg in (-1.0, 1.0) for e in eq.rod3d(ra + Z * sg * HACK_RAIL_Z, rb + Z * sg * HACK_RAIL_Z, 3.0)]
        rails += eq.rod3d(ra - Z * HACK_RAIL_Z, ra + Z * HACK_RAIL_Z, 2.4) + eq.rod3d(rb - Z * HACK_RAIL_Z,
                                                                                     rb + Z * HACK_RAIL_Z, 2.4)
        rolls = []
        for sg in (-1.0, 1.0):
            c = sh + Z * sg * 12.25         # from beside the head out to the shoulder joint
            rolls += eq.cyl3d(c, Z, 6.0, 2.25, 'pad', True) + eq.rod3d(c, c - tf.f * 11.5, 1.5, 'frame')
        return [Item(Cone(cam.p(rail_a), cam.p(rail_b), 3.0), 'frame', 'back',
                     collider=('capsule', v3(rail_a[0], rail_a[1], 0), v3(rail_b[0], rail_b[1], 0), 3.0), spec3d=rails),
                Item(pad, 'pad', 'back', collider=eq.pad_box(a, b, tf.f, 40.0), spec3d=eq.pad3d(a, b, tf.f, 40.0)),
                Item(shoulder_pad, 'pad', ('after', 'head'), gap=True,
                     collider=[('sphere', sh + Z * (sg * 12.0), 6.0) for sg in (-1, 1)], spec3d=rolls),
                Item(plat, 'frame', 'back', collider=eq.pad_box(pa, pb, Y, 40.0),
                     spec3d=eq.pad3d(pa, pb, Y, 40.0, color='frame'))]

    return pose, rep_down_first(1.6, 1.3, top=0.5, bottom=0.22), equip


@exercise('sissySquats', 'legs', 'side', muscles=['quads'])
def sissy_squats():
    toe = toe_of(v3(-2.0, ANKLE_H))               # balls of the feet, planted
    post_x, post_top = 19.0, 126.0                # a support post at the near hand, fixed
    grip = v3(post_x - 3.0, 116.0, 26.0)          # the hand holds it in one place

    def pose(u):
        # knees drive forward and down, heels rise, knee-hip-shoulder stays one leaning line
        fp = lerp(0.0, -34.0, u)
        A = toe_planted(toe, fp)
        shin = math.radians(lerp(4.0, 64.0, u))
        K = A + SHANK * v3(math.sin(shin), math.cos(shin))
        back = math.radians(lerp(2.0, 48.0, u))
        H = K + THIGH * v3(-math.sin(back), math.cos(back))
        p = {'pelvis': H, 'pitch': -math.degrees(back), 'neck': lerp(0.0, 18.0, u)}
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': v3(A[0], A[1], sg * 12.0), 'foot_pitch': fp, 'pole': v3(1.0, 0.0, 0.2 * sg)}
        p['armR'] = {'hand': grip, 'pole': np.array([-0.3, -1.0, 0.3])}
        p['armL'] = {'flex': lerp(30.0, 70.0, u), 'abd': 4.0, 'elbow': 20.0}
        return p

    def equip(J, v, u):
        cam = v.cam
        # at the near hand's depth: in front of the legs that pass behind it, just behind the fist
        post = RBox(cam.p(v3(post_x, post_top / 2)), 2.6, post_top / 2, 2.0)
        # 3D: a square upright (the drawn outline) on a foot across, end-on from the side
        spec = (eq.box3d(v3(post_x, post_top / 2, grip[2]), X, Y, Z, 2.6, post_top / 2, 2.6, 2.0, 'frame')
                + eq.rod3d(v3(post_x, 1.2, grip[2] - 14.0), v3(post_x, 1.2, grip[2] + 14.0), 1.4, 'frame'))
        return [Item(post, 'frame', ('before', 'armR'),
                     collider=('capsule', v3(post_x, 0.0, grip[2]), v3(post_x, post_top, grip[2]), 2.6), grip=True,
                     spec3d=spec)]

    return pose, rep_down_first(1.7, 1.4, top=0.5, bottom=0.25), equip


@exercise('pistolSquats', 'legs', 'side', muscles=['quads', 'glutes'])
def pistol_squats():
    A = -4.0

    def pose(u):
        K, H = squat_chain(u, A, 0.0, 40.0, 90.0, -22.0)
        th = lerp(4.0, 42.0, u)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.3 * th}
        p['legR'] = {'foot': v3(A, ANKLE_H, 5.0), 'toe_out': 4.0, 'pole': np.array([1.0, 0.0, 0.1])}
        # the free leg stays off the floor (its heel went through it at the bottom; at the top it's
        # held clear too, or its toe drags along the floor as it swings forward) and the arms
        # reach forward, over the standing knee rather than down through it
        p['legL'] = {'hip': lerp(32.0, 91.0 - th * 0.2, u), 'abd': 2.0, 'knee': lerp(48.0, 2.0, smooth(0.0, 0.5, u)),
                     'ankle': 0.0}
        p['armL'] = {'flex': lerp(30.0, 112.0, u) - th * 0.3, 'abd': 6.0, 'elbow': 4.0}
        p['armR'] = {'flex': lerp(30.0, 112.0, u) - th * 0.3, 'abd': 6.0, 'elbow': 4.0}
        return p

    return pose, rep_down_first(1.8, 1.5, top=0.55, bottom=0.25), None


@exercise('thrusters', 'legs', 'side', muscles=['quads', 'glutes', 'delts'])
def thrusters():
    reach = math.sqrt((ARM - 0.8) ** 2 - (RACK_Z - SHOULDER_HALF) ** 2)
    over_aim = v3(0.2, -1.0, 0.9)           # locked out: elbows turned out

    def pose(u):
        # u 0 -> 0.5: front squat down; 0.5 -> 1: drive up and press in one motion
        sq = min(u * 2.0, 1.0) if u <= 0.5 else max(1.0 - (u - 0.5) * 2.4, 0.0)
        press = smooth(0.62, 0.95, u)
        K, H, th = upright_squat(sq, FRONT_RACK)
        th = th * (1 - press) + 2.0 * press
        S = shoulder_at(H, th)
        rack = torso_point(H, th, *FRONT_RACK)
        over = S + v3(1.0, reach)
        # the bar leaves the throat forwards and rounds the face (the chin lifts out of its way),
        # then comes back over the shoulders: straight up it would pass through the head
        arc = 6.75 * press * (1 - press) ** 2
        b = rack + (over - rack) * press + v3(10.0 * arc, 0.0)
        p = {'pelvis': H, 'pitch': th, 'neck': 0.3 * th + 6.0 * arc}
        p.update(feet(-6.0, 12.0, 12.0))
        aim = rack_aim(RACK_ELBOW - th) * (1 - press) + over_aim * press
        return grip_arms(p, v3(b[0], b[1], RACK_Z), aim, lerp(RACK_WF, -10.0, press))

    def equip(J, v, u):
        B = (J.p['handL'] + J.p['handR']) / 2
        return eq.barbell(v, v3(B[0], B[1], 0.0), plate_r=17.0)

    # starts overhead: lower into the squat, drive up and press, twice
    tl = Timeline([(0.4, 1.0, 1.0), (1.3, 1.0, 0.5), (0.2, 0.5, 0.5), (1.1, 0.5, 1.0)] * 2)
    return pose, tl, equip


WB_WALL_TOP = 340.0         # 3D: the wall section behind the wall-ball target (cm, from the floor)
WB_WALL_HALF = 150.0        # ... and half its width (the 2D collider's 3 m)


@exercise('wallBalls', 'legs', 'side', muscles=['quads', 'glutes', 'delts'])
def wall_balls():
    LOAD = (24.0, 38.0)
    wall_x = 84.0
    target_y = 290.0
    heading = {s: v3(math.cos(math.radians(14.0)), 0.0, sg * math.sin(math.radians(14.0))) for s, sg in (('L', -1), ('R', 1))}
    toes = {s: toe_of(v3(-6.0, ANKLE_H, sg * 15.0), heading[s]) for s, sg in (('L', -1), ('R', 1))}

    def pose(u):
        # 0 -> 0.45 squat; 0.45 -> 0.7 drive and throw; 0.7 -> 1 ball flies and comes back
        sq = smooth(0.0, 0.4, u) * (1 - smooth(0.45, 0.62, u))
        throw = smooth(0.45, 0.66, u) * (1 - smooth(0.8, 1.0, u))
        K, H, th = upright_squat(sq, LOAD, shin=(0.0, 36.0), thigh=(90.5, -6.0))
        th = th * (1 - throw) + 2.0 * throw
        S = shoulder_at(H, th)
        # the ball rests against the chest (at 20 cm it sank into it) and is driven up and a little
        # forward, round the face: straight up from the chest it passed through the head
        chest = torso_point(H, th, LOAD[0], 40.0)
        up = S + v3(14.0, 56.0)
        arc = 6.75 * throw * (1 - throw) ** 2
        h = chest + (up - chest) * throw + v3(12.0 * arc, 0.0)
        p = {'pelvis': H + v3(0, 3.0 * math.sin(math.pi * throw)), 'pitch': th, 'neck': 0.3 * th + 10.0 * throw}
        fp = -18.0 * math.sin(math.pi * throw)          # heels up with the drive, balls of the feet planted
        for s, sg in (('L', -1), ('R', 1)):
            p['leg' + s] = {'foot': toe_planted(toes[s], fp, heading[s]), 'toe_out': 14.0, 'foot_pitch': fp,
                            'pole': np.array([1.0, 0.0, 0.2 * sg])}
        p.update(both(v3(h[0], h[1], 10.0), [lerp(0.2, 0.3, throw), -1.0, 0.7]))
        return p

    def equip(J, v, u):
        cam = v.cam
        h = (J.p['handL'] + J.p['handR']) / 2
        # the ball leaves the hands at the top of the drive, rises to the target and drops back
        fly = smooth(0.62, 0.66, u) * (1 - smooth(0.96, 1.0, u))
        t = min(max((u - 0.64) / 0.34, 0.0), 1.0)
        height = 4 * t * (1 - t)
        ball = h + v3(12.0 * height, (target_y - h[1] + 20.0) * height, 0.0)
        c = h * (1 - fly) + ball * fly + v3(0, 13.0, 0) * (1 - fly)
        wall = RBox(cam.p(v3(wall_x + 3.0, 200.0)), 3.0, 200.0, 2.0)
        target = RBox(cam.p(v3(wall_x - 2.0, target_y)), 2.0, 14.0, 1.6)
        # 3D: the wall and its target are backdrops (behind the figure from any side, left out of the
        # framing), the wall a section 3.4 m tall and 3 m wide. The target is a disc on it, its face
        # a hair proud in the darker tone (in the wall's tone it would vanish face-on). The ball flies
        # out of the picture as in 2D: it doesn't count for the framing either.
        wall3 = eq.box3d(v3(wall_x + 3.0, WB_WALL_TOP / 2, 0.0), X, Y, Z, 3.0, WB_WALL_TOP / 2, WB_WALL_HALF, 2.0,
                         'frame', 'back')
        tc = v3(wall_x - 2.0, target_y, 0.0)
        target3 = (eq.cyl3d(tc, X, 14.0, 2.0, 'plate_rim', 'back')
                   + eq.cyl3d(tc - X * 0.06, X, 11.0, 2.0, 'plate', 'back'))
        # held on the midline: in front of the body, behind the near arm and hands, and behind the
        # near thigh where it comes up beside the ball at the bottom
        return [Item(wall, 'frame', 'back', frame=False,
                     collider=('box', v3(wall_x + 3.0, 200.0, 0.0), [X, Y, Z], [3.0, 200.0, 150.0]), spec3d=wall3),
                Item(target, 'plate_rim', 'back', frame=False, spec3d=target3),
                Item(Circle(cam.p(c), 12.0), 'plate_rim', ('after', 'base'), gap=True, frame=False,
                     collider=('sphere', v3(c[0], c[1], 0.0), 12.0), grip=True,
                     spec3d=eq.ball3d(v3(c[0], c[1], 0.0), 12.0, 'plate_rim', True), frame3d=False)]

    return pose, Timeline([(0.2, 0, 0), (3.2, 0, 1.0)] * 2, linear=True), equip
