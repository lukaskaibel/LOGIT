#!/usr/bin/env python3
"""Build and review the exercise animations.

  build.py sheet [keys|all]          key frames per exercise -> out/sheets/<key>.png (+ all.png)
  build.py video [keys|all]          review videos 1080 px -> out/full/<key>.mp4
  build.py app [--force] [keys|all]  app clips -> LOGIT/Resources/ExerciseAnimations/<key>.mov + <key>_icon.mov
  build.py web [keys|all]            small H.264 loops + posters for sharing -> out/web/
  build.py clip [keys|all]           3D check: body through equipment, floor or itself
  build.py rig [keys|all]            baked 3D data for the app's real-time renderer -> LOGIT/Resources/ExerciseRigs/
  build.py turn [--n=2 --px=220] keys   each exercise from every side (view3d) -> out/turn/<key>.png
  build.py check                     coverage against the default library + highlight continuity
  build.py frame <key> <sec> <png> [px]   one frame at a time for close inspection
  build.py sheet --out=<name> <keys>      name the combined sheet (default all.png)
  build.py sheet --full --n=8 --px=300 <keys>   n frames over the whole loop, tiles of px
"""
import json
import os
import sys
import time

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True          # no __pycache__ in the repo (worker processes inherit it)

from logitanim.scene import REGISTRY, write_video  # noqa: E402
from logitanim import exercises  # noqa: E402,F401
from logitanim.spec import MUSCLE  # noqa: E402

OUT = os.path.join(HERE, 'out')
LIB = os.path.join(HERE, '..', '..', 'LOGIT', 'Resources', 'default_exercises.json')


def library():
    d = json.load(open(LIB))
    return [(e['nameKey'].replace('_default.exercise.', ''), e['muscleGroup']) for e in d['exercises']]


def pick(args):
    if not args or args == ['all']:
        return sorted(REGISTRY)
    return [a for a in args if a in REGISTRY]


def sheet(keys, n=5, tile=300, out_name='all', full=False):
    """Key frames per exercise. By default the first rep (half of a loop longer than 5 s); with
    full=True, n frames spread over the whole loop (use it to review multi-part moves)."""
    os.makedirs(os.path.join(OUT, 'sheets'), exist_ok=True)
    rows = []
    for k in keys:
        ex = REGISTRY[k]()
        span = ex.duration if full or ex.duration <= 5 else ex.duration / 2
        ts = [span * i / n for i in range(n)]
        tiles = [Image.fromarray(ex.render(t, px=tile)) for t in ts]
        row = Image.new('RGB', (n * (tile + 4), tile), (0, 0, 0))
        for i, im in enumerate(tiles):
            row.paste(im, (i * (tile + 4), 0))
        row.save(os.path.join(OUT, 'sheets', f'{k}.png'))
        rows.append(row)
        print('sheet', k)
    if len(rows) > 1:
        H = sum(r.height + 6 for r in rows)
        W = max(r.width for r in rows)
        s = Image.new('RGB', (W, H), (0, 0, 0))
        y = 0
        for r in rows:
            s.paste(r, (0, y))
            y += r.height + 6
        s.save(os.path.join(OUT, 'sheets', f'{out_name}.png'))
        print('wrote', os.path.join(OUT, 'sheets', f'{out_name}.png'))


def video(keys):
    os.makedirs(os.path.join(OUT, 'full'), exist_ok=True)
    for k in keys:
        t0 = time.time()
        n = write_video(k, os.path.join(OUT, 'full', f'{k}.mp4'))
        print('video', k, n, f'{time.time() - t0:.1f}s')


def web(keys, px=360):
    """Small opaque loops for sharing on the web: out/web/<key>.mp4 (H.264 on the card colour,
    30 fps) plus a JPEG poster of the first frame, and out/web/index.json with names and groups."""
    d = os.path.join(OUT, 'web')
    os.makedirs(d, exist_ok=True)
    groups = dict(library())
    for k in keys:
        mp4 = os.path.join(d, f'{k}.mp4')
        write_video(k, mp4, px=px, mode='full', fps=30, crf=24)
        Image.fromarray(REGISTRY[k]().render(0.0, px=px)).save(os.path.join(d, f'{k}.jpg'), quality=86)
        print('web', k, os.path.getsize(mp4) // 1024, 'KB', flush=True)
    index = [dict(key=k, group=groups.get(k, REGISTRY[k]().group), camera=REGISTRY[k]().camera) for k in sorted(REGISTRY)]
    json.dump(index, open(os.path.join(d, 'index.json'), 'w'))


TURN_VIEWS = [(0.0, 0.0), (45.0, 0.0), (90.0, 0.0), (135.0, 0.0), (180.0, 0.0), (270.0, 0.0), (30.0, 30.0),
              (210.0, 30.0)]


def _turn_one(args):
    """One exercise from every side (see turn())."""
    import warnings
    warnings.filterwarnings('ignore')
    from PIL import ImageDraw
    from logitanim import view3d
    from logitanim.spec import PAL
    k, px, n = args
    ex = REGISTRY[k]()
    ex.frame()
    yaw0 = {'side': 0.0, 'front': 90.0, 'back': -90.0, 'top': 0.0}[ex.camera]
    pitch0 = 90.0 if ex.camera == 'top' else 0.0
    bounds = view3d.bounds3d(ex)
    floor = view3d.floor_disc(ex) if ex.floor else None
    rows, missing = [], 0
    for i in range(n):
        t = ex.duration * i / n
        tiles = [ex.render(t, px=px)]
        cv = ex.canvas_for(px, 'full', PAL)
        J, prims, m = view3d.scene(ex, t, view3d.Cam3(yaw0, pitch0), floor=floor)
        missing = max(missing, m)
        view3d.composite(cv, prims, PAL['bg'])
        tiles.append(cv.to_uint8())
        for dyaw, pitch in TURN_VIEWS[1:]:
            cam = view3d.Cam3(yaw0 + dyaw, pitch0 + pitch if pitch0 == 0 else pitch0 - pitch)
            cv = view3d.turn_canvas(bounds, cam, px)
            J, prims, m = view3d.scene(ex, t, cam, floor=floor)
            view3d.composite(cv, prims, PAL['bg'])
            tiles.append(cv.to_uint8())
        row = Image.fromarray(np.concatenate([np.pad(a, ((0, 0), (0, 3), (0, 0))) for a in tiles], axis=1))
        d = ImageDraw.Draw(row)
        labels = ['today', '3D same camera'] + [f'+{a:.0f}' + (f' / {p:.0f} up' if p else '') for a, p in TURN_VIEWS[1:]]
        for j, lab in enumerate(labels):
            d.text((j * (px + 3) + 4, 3), f'{k} t={t:.1f} {lab}' if j == 0 else lab, fill=(150, 150, 150))
        rows.append(np.asarray(row))
    img = np.concatenate([np.pad(r, ((0, 3), (0, 0), (0, 0))) for r in rows], axis=0)
    os.makedirs(os.path.join(OUT, 'turn'), exist_ok=True)
    path = os.path.join(OUT, 'turn', f'{k}.png')
    Image.fromarray(img).save(path)
    return k, path, missing


def turn(keys, px=220, n=2):
    """Each exercise from every side: per time, today's frame | the 3D renderer from the same camera |
    turned 45, 90, 135, 180, 270 deg | turned and seen from 30 deg above (twice) -> out/turn/<key>.png.
    Equipment without a 3D spec is left out of the 3D views (and counted)."""
    from multiprocessing import Pool
    with Pool(12) as pool:
        for k, path, missing in pool.imap(_turn_one, [(k, px, n) for k in keys]):
            print('turn', k, path, f'({missing} items without 3D)' if missing else '')


RIGS = os.path.join(HERE, '..', '..', 'LOGIT', 'Resources', 'ExerciseRigs')


def _rig_one(k):
    import warnings
    warnings.filterwarnings('ignore')
    from logitanim import export3d
    try:
        header, q = export3d.bake(REGISTRY[k]())
        blob = export3d.encode(header, q)
    except ValueError as e:
        return k, None, str(e)
    open(os.path.join(RIGS, f'{k}.rig'), 'wb').write(blob)
    return k, len(blob), None


def rigs(keys):
    """Baked 3D data for the app's real-time renderer: LOGIT/Resources/ExerciseRigs/<key>.rig (see
    logitanim/export3d.py). Exercises whose equipment exists only for one camera are skipped."""
    from multiprocessing import Pool
    os.makedirs(RIGS, exist_ok=True)
    with Pool(12) as pool:
        res = pool.map(_rig_one, keys)
    done = [(k, n) for k, n, e in res if n]
    for k, n, e in res:
        if e:
            print('rig', k, 'SKIPPED:', e)
    if done:
        sizes = sorted(n for _, n in done)
        print(f'rig: {len(done)} written, {sum(sizes) / 1e6:.2f} MB, median {sizes[len(sizes) // 2] / 1024:.1f} KB, '
              f'largest {sizes[-1] / 1024:.1f} KB')


def _clip_line(k):
    from logitanim import clip
    worst = clip.check(REGISTRY[k]())
    bad = sorted(worst.items(), key=lambda kv: -kv[1][0])
    if not bad:
        return f'{k}: ok'
    return f'{k}: ' + '; '.join(f'{kind} {a}/{b} {d:.1f} cm @{t:.2f}s' for (kind, a, b), (d, t) in bad[:10])


def clips(keys):
    """3D interpenetration per exercise (see logitanim/clip.py): what passes through what, how deep,
    and when. Contact is fine; this lists penetration beyond the tolerances."""
    from multiprocessing import Pool
    with Pool(12) as pool:
        for line in pool.imap(_clip_line, keys):
            print(line, flush=True)


def continuity(key, fps=30, px=240):
    """Largest frame-to-frame jump of the highlight's centroid (px). Highlights must glide."""
    ex = REGISTRY[key]()
    col = (MUSCLE[ex.group] * 255).astype(int)
    n = int(ex.duration * fps)
    prev = None
    worst = 0.0
    for i in range(n):
        img = ex.render(i / fps, px=px).astype(int)
        m = np.abs(img - col).sum(axis=2) < 40
        if m.sum() < 4:
            prev = None
            continue
        ys, xs = np.nonzero(m)
        c = np.array([xs.mean(), ys.mean()])
        if prev is not None:
            worst = max(worst, float(np.linalg.norm(c - prev)))
        prev = c
    return worst


def check():
    lib = library()
    missing = [k for k, _ in lib if k not in REGISTRY]
    wrong = [(k, g, REGISTRY[k]().group) for k, g in lib if k in REGISTRY and REGISTRY[k]().group != g]
    print(f'{len(lib) - len(missing)}/{len(lib)} exercises defined')
    if missing:
        print('missing:', ' '.join(missing))
    if wrong:
        print('group mismatch:', wrong)


if __name__ == '__main__':
    cmd, args = sys.argv[1], sys.argv[2:]
    out_name, n_frames, tile, full = 'all', 5, 300, False
    for a in list(args):
        if a.startswith('--out='):
            out_name = a.split('=', 1)[1]
            args.remove(a)
        elif a.startswith('--n='):
            n_frames = int(a.split('=', 1)[1])
            args.remove(a)
        elif a.startswith('--px='):
            tile = int(a.split('=', 1)[1])
            args.remove(a)
        elif a == '--full':
            full = True
            args.remove(a)
    if cmd == 'sheet':
        sheet(pick(args), n=n_frames, tile=tile, out_name=out_name, full=full)
    elif cmd == 'frame':
        # build.py frame <key> <seconds> <out.png> [px]
        k, t, path = args[0], float(args[1]), args[2]
        px = int(args[3]) if len(args) > 3 else 720
        Image.fromarray(REGISTRY[k]().render(t, px=px)).save(path)
        print(path)
    elif cmd == 'video':
        video(pick(args))
    elif cmd == 'web':
        web(pick(args))
    elif cmd == 'clip':
        clips(pick(args))
    elif cmd == 'rig':
        rigs(pick(args))
    elif cmd == 'turn':
        turn(pick(args), px=tile if tile != 300 else 220, n=n_frames if n_frames != 5 else 2)
    elif cmd == 'check':
        check()
    elif cmd == 'jumps':
        for k in pick(args):
            print(k, round(continuity(k), 1))
