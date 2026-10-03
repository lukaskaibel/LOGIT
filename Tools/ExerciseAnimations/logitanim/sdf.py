"""Signed-distance shapes and an anti-aliased canvas.

World units are centimetres, y up. Every shape knows its bounding box so the canvas only evaluates
the pixels a shape can touch.
"""
import math
import numpy as np


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def rgb(r, g, b):
    return np.array([r / 255.0, g / 255.0, b / 255.0], np.float32)


def mix(a, b, t):
    return (np.asarray(a, np.float32) * (1 - t) + np.asarray(b, np.float32) * t).astype(np.float32)


def V(x, y):
    return np.array([x, y], float)


# ----------------------------------------------------------------------------------------------
# Shapes


class Shape:
    def bbox(self):
        raise NotImplementedError

    def sdf(self, X, Y):
        raise NotImplementedError


class Circle(Shape):
    def __init__(self, c, r):
        self.c = np.asarray(c, float)
        self.r = float(r)

    def bbox(self):
        x, y = self.c
        return (x - self.r, y - self.r, x + self.r, y + self.r)

    def sdf(self, X, Y):
        return np.hypot(X - self.c[0], Y - self.c[1]) - self.r


class Cone(Shape):
    """Round cone (uneven capsule) from a (radius ra) to b (radius rb)."""

    def __init__(self, a, b, ra, rb=None):
        self.a = np.asarray(a, float)
        self.b = np.asarray(b, float)
        self.ra = float(ra)
        self.rb = float(ra if rb is None else rb)

    def bbox(self):
        a, b, ra, rb = self.a, self.b, self.ra, self.rb
        return (min(a[0] - ra, b[0] - rb), min(a[1] - ra, b[1] - rb),
                max(a[0] + ra, b[0] + rb), max(a[1] + ra, b[1] + rb))

    def sdf(self, X, Y):
        a, b, ra, rb = self.a, self.b, self.ra, self.rb
        d = b - a
        h = math.hypot(d[0], d[1])
        if h < 1e-6 or abs(ra - rb) >= h:
            return np.minimum(np.hypot(X - a[0], Y - a[1]) - ra, np.hypot(X - b[0], Y - b[1]) - rb)
        ux, uy = d / h
        px = X - a[0]
        py = Y - a[1]
        qy = px * ux + py * uy
        qx = np.abs(px * uy - py * ux)
        bb = (ra - rb) / h
        aa = math.sqrt(1 - bb * bb)
        k = -bb * qx + aa * qy
        d0 = np.hypot(qx, qy) - ra
        d1 = np.hypot(qx, qy - h) - rb
        dm = qx * aa + qy * bb - ra
        return np.where(k < 0, d0, np.where(k > aa * h, d1, dm))


class RBox(Shape):
    """Rounded rectangle centred at c with half extents hx, hy, corner radius r, rotated by ang."""

    def __init__(self, c, hx, hy, r=0.0, ang=0.0):
        self.c = np.asarray(c, float)
        self.hx, self.hy, self.r, self.ang = float(hx), float(hy), float(r), float(ang)

    def bbox(self):
        c, s = abs(math.cos(self.ang)), abs(math.sin(self.ang))
        ex = c * self.hx + s * self.hy
        ey = s * self.hx + c * self.hy
        return (self.c[0] - ex, self.c[1] - ey, self.c[0] + ex, self.c[1] + ey)

    def sdf(self, X, Y):
        px = X - self.c[0]
        py = Y - self.c[1]
        c, s = math.cos(-self.ang), math.sin(-self.ang)
        lx = c * px - s * py
        ly = s * px + c * py
        qx = np.abs(lx) - (self.hx - self.r)
        qy = np.abs(ly) - (self.hy - self.r)
        return (np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
                + np.minimum(np.maximum(qx, qy), 0) - self.r)


class Ellipse(Shape):
    """Approximate ellipse distance (exact on the boundary, good near it)."""

    def __init__(self, c, rx, ry, ang=0.0):
        self.c = np.asarray(c, float)
        self.rx, self.ry, self.ang = float(rx), float(ry), float(ang)

    def bbox(self):
        m = max(self.rx, self.ry)
        return (self.c[0] - m, self.c[1] - m, self.c[0] + m, self.c[1] + m)

    def sdf(self, X, Y):
        px = X - self.c[0]
        py = Y - self.c[1]
        c, s = math.cos(-self.ang), math.sin(-self.ang)
        lx = c * px - s * py
        ly = s * px + c * py
        k0 = np.hypot(lx / self.rx, ly / self.ry)
        k1 = np.hypot(lx / (self.rx * self.rx), ly / (self.ry * self.ry))
        return k0 * (k0 - 1) / np.maximum(k1, 1e-6)


class Poly(Shape):
    """Simple polygon (any winding), optionally dilated by r for rounded corners."""

    def __init__(self, pts, r=0.0):
        self.p = np.asarray(pts, float)
        self.r = float(r)

    def bbox(self):
        mn = self.p.min(0) - self.r
        mx = self.p.max(0) + self.r
        return (mn[0], mn[1], mx[0], mx[1])

    def sdf(self, X, Y):
        p = self.p
        n = len(p)
        d = None
        s = None
        for i in range(n):
            j = i - 1
            ex, ey = p[j] - p[i]
            wx = X - p[i][0]
            wy = Y - p[i][1]
            t = np.clip((wx * ex + wy * ey) / max(ex * ex + ey * ey, 1e-12), 0, 1)
            bx = wx - ex * t
            by = wy - ey * t
            dd = bx * bx + by * by
            d = dd if d is None else np.minimum(d, dd)
            c1 = Y >= p[i][1]
            c2 = Y < p[j][1]
            c3 = ex * wy > ey * wx
            flip = (c1 & c2 & c3) | (~c1 & ~c2 & ~c3)
            s = flip if s is None else (s ^ flip)
        sign = np.where(s, -1.0, 1.0)
        return sign * np.sqrt(d) - self.r


class Union(Shape):
    def __init__(self, shapes, k=0.0):
        self.shapes = [s for s in shapes if s is not None]
        self.k = float(k)

    def bbox(self):
        bs = [s.bbox() for s in self.shapes]
        return (min(b[0] for b in bs) - self.k, min(b[1] for b in bs) - self.k,
                max(b[2] for b in bs) + self.k, max(b[3] for b in bs) + self.k)

    def sdf(self, X, Y):
        d = self.shapes[0].sdf(X, Y)
        for sh in self.shapes[1:]:
            d2 = sh.sdf(X, Y)
            if self.k > 0:
                h = np.maximum(self.k - np.abs(d - d2), 0) / self.k
                d = np.minimum(d, d2) - h * h * self.k * 0.25
            else:
                d = np.minimum(d, d2)
        return d


class Intersect(Shape):
    def __init__(self, a, b):
        self.a, self.b = a, b

    def bbox(self):
        a, b = self.a.bbox(), self.b.bbox()
        return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))

    def sdf(self, X, Y):
        return np.maximum(self.a.sdf(X, Y), self.b.sdf(X, Y))


class Subtract(Shape):
    def __init__(self, a, b):
        self.a, self.b = a, b

    def bbox(self):
        return self.a.bbox()

    def sdf(self, X, Y):
        return np.maximum(self.a.sdf(X, Y), -self.b.sdf(X, Y))


class Offset(Shape):
    def __init__(self, a, g):
        self.a, self.g = a, float(g)

    def bbox(self):
        b = self.a.bbox()
        g = max(self.g, 0)
        return (b[0] - g, b[1] - g, b[2] + g, b[3] + g)

    def sdf(self, X, Y):
        return self.a.sdf(X, Y) - self.g


# ----------------------------------------------------------------------------------------------
# Canvas


class Canvas:
    def __init__(self, w, h, scale, origin, bg):
        """origin = pixel position (x, y from top-left) of world (0, 0)."""
        self.w, self.h, self.s = w, h, float(scale)
        self.ox, self.oy = origin
        self.bg = np.asarray(bg, np.float32)
        self.img = np.empty((h, w, 3), np.float32)
        self.img[:] = self.bg

    def region(self, bb, pad=2):
        x0, y0, x1, y1 = bb
        if x1 < x0 or y1 < y0:
            return None
        j0 = max(int(math.floor(self.ox + x0 * self.s)) - pad, 0)
        j1 = min(int(math.ceil(self.ox + x1 * self.s)) + pad, self.w)
        i0 = max(int(math.floor(self.oy - y1 * self.s)) - pad, 0)
        i1 = min(int(math.ceil(self.oy - y0 * self.s)) + pad, self.h)
        if j1 <= j0 or i1 <= i0:
            return None
        X = ((np.arange(j0, j1, dtype=np.float64) + 0.5 - self.ox) / self.s)[None, :]
        Y = ((self.oy - (np.arange(i0, i1, dtype=np.float64) + 0.5)) / self.s)[:, None]
        return i0, i1, j0, j1, X, Y

    def cover(self, d):
        return np.clip(0.5 - d * self.s, 0.0, 1.0)

    def paint(self, shape, color, alpha=1.0, overlays=()):
        """Fill shape with color. overlays = [(region_shape, color, alpha)] recolour parts of the
        fill (anti-aliased on the region edge only, so no fringe along the shape's silhouette)."""
        if shape is None:
            return
        r = self.region(shape.bbox())
        if r is None:
            return
        i0, i1, j0, j1, X, Y = r
        a = self.cover(shape.sdf(X, Y)).astype(np.float32) * alpha
        if not a.any():
            return
        col = np.broadcast_to(np.asarray(color, np.float32), a.shape + (3,))
        if overlays:
            col = col.copy()
            for osh, ocol, oalpha in overlays:
                oa = (self.cover(osh.sdf(X, Y)) * oalpha).astype(np.float32)
                col += (np.asarray(ocol, np.float32) - col) * oa[..., None]
        sub = self.img[i0:i1, j0:j1]
        sub += (col - sub) * a[..., None]

    def paint_gap(self, shape, color, gap, knock, anchor=None, r0=0.0, r1=0.0, overlays=(), anchors=(),
                  partner=None):
        """Paint `shape` with a knockout band `gap` wide around it, composited exactly (no
        double anti-aliasing where band and shape share an edge). With an anchor, the band
        tapers to nothing within r0..r1 of it, so a limb peels away from the body it grows from;
        `anchors` adds more (point, r0, r1) tapers, and the narrowest wins.

        partner = (shape, overlays, s): the other half of the same limb, painted just before.
        This part lies in front of it with strength s (0..1, from their depth difference): at 0
        the two read as one limb (no band between them and the partner's highlights show through),
        at 1 this part covers the partner's highlights and cuts its band into it."""
        if shape is None:
            return
        b = shape.bbox()
        r = self.region((b[0] - gap, b[1] - gap, b[2] + gap, b[3] + gap))
        if r is None:
            return
        i0, i1, j0, j1, X, Y = r
        d = shape.sdf(X, Y)
        tapers = ([(anchor, r0, r1)] if anchor is not None else []) + list(anchors)
        g = gap
        for pt, a0, a1 in tapers:
            t = np.clip((np.hypot(X - pt[0], Y - pt[1]) - a0) / (a1 - a0), 0, 1)
            g = g * (t * t * (3 - 2 * t))
        c = self.cover(d).astype(np.float32)
        cg = np.maximum(self.cover(d - g).astype(np.float32), c)
        if not cg.any():
            return
        col = np.broadcast_to(np.asarray(color, np.float32), c.shape + (3,))
        if overlays:
            col = col.copy()
            for osh, ocol, oalpha in overlays:
                oa = (self.cover(osh.sdf(X, Y)) * oalpha).astype(np.float32)
                col += (np.asarray(ocol, np.float32) - col) * oa[..., None]
        band = (cg - c)
        restore = None
        if partner is not None:
            pshape, poverlays, s = partner
            keep = 1.0 - float(s)
            if keep > 1e-4:
                pc = self.cover(pshape.sdf(X, Y)).astype(np.float32)
                pcol = np.broadcast_to(np.asarray(color, np.float32), c.shape + (3,)).copy()
                for osh, ocol, oalpha in poverlays:
                    oa = (self.cover(osh.sdf(X, Y)) * oalpha).astype(np.float32)
                    pcol += (np.asarray(ocol, np.float32) - pcol) * oa[..., None]
                    # the partner's highlight shows through this part while it isn't yet in front
                    col = col.copy() if not col.flags.writeable else col
                    col += (np.asarray(ocol, np.float32) - col) * (oa * keep)[..., None]
                # ... and the band doesn't cut into the partner while they read as one limb
                restore = band * pc * keep
        sub = self.img[i0:i1, j0:j1]
        k = np.asarray(knock, np.float32)
        if restore is None:
            sub[:] = sub * (1 - cg)[..., None] + k * band[..., None] + col * c[..., None]
        else:
            sub[:] = (sub * (1 - cg)[..., None] + k * (band - restore)[..., None] + pcol * restore[..., None]
                      + col * c[..., None])

    def to_uint8(self):
        return (np.clip(self.img, 0, 1) * 255 + 0.5).astype(np.uint8)
