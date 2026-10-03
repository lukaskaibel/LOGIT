//
//  ExerciseFigureShaders.swift
//  LOGIT
//

/// The exercise figure, drawn per pixel from the primitives ExerciseFigureScene builds: each pixel
/// gathers the primitives that cover it (or whose knockout band reaches it), orders them by depth
/// and paints them back to front. A primitive cuts its band into what is on top so far as far as it
/// lies in front of it (2.5 to 4 cm: nothing to all), never into its own group, and the highlight of
/// a part shows through a part that isn't yet clearly in front of it. A port of view3d.composite in
/// Tools/ExerciseAnimations: change the two together.
///
/// Kept as source and compiled when first needed (a few milliseconds), so building the app needs no
/// Metal toolchain.
enum ExerciseFigureShaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 origin;      // pixel position of the world origin
    float scale;        // pixels per cm
    uint primCount;
};

struct Prim {
    float4 bbox;
    uint4 info;         // kind, group, first overlay, overlay count
    float4 color;       // rgb, knockout band width
    float4 p0, p1, p2, p3, p4;
    float4 a0, a1;
    uint4 range;
};

struct Overlay {
    uint4 info;         // kind (0 ellipse, 1 polygon), first vertex, vertex count
    float4 g0;
    float4 g1;
    float4 color;
};

constant uint KIND_CONE = 0, KIND_CIRCLE = 1, KIND_CYLINDER = 2, KIND_BOX = 3, KIND_TORSO = 4,
              KIND_FLOOR_BOX = 5, KIND_FLOOR_ELLIPSE = 6;
constant float FAR = 1000.0;
constant float SPLIT_NEAR = 2.5, SPLIT_FULL = 4.0;
constant int MAX_ACTIVE = 8;

struct VOut {
    float4 position [[position]];
};

vertex VOut figure_vertex(uint vid [[vertex_id]]) {
    const float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VOut o;
    o.position = float4(pos[vid], 0, 1);
    return o;
}

// ---- signed distances (sdf.py) ------------------------------------------------------------------

static float sd_cone(float2 p, float2 a, float2 b, float ra, float rb) {
    float2 d = b - a;
    float h = length(d);
    if (h < 1e-6 || abs(ra - rb) >= h) {
        return min(length(p - a) - ra, length(p - b) - rb);
    }
    float2 u = d / h;
    float2 q = p - a;
    float qy = dot(q, u);
    float qx = abs(q.x * u.y - q.y * u.x);
    float bb = (ra - rb) / h;
    float aa = sqrt(1.0 - bb * bb);
    float k = -bb * qx + aa * qy;
    if (k < 0.0) return length(float2(qx, qy)) - ra;
    if (k > aa * h) return length(float2(qx, qy - h)) - rb;
    return qx * aa + qy * bb - ra;
}

static float sd_rbox(float2 p, float2 c, float hx, float hy, float r, float ang) {
    float2 q = p - c;
    float cs = cos(-ang), sn = sin(-ang);
    float2 l = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    float2 d = abs(l) - float2(hx - r, hy - r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

static float sd_ellipse(float2 p, float2 c, float rx, float ry, float ang) {
    float2 q = p - c;
    float cs = cos(-ang), sn = sin(-ang);
    float2 l = float2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
    float k0 = length(l / float2(rx, ry));
    float k1 = length(l / float2(rx * rx, ry * ry));
    return k0 * (k0 - 1.0) / max(k1, 1e-6);
}

static float sd_poly(float2 p, const device float2 *v, uint start, uint n, float r) {
    float d = INFINITY;
    bool inside = false;
    for (uint i = 0; i < n; i++) {
        float2 vi = v[start + i];
        float2 vj = v[start + (i + n - 1) % n];
        float2 e = vj - vi;
        float2 w = p - vi;
        float t = clamp(dot(w, e) / max(dot(e, e), 1e-12), 0.0, 1.0);
        float2 b = w - e * t;
        d = min(d, dot(b, b));
        bool c1 = p.y >= vi.y, c2 = p.y < vj.y, c3 = e.x * w.y > e.y * w.x;
        if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) inside = !inside;
    }
    return (inside ? -1.0 : 1.0) * sqrt(d) - r;
}

static float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

static float sd_torso(float2 p, Prim pr, const device float2 *verts, const device float4 *aux) {
    float loft = INFINITY;
    for (uint k = 0; k < pr.range.y; k++) {
        float4 h = aux[pr.range.x + k];
        loft = min(loft, sd_poly(p, verts, uint(h.x), uint(h.y), pr.p1.w));
    }
    float yoke = sd_cone(p, pr.p0.xy, pr.p0.zw, pr.p1.x, pr.p1.x);
    float caps = min(length(p - pr.p2.xy), length(p - pr.p2.zw)) - pr.p1.y;
    return smin(loft, min(yoke, caps), pr.p1.z);
}

static float sdf(Prim pr, float2 p, const device float2 *verts, const device float4 *aux) {
    switch (pr.info.x) {
    case KIND_CONE: return sd_cone(p, pr.p0.xy, pr.p0.zw, pr.p1.x, pr.p1.y);
    case KIND_CIRCLE: return length(p - pr.p0.xy) - pr.p0.z;
    case KIND_CYLINDER: return sd_rbox(p, pr.p0.xy, pr.p0.z, pr.p0.w, pr.p1.x, pr.p1.y);
    case KIND_BOX: return sd_poly(p, verts, pr.range.x, pr.range.y, pr.p1.x);
    case KIND_TORSO: return sd_torso(p, pr, verts, aux);
    case KIND_FLOOR_BOX: return sd_rbox(p, pr.p0.xy, pr.p0.z, pr.p0.w, pr.p1.x, 0.0);
    default: return sd_ellipse(p, pr.p0.xy, pr.p0.z, pr.p0.w, 0.0);
    }
}

// ---- depth (view3d.py) ------------------------------------------------------------------------------

static float depth_cone(float2 p, Prim pr) {
    float2 a = pr.p0.xy, b = pr.p0.zw;
    float2 ab = b - a;
    float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-9), 0.0, 1.0);
    float dperp = length(p - (a + ab * t));
    float rv = mix(pr.p2.z, pr.p2.w, t);
    float rs = max(mix(pr.p1.x, pr.p1.y, t), 1e-3);
    float q = dperp / rs;
    return mix(pr.p2.x, pr.p2.y, t) + rv * sqrt(clamp(1.0 - q * q, 0.0, 1.0));
}

static float depth_cylinder(float2 p, Prim pr) {
    float3 c = pr.p2.xyz, ax = pr.p3.xyz;
    float r = pr.p2.w, half_len = pr.p3.w;
    float3 o = float3(p, FAR), dir = float3(0, 0, -1);
    float3 w = o - c;
    float wa = dot(w, ax), da = dot(dir, ax);
    float3 wp = w - wa * ax, dp = dir - da * ax;
    float A = dot(dp, dp);
    float best = INFINITY;
    if (A > 1e-9) {
        float B = 2.0 * dot(wp, dp), C = dot(wp, wp) - r * r;
        float disc = B * B - 4.0 * A * C;
        if (disc >= 0.0) {
            float t = (-B - sqrt(disc)) / (2.0 * A);
            if (abs(wa + t * da) <= half_len) best = t;
        }
    }
    if (abs(da) > 1e-9) {
        for (int k = 0; k < 2; k++) {
            float sgn = k == 0 ? -1.0 : 1.0;
            float t = (sgn * half_len - wa) / da;
            float3 q = w + t * dir - sgn * half_len * ax;
            if (dot(q, q) <= r * r && t < best) best = t;
        }
    }
    if (isfinite(best)) return FAR - best;
    // off it (its anti-aliased edge and knockout band): the depth of its outline there, the axis point
    // nearest the pixel, or the near cap's centre when the axis points at the camera
    float s2 = dot(ax.xy, ax.xy);
    float t = clamp(dot(p - c.xy, ax.xy) / max(s2, 1e-9), -half_len, half_len);
    return mix(pr.p4.x, c.z + t * ax.z, smoothstep(0.2, 0.5, sqrt(s2)));
}

static bool box_slab(float2 p, Prim pr, thread float &tn) {
    float3 w = float3(p, FAR) - pr.p2.xyz;
    float3 dir = float3(0, 0, -1);
    float tf = INFINITY;
    tn = -INFINITY;
    float4 axes[3] = { pr.p3, pr.p4, pr.a0 };
    for (int i = 0; i < 3; i++) {
        float3 a = axes[i].xyz;
        float h = axes[i].w;
        float wa = dot(w, a), da = dot(dir, a);
        if (abs(da) < 1e-9) {
            if (abs(wa) > h) return false;
            continue;
        }
        float t1 = (-h - wa) / da, t2 = (h - wa) / da;
        tn = max(tn, min(t1, t2));
        tf = min(tf, max(t1, t2));
    }
    return tn <= tf && isfinite(tn);
}

static float depth_box(float2 p, Prim pr, const device float2 *verts) {
    float tn;
    if (box_slab(p, pr, tn)) return FAR - tn;
    // off it (its anti-aliased edge and knockout band): the front face's depth at the nearest point of
    // its outline's inner hull, so a band never stands nearer than the box's own edge
    uint start = pr.range.x, n = pr.range.y;
    float2 q = p;
    float best = INFINITY;
    for (uint i = 0; i < n; i++) {
        float2 a = verts[start + i], e = verts[start + (i + 1) % n] - a;
        float2 s = a + e * clamp(dot(p - a, e) / max(dot(e, e), 1e-12), 0.0, 1.0);
        float d = distance_squared(p, s);
        if (d < best) {
            best = d;
            q = s;
        }
    }
    return box_slab(q + (pr.p2.xy - q) * 0.01, pr, tn) ? FAR - tn : pr.p2.w;
}

static float depth_torso(float2 p, Prim pr, const device float4 *aux) {
    float2 b2 = pr.p3.xy, t2 = pr.p3.zw;
    float2 axis = t2 - b2;
    float t = clamp(dot(p - b2, axis) / max(dot(axis, axis), 1e-9), 0.0, 1.0);
    float h = mix(pr.a1.z, pr.a1.w, t);
    // the section table, ascending by height
    uint s0 = pr.range.z, n = pr.range.w;
    float4 lo = aux[s0], hi = aux[s0 + n - 1];
    float4 sec = h <= lo.x ? lo : (h >= hi.x ? hi : lo);
    for (uint k = 0; k + 1 < n; k++) {
        float4 a = aux[s0 + k], b = aux[s0 + k + 1];
        if (h >= a.x && h <= b.x) {
            sec = mix(a, b, (h - a.x) / max(b.x - a.x, 1e-6));
            break;
        }
    }
    float2 center = b2 + axis * t + pr.p4.zw * sec.y;
    float off = length(p - center);
    float q = off / max(sec.w, 1e-3);
    float prof = sqrt(clamp(1.0 - q * q, 0.0, 1.0));
    return mix(pr.p4.x, pr.p4.y, t) + sec.y * pr.a1.x + pr.a1.y * sec.z * prof;
}

static float depth(Prim pr, float2 p, const device float2 *verts, const device float4 *aux) {
    switch (pr.info.x) {
    case KIND_CONE: return depth_cone(p, pr);
    case KIND_CIRCLE: {
        float d = length(p - pr.p0.xy);
        return pr.p2.x + sqrt(max(pr.p2.y * pr.p2.y - d * d, 0.0));
    }
    case KIND_CYLINDER: return depth_cylinder(p, pr);
    case KIND_BOX: return depth_box(p, pr, verts);
    case KIND_TORSO: return depth_torso(p, pr, aux);
    default: return -1e6;
    }
}

// ---- compositing ------------------------------------------------------------------------------------

struct Active {
    float z;
    float c;        // coverage of the shape
    float cg;       // coverage of the shape and its band
    uint index;
};

static float taper(float2 p, float4 a) {
    if (a.w <= 0.0) return 1.0;
    float t = clamp((length(p - a.xy) - a.z) / (a.w - a.z), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

fragment float4 figure_fragment(VOut in [[stage_in]],
                                constant Uniforms &u [[buffer(0)]],
                                const device Prim *prims [[buffer(1)]],
                                const device float2 *verts [[buffer(2)]],
                                const device Overlay *overlays [[buffer(3)]],
                                const device float4 *aux [[buffer(4)]]) {
    float2 p = float2((in.position.x - u.origin.x) / u.scale, (u.origin.y - in.position.y) / u.scale);
    float aa = 1.0 / u.scale;

    Active act[MAX_ACTIVE];
    int na = 0;
    for (uint i = 0; i < u.primCount; i++) {
        Prim pr = prims[i];
        float pad = pr.color.w + 2.0 * aa;
        if (p.x < pr.bbox.x - pad || p.x > pr.bbox.z + pad || p.y < pr.bbox.y - pad || p.y > pr.bbox.w + pad) continue;
        float d = sdf(pr, p, verts, aux);
        // only limbs taper their band near a joint (a0/a1 carry other parameters elsewhere)
        float g = pr.color.w;
        if (pr.info.x == KIND_CONE || pr.info.x == KIND_CIRCLE) g *= taper(p, pr.a0) * taper(p, pr.a1);
        float c = clamp(0.5 - d * u.scale, 0.0, 1.0);
        float cg = max(clamp(0.5 - (d - g) * u.scale, 0.0, 1.0), c);
        if (cg <= 0.0) continue;
        float z = depth(pr, p, verts, aux);
        if (pr.info.x != KIND_TORSO && pr.range.w == 1u) z -= 1.0e5;    // a backdrop: behind everything
        // keep the MAX_ACTIVE nearest, sorted back to front
        int k = na < MAX_ACTIVE ? na : MAX_ACTIVE - 1;
        if (na == MAX_ACTIVE && z <= act[0].z) continue;
        if (na == MAX_ACTIVE) {
            for (int m = 0; m < MAX_ACTIVE - 1; m++) act[m] = act[m + 1];
        } else {
            na++;
        }
        while (k > 0 && act[k - 1].z > z) {
            act[k] = act[k - 1];
            k--;
        }
        act[k] = Active{ z, c, cg, i };
    }

    float3 col = float3(0.0);
    float alpha = 0.0;
    float topZ = -INFINITY;
    int topGroup = -1;
    float topOA = 0.0;
    float3 topOC = float3(0.0);
    for (int k = 0; k < na; k++) {
        Prim pr = prims[act[k].index];
        float c = act[k].c, cg = act[k].cg, z = act[k].z;
        float lead = isfinite(topZ) ? z - topZ : 99.0;
        float s = clamp((lead - SPLIT_NEAR) / (SPLIT_FULL - SPLIT_NEAR), 0.0, 1.0);
        s = s * s * (3.0 - 2.0 * s);
        if (int(pr.info.y) == topGroup) s = 0.0;
        float band = (cg - c) * s;

        // its own highlight
        float oa = 0.0;
        float3 oc = float3(0.0);
        for (uint m = 0; m < pr.info.w; m++) {
            Overlay ov = overlays[pr.info.z + m];
            float od = ov.info.x == 0 ? sd_ellipse(p, ov.g0.xy, ov.g0.z, ov.g0.w, ov.g1.x)
                                      : sd_poly(p, verts, ov.info.y, ov.info.z, ov.g0.x);
            float a = clamp(0.5 - od * u.scale, 0.0, 1.0) * ov.color.w;
            oc += (ov.color.rgb - oc) * a;
            oa = oa + (1.0 - oa) * a;
        }
        if (oa > 1e-6) oc /= oa;
        float3 fill = pr.color.rgb + (oc - pr.color.rgb) * oa;
        // the highlight of the part behind shows through where this one isn't clearly in front
        float through = topOA * (1.0 - s);
        fill += (topOC - fill) * through;

        // knock out to transparent: premultiplied colour and alpha both lose the band
        col = col * (1.0 - c - band) + fill * c;
        alpha = alpha * (1.0 - c - band) + c;
        if (c > 0.5) {
            topZ = z;
            topGroup = int(pr.info.y);
            if (oa > 0.0) topOC = oc;
            topOA = max(oa, through);
        }
    }
    return float4(col, alpha);
}
"""#
}
