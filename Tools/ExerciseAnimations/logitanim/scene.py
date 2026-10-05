"""Exercise registry, frame composition, framing and video output."""
import math
import subprocess

import numpy as np

from .sdf import Canvas, RBox, V
from .spec import PAL, MUSCLE, SCALE, VIDEO_PX, FPS
from .rig import solve
from .body import view, Camera, behind_margins
from . import anatomy

REGISTRY = {}


class Item:
    """A piece of equipment (or anything not the figure) in one frame.
    z: 'back' (behind everything), 'front' (in front, with a knockout gap),
       ('before', layer) / ('after', layer) relative to a figure layer. Arm layers come in two
       halves, 'armL'/'armR' (upper arm) and 'foreL'/'foreR' (forearm and hand), and legs seen
       from the front as 'legL'/'legR' (thigh) and 'shinL'/'shinR' (shank and foot).
    depth: the camera depth of the item (cam.depth of a 3D point). When given it wins over z: the
       item is slotted between the figure's layers by how near the camera it really is, so a
       plate at the camera end of a bar covers the arm and chest and the far one hides behind.
    collider: its 3D volume for `build.py clip`, a tuple
       ('capsule', a3, b3, r) | ('sphere', c3, r) | ('cylinder', c3, axis3, r, half_len)
       | ('box', c3, [e1, e2, e3], [h1, h2, h3]); grip=True marks a handle hands may hold.
    spec3d: the equipment as 3D primitives for view3d (any camera), a list of
       ('cyl', c3, axis3, r, half, colour, gap) | ('cap', a3, b3, r, colour, gap)
       | ('sph', c3, r, colour, gap) | ('box', c3, [e1, e2, e3], [h1, h2, h3], rounding, colour, gap).
       A helper that returns several items puts the whole piece on one of them and [] on the
       others; None means the item exists for one camera only (2D).
    """

    def __init__(self, shape, color, z='back', gap=False, frame=True, depth=None, collider=None, grip=False,
                 alpha=1.0, spec3d=None, frame3d=True):
        """frame=False: leave it out of the framing (straps, cables and walls running off-canvas).
        shape=None: nothing to draw, only a collider (a bar hidden behind its end-on plate).
        frame3d=False: leave its 3D spec out of the 3D framing (a thrown ball, a climbing rope)."""
        self.shape, self.color, self.z, self.gap, self.frame = shape, color, z, gap, frame and shape is not None
        self.depth, self.collider, self.grip, self.alpha = depth, collider, grip, alpha
        self.spec3d, self.frame3d = spec3d, frame3d


class Exercise:
    def __init__(self, key, group, camera, pose, phase, equip=None, muscles=None, floor=True,
                 near_arm_behind=False, name=None, note=None):
        self.key, self.group, self.camera = key, group, camera
        self.pose_fn, self.phase = pose, phase
        self.equip = equip
        self.muscles = muscles if muscles is not None else anatomy.GROUP_REGIONS[group]
        self.floor = floor
        self.near_arm_behind = near_arm_behind
        self.name = name or key
        self.note = note
        self.duration = phase.total
        self._frame = None
        self._behind = None

    # ---- one frame --------------------------------------------------------------------

    def state(self, t):
        u = self.phase(t)
        J = solve(self.pose_fn(u))
        if self.camera == 'side':
            v = view(J, 'side', near_arm_behind=self.near_arm_behind)
        else:
            v = view(J, self.camera, behind=self.behind_weights(t))
        items = self.equip(J, v, u) if self.equip else []
        return J, v, items

    # Front and back views: when an arm passes behind the torso. It switches only once it's HYST cm
    # past the switch point, so a pose held right at it stays on one side (no flicker, nothing held
    # half-way), and the switch dissolves over FADE seconds of the movement instead of popping.
    HYST = 1.0
    FADE = 0.2

    def behind_weights(self, t):
        """{side: weight of the arm being drawn behind the torso} at time t (see HYST and FADE)."""
        if self._behind is None:
            cam = Camera(self.camera)
            n = max(16, int(round(self.duration * 60)))
            margins = [behind_margins(solve(self.pose_fn(self.phase(self.duration * i / n))), cam) for i in range(n)]
            seqs = {}
            for s in 'LR':
                b = margins[0][s] < 0
                seq = np.zeros(n)
                for lap in range(2):            # the second lap starts from where the loop really ends
                    for i in range(n):
                        m = margins[i][s]
                        if b and m > self.HYST:
                            b = False
                        elif not b and m < -self.HYST:
                            b = True
                        seq[i] = 1.0 if b else 0.0
                seqs[s] = seq
            self._behind = (n, seqs)
        n, seqs = self._behind
        # the state averaged over a window FADE wide (a linear ramp through each switch), eased
        x = (t / self.duration) * n
        k = self.FADE / self.duration * n / 2
        out = {}
        for s, seq in seqs.items():
            if seq.min() == seq.max():
                out[s] = float(seq[0])
                continue
            grid = np.arange(int(math.floor(x - k)), int(math.ceil(x + k)) + 1)
            lo = np.clip(np.minimum(grid + 0.5, x + k) - np.maximum(grid - 0.5, x - k), 0.0, None)
            w = float((seq[grid % n] * lo).sum() / max(lo.sum(), 1e-9))
            out[s] = w * w * (3 - 2 * w)
        return out

    def paint(self, cv, t, pal=PAL, knock=None, floor=True, muscles=True):
        knock = pal['bg'] if knock is None else knock
        J, v, items = self.state(t)
        if floor and self.floor and self._frame is not None:
            x0, x1 = self._frame['floor']
            cv.paint(RBox(V((x0 + x1) / 2, -2.9), (x1 - x0) / 2, 0.85, 0.85), pal['floor'])
        ov = v.overlays(J, self.muscles if muscles else [], MUSCLE[self.group])
        if not v.variants:
            self._paint_layers(cv, v.layers, items, ov, pal, knock)
            return J, v
        # a limb between two paint orders: paint the frame each way and blend by weight
        under = cv.img.copy()
        acc = np.zeros_like(cv.img)
        for w, layers in v.variants:
            cv.img[:] = under
            self._paint_layers(cv, layers, items, ov, pal, knock)
            acc += cv.img * np.float32(w)
        cv.img[:] = acc
        return J, v

    def _paint_layers(self, cv, layers, items, ov, pal, knock):
        by_z = {}
        order = [layer.name for layer in layers]
        names = set(order)
        by_depth = []
        for it in items:
            if it.depth is not None:
                by_depth.append(it)
                continue
            key = it.z if isinstance(it.z, str) else tuple(it.z)
            if not isinstance(key, str):
                pos, name = key
                if name.startswith('arm') and 'fore' + name[3:] in names:
                    # an arm is two layers: held things sit just behind the hand, and 'after the
                    # arm' means in front of whichever half is nearer
                    halves = [n for n in order if n in (name, 'fore' + name[3:])]
                    name = 'fore' + name[3:] if pos == 'before' else halves[-1]
                if name not in names:
                    # that limb is merged into the body in this frame: stay with the body rather
                    # than vanish for these frames and pop back
                    pos, name = (pos, 'base') if 'base' in names else (('front' if pos == 'after' else 'back'), None)
                key = (pos, name) if name else pos
            by_z.setdefault(key, []).append(it)

        def paint_item(it):
            if it.shape is None:
                return
            col = pal[it.color] if isinstance(it.color, str) else it.color
            if it.gap:
                cv.paint_gap(it.shape, col, 1.6, knock)
            else:
                cv.paint(it.shape, col, it.alpha)

        def paint_items(key):
            for it in by_z.get(key, []):
                paint_item(it)

        # depth-sorted items slot in before the first layer that lies nearer the camera (layer
        # depths as a running maximum, so the figure's own painting order stays as it is)
        by_depth.sort(key=lambda it: it.depth)
        nearest = -1e9
        pending = list(by_depth)

        paint_items('back')
        shapes = {layer.name: layer.shape for layer in layers}
        for layer in layers:
            nearest = max(nearest, layer.depth)
            while pending and pending[0].depth < nearest:
                paint_item(pending.pop(0))
            paint_items(('before', layer.name))
            partner = None
            if layer.partner is not None:
                pname, s = layer.partner
                partner = (shapes[pname], ov.get(pname, ()), s)
            cv.paint_gap(layer.shape, pal['fig'], layer.gap, knock, layer.anchor, layer.r0, layer.r1,
                         overlays=ov.get(layer.name, ()), anchors=layer.anchors, partner=partner)
            paint_items(('after', layer.name))
        for it in pending:
            paint_item(it)
        paint_items('front')

    # ---- framing ----------------------------------------------------------------------

    def frame(self, samples=120):
        """Content box over the whole loop (cm), and the floor extent."""
        if self._frame is not None:
            return self._frame
        x0 = y0 = 1e9
        x1 = y1 = -1e9
        for i in range(samples):
            t = self.duration * i / samples
            J, v, items = self.state(t)
            for sh in [v.silhouette] + [it.shape for it in items if getattr(it, 'frame', True)]:
                b = sh.bbox()
                x0, y0, x1, y1 = min(x0, b[0]), min(y0, b[1]), max(x1, b[2]), max(y1, b[3])
        if self.floor:
            y0 = min(y0, -3.8)
        fl = (x0 - 12, x1 + 12)
        self._frame = dict(box=(x0, y0, x1, y1), floor=fl)
        return self._frame

    def canvas_for(self, px, mode='full', pal=PAL, bg=None):
        f = self.frame()
        x0, y0, x1, y1 = f['box']
        if mode == 'icon':
            x0 += 2
            x1 -= 2
            side = max(x1 - x0, y1 - y0) * 1.06
            scale = px / side
        else:
            margin = 60 * px / VIDEO_PX
            fit = min((px - 2 * margin) / max(x1 - x0, 1), (px - 2 * margin) / max(y1 - y0, 1))
            scale = min(SCALE * px / VIDEO_PX, fit)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        origin = (px / 2 - cx * scale, px / 2 + cy * scale)
        return Canvas(px, px, scale, origin, pal['bg'] if bg is None else bg)

    def render(self, t, px=VIDEO_PX, mode='full', pal=PAL):
        cv = self.canvas_for(px, mode, pal)
        self.paint(cv, t, pal, floor=(mode != 'icon'))
        return cv.to_uint8()


def exercise(key, group, camera='side', muscles=None, floor=True, near_arm_behind=False):
    """Decorator: the function returns (pose_fn, phase, equip_fn)."""
    def wrap(fn):
        def build():
            pose, phase, equip = fn()
            return Exercise(key, group, camera, pose, phase, equip, muscles, floor, near_arm_behind)
        REGISTRY[key] = build
        return fn
    return wrap


# ---- video output ----------------------------------------------------------------------

_EX = None
_ARGS = None


def _init(key, args):
    global _EX, _ARGS
    from . import exercises  # noqa: F401  (registers everything)
    _EX = REGISTRY[key]()
    _EX.frame()
    _ARGS = args


def _frame_rgb(i):
    px, mode, fps = _ARGS
    return _EX.render(i / fps, px, mode).tobytes()


def write_video(key, path, px=VIDEO_PX, mode='full', fps=FPS, workers=12, crf=14):
    """H.264 on the palette's background, for review and the web (the app draws live from rigs)."""
    from multiprocessing import Pool
    ex = REGISTRY[key]()
    n = int(round(ex.duration * fps))
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{px}x{px}',
           '-r', str(fps), '-i', '-', '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
           '-c:v', 'libx264', '-preset', 'slow', '-crf', str(crf), '-tune', 'animation',
           '-x264-params', 'colorprim=bt709:transfer=iec61966-2-1:colormatrix=bt709',
           '-profile:v', 'high', '-colorspace', 'bt709', '-color_primaries', 'bt709',
           '-color_trc', 'iec61966-2-1', '-color_range', 'tv', '-movflags', '+faststart', path]
    ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with Pool(workers, initializer=_init, initargs=(key, (px, mode, fps))) as pool:
        for buf in pool.imap(_frame_rgb, range(n), chunksize=4):
            ff.stdin.write(buf)
    ff.stdin.close()
    if ff.wait() != 0:
        raise RuntimeError(f'encoding {key} failed')
    return n
