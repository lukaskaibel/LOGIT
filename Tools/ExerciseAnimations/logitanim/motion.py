"""Timing and pose interpolation."""
import copy
import numpy as np


def ease(x):
    """Minimum-jerk profile: how people move between two rests."""
    x = min(max(x, 0.0), 1.0)
    return x * x * x * (10 - 15 * x + 6 * x * x)


def smooth(a, b, x):
    x = min(max((x - a) / (b - a), 0.0), 1.0)
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


class Timeline:
    """Segments of (seconds, from, to) for a phase value; loops seamlessly.
    linear=True for phase values that already encode their own timing (multi-step sequences)."""

    def __init__(self, segs, linear=False):
        self.segs = segs
        self.total = sum(s[0] for s in segs)
        self.linear = linear

    def __call__(self, t):
        t = t % self.total
        for dur, a, b in self.segs:
            if t < dur:
                if a == b:
                    return a
                x = t / dur
                v = a + (b - a) * (x if self.linear else ease(x))
                # never overshoot the ends through rounding (a phase of -1e-17 breaks u ** 1.35)
                return min(max(v, min(a, b)), max(a, b))
            t -= dur
        return self.segs[-1][2]


def rep(concentric, eccentric, top=0.45, bottom=0.2, reps=2, start_at_end=False):
    """A strength rep between phase 0 (start) and 1 (end of the working stroke).
    concentric: seconds from 0 to 1; eccentric: 1 back to 0; holds at both ends."""
    one = [(top, 0, 0), (concentric, 0, 1), (bottom, 1, 1), (eccentric, 1, 0)]
    return Timeline(one * reps)


def rep_down_first(down, up, top=0.45, bottom=0.2, reps=2):
    """For lifts that start at the top and lower first (squat, push-up, bench press)."""
    one = [(top, 0, 0), (down, 0, 1), (bottom, 1, 1), (up, 1, 0)]
    return Timeline(one * reps)


class Cycle:
    """A continuous cyclic phase (gait, pedalling): returns phase in [0, 1)."""

    def __init__(self, period, cycles):
        self.period = period
        self.total = period * cycles

    def __call__(self, t):
        return (t % self.total) / self.period % 1.0


def blend(a, b, t):
    """Interpolate two pose dicts (numbers, arrays, nested dicts). Keys missing in one side
    are taken from the other."""
    if isinstance(a, dict):
        out = {}
        for k in set(a) | set(b):
            if k in a and k in b:
                out[k] = blend(a[k], b[k], t)
            else:
                out[k] = copy.deepcopy(a.get(k, b.get(k)))
        return out
    if isinstance(a, (bool, str)) or a is None:
        return a if t < 0.5 else b
    return a + (np.asarray(b) - np.asarray(a)) * t if isinstance(a, np.ndarray) else a + (b - a) * t


def keys(*poses, spans=None):
    """Piecewise pose function over u in [0, 1] through the given key poses. Each span eases
    on its own, so intermediate keys are passed through smoothly at rest points only when
    the timeline holds there."""
    n = len(poses) - 1
    spans = spans or [1.0 / n] * n
    edges = np.cumsum([0.0] + list(spans))

    def f(u):
        u = min(max(u, 0.0), 1.0)
        for i in range(n):
            if u <= edges[i + 1] + 1e-9:
                t = (u - edges[i]) / max(edges[i + 1] - edges[i], 1e-9)
                return blend(poses[i], poses[i + 1], t)
        return copy.deepcopy(poses[-1])
    return f


def merge(base, **changes):
    """Copy of a pose dict with nested updates: merge(p, legR={'foot': ...}, pitch=10)."""
    out = copy.deepcopy(base)
    for k, v in changes.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            d = dict(out[k])
            d.update(v)
            out[k] = d
        else:
            out[k] = v
    return out
