# LOGIT exercise animations

One minimal character, drawn from a single spec, performs every default exercise.
Everything is Python (numpy + ffmpeg), plus a small Swift encoder for the app's transparent clips.
Output: looping videos for the app.

```
python3 build.py sheet <keys|all>          # key frames per exercise -> out/sheets/<key>.png (+ all.png for several)
python3 build.py video <keys|all>          # 1080 px review videos -> out/full/<key>.mp4
python3 build.py app [--force] <keys|all>  # the app's clips -> LOGIT/Resources/ExerciseAnimations/
python3 build.py web <keys|all>            # small H.264 loops + posters for sharing -> out/web/
python3 build.py check                     # which default exercises still have no definition
python3 build.py jumps <keys>              # largest frame-to-frame jump of the muscle highlight
```

## The app's clips

`build.py app` writes one transparent HEVC loop per exercise, `<key>.mov`, into
`LOGIT/Resources/ExerciseAnimations/` (a folder reference in the Xcode project): 288 px, 30 fps,
cropped tight to the figure with no floor. The app shows it at 96 pt beside the title of the
exercise detail screen (pixel for pixel on a 3x screen) and at 48 pt, bare, left of the name in the
exercise cells (exactly half). Both sit on the app's dark card and background colours, so the clip
uses the standard palette.

They are encoded by `encode_alpha.swift` (compiled into `out/bin/` on first use) through
AVFoundation, tagged BT.709 with the sRGB transfer function. Don't switch back to ffmpeg's
`hevc_videotoolbox` for these: it leaves alpha clips untagged, and iOS then decodes them as BT.709
gamma, which lifts the dark greys by about 8 levels. Existing clips are kept unless `--force`, so an
interrupted batch resumes. `ExerciseAnimationView.swift` looks clips up by the exercise's library
key (`_default.exercise.<key>`).

## Live 3D (prototype)

The figure is solved in 3D; only the drawing is flattened for one camera. `logitanim/view3d.py`
draws the same scene from any camera (yaw round the vertical, pitch above the horizon) by per-pixel
depth instead of body.py's fixed paint order. At the exercise's own camera it matches today's
frames to well under 1% of pixels. `build.py rig` bakes each exercise for the app's real-time
renderer into `LOGIT/Resources/ExerciseRigs/<key>.rig`, a few KB each (see `logitanim/export3d.py`).
The app's renderer is `ExerciseRig.swift`, `ExerciseFigureScene.swift` (a port of view3d) and
`ExerciseFigureShaders.swift`, a port of `view3d.composite` compiled from source at runtime. Change
the Python and Swift sides together. `metal/run.sh` builds a macOS harness from the app's own
sources that renders frames to PNG and times the GPU.

Equipment draws in 3D only when the helper that made it attaches `Item.spec3d` (3D primitives);
items without it exist for one camera only, and `build.py rig` skips their exercise. All 208 have
it. Build specs from the same 3D points the 2D code projects, with the helpers in `equipment.py`
(`rod3d`, `cone3d`, `cyl3d`, `ball3d`, `box3d`, `pad3d`, `post3d`, `rope3d`, `ring3d`, `plate3d`):
- **Independent of the camera.** The app bakes each exercise from its own camera and turns that one
  spec, so a spec that reads `v.cam` (the near plate only, say) looks right in every Python view
  and wrong in the app. Choose 2D shapes by camera, never 3D ones.
- **The same make-up every frame**: the same primitives in the same order; only numbers move. A part
  that must jump does so hidden (shrunk inside something), or the app's frame interpolation sweeps it.
- **Real sizes and both sides**: seats and pads have widths, paired parts exist on both sides, frames
  stand beside or behind the body, never through it.
- gap `'back'` makes a backdrop (walls, water): behind the figure from every side, and out of the
  framing. `Item(frame3d=False)` also leaves an item out of the framing (a thrown ball, a rope
  running off the picture), as `frame=False` does in 2D.

`build.py turn KEY` draws an exercise from eight angles for review, and `build.py rig` must write
every key it is given. The app's Metal port must match `view3d` (a harness run against all 208, at
two angles each, agreed to within 0.07% of pixels).

## Why it stays consistent

- **`logitanim/spec.py` is the only place that decides how the figure looks**: bone lengths, limb
  widths, head, colours, the knockout gap. Exercise files never set sizes or colours of their own
  (use the palette keys `'pad'`, `'frame'`, `'metal'`, `'plate'`, `'plate_rim'`, `'floor'`).
- **Exercises are motion, not drawings.** An exercise returns a pose function, a timeline and an
  equipment function. The skeleton (`rig.py`) solves joints, `body.py` draws the silhouette for the
  camera, `anatomy.py` places muscle highlights. Change the spec or the body and every exercise
  re-renders consistently (a second body type is just another spec).
- **Muscle highlights are attached to bones** (ellipsoids/patches in the bone's own frame, projected
  by the camera), so they move continuously and can never jump from one side of a limb to the other.

## Conventions

- Units are **cm**. World axes: **x forward** (the figure faces screen-right in the side view),
  **y up**, **z = the figure's right** (towards the camera in the side view). The floor is y = 0.
- Cameras: `'side'` (default, from the figure's right), `'front'`, `'back'`, `'top'`. Pick the view
  that shows the movement best: sagittal-plane movements side-on; lateral raises and flyes from the
  front (a flat dumbbell fly from `'top'`, since a side camera looks straight down the arc and the
  arm covers the chest); pull-ups/pulldowns and shrugs (lats, traps) from the back. Use
  `floor=False` with `'top'`.
- Lying on the back: `pitch=-90`, **head to the left** (-x). Lying face down / planks: `pitch=+90`,
  head to the right.
- A pose is a dict (see `rig.solve`):
  - `pelvis` (3D hip-joint midpoint), spine `pitch`/`roll`/`yaw` (deg; pitch + = lean forward),
    pelvis `p_pitch`/`p_roll`/`p_yaw`, `neck` (deg, + = chin up), `shrug`, `protract` (cm).
  - `legL`/`legR`: IK `{'foot': ankle target, 'pole': knee direction, 'foot_pitch': deg (+ toes up),
    'toe_out': deg}` or FK `{'hip': flex deg, 'abd': deg, 'knee': deg, 'ankle': deg}`.
  - `armL`/`armR`: IK `{'hand': grip target, 'pole': elbow direction}` (optionally `'palm': True,
    'palm_dir': ...` for flat hands on the floor, `'wrist_flex': deg` to curl the wrist, where
    `hand` is then the wrist) or FK `{'flex': deg, 'abd': deg, 'elbow': deg}`.
- `wrist_flex` bends the hand towards the inside of the elbow, measured against the upper arm, so
  it is undefined with the elbow at 90 degrees and mirrors past it. Keep the flex at 0 near a
  right-angled elbow, or build the arm the way `olympic.finish_arm` does (it solves the grip with
  the same rule and fades the flex out within 12 degrees of 90).
- Helpers in `exercises/common.py`: `standing`, `seated`, `feet`, `both` (mirror right-hand target),
  `Gait` (walk/run in place), `torso_point`, `solve_torso_for`, `rep`, `rep_down_first`, `Timeline`,
  `keys` (piecewise pose interpolation), `blend`, `merge`.
- Timing: **two reps per loop**, the loop must be seamless (end pose = start pose). Strength reps
  ~1.2–1.6 s per stroke with short holds (`rep`/`rep_down_first`). Cyclic cardio: whole cycles.
- Equipment (`equipment.py`): `barbell`, `plate_disc`, `dumbbell`, `kettlebell`, `medball`,
  `fixed_bar`, `bench` (flat/incline/decline), `pad`, `pad_box`, `post`, `box3`, `plyo_box`,
  `cable_stack`. See "Depth: what is in front of what" below for how items are ordered.
- Layers: `'base'` (torso, plus the legs it absorbs), `'head'`, and every limb in two halves:
  `'armL'`/`'armR'` (upper arm) with `'foreL'`/`'foreR'` (forearm and hand), and, in front and
  back views, `'legL'`/`'legR'` (thigh) with `'shinL'`/`'shinR'` (shank and foot). Side-on the
  legs stay whole (`'legL'`/`'legR'`), since both halves swing in the same plane.
- Muscles: name regions from `anatomy.ALL_REGIONS` (`pecs, abs, obliques, lats, traps, erectors,
  glutes, delts, biceps, triceps, forearms, quads, hamstrings, adductors, abductors, calves,
  hipflexors`). They are tinted with the exercise's muscle-group colour.

## Depth: what is in front of what

Every animation has to make sense in 3D: whatever is nearer the camera covers what is behind it.
The renderer is a painter (back to front), and the order comes from real depth wherever it can:

- **Limbs.** Each arm (and each front-view leg) is two layers ordered by depth. When the forearm
  comes in front of the upper arm (an Arnold press at the bottom, a front rack), it is drawn over
  it with the knockout gap and hides the shoulder's highlight behind it. The switch fades over 2.5 to
  4 cm of depth, so nothing pops. In front and back views the halves of both arms are sorted
  together by depth, so a bar held in both hands lies in front of both upper arms and behind both
  fists alike.
- **Arms behind the torso** (front and back views). An arm whose forearm is 14 cm or more on the far
  side of the torso's middle is drawn behind it (the forearms in front of the chest at the top of a
  pull-up seen from behind). `Exercise.behind_weights` times these switches over the loop: an arm
  switches only once it is 1 cm past the line, so a pose held on it stays put, and the switch
  dissolves over 0.2 s of the movement (the frame is painted both ways and blended).
- **Hands behind the head.** `near_arm_behind='forearm'` tucks the near forearm and hand in behind
  the head while the upper arm, on the camera side of the body, stays in front (crunches, sit-ups,
  dragon flags). `near_arm_behind=True` hides the whole near arm behind the body, for a hand that
  really is behind the back.
- **Equipment with a depth.** `Item(..., depth=cam.depth(p3))` is slotted between the figure's
  layers by how near the camera it is, and the depth wins over `z`. `eq.barbell` does this itself.
  Seen end-on, the plate at the camera end covers the arms and chest (bench press), the shins (a
  deadlift from the floor) and even part of the head (a back squat). So bars carried on the back use
  `plate_r=17`, which keeps the face readable; pulls from the floor keep the 22.5 plates their bar
  height depends on, and bars racked on the front that never touch the floor (military press, push
  press, jerks, thrusters) use 17 too. Seen along its length, a bar lies at the hands' depth, just
  behind the fists: a forearm layer's depth is its hand's, so held things slot in behind the fist
  however the forearm is angled. `eq.fixed_bar` seen end-on puts the bar's end in front of the
  fists (the bar reaches past the near hand towards the camera), on the far bracket.
- **Held implements.** `('before', 'armR')` puts an item just behind the right hand (the fist
  closes around it); it is mapped to the forearm layer, since the hand lives there. `eq.dumbbell`
  also fades a copy of its camera-side head over the hand as that head turns towards the camera,
  so end-on (curls seen from the side, lateral raises from the front) the head covers the grip.
- **Everything else** keeps a manual `z`: `'back'`, `'front'` (with a gap), or
  `('before'|'after', layer)`. Choose it from the geometry: in the side view the camera looks along
  -z (the right side, larger z, is nearer); in the front view along -x (forward is nearer); in the
  back view along +x; from the top along -y. A machine part at the near side of the figure goes in
  front of it. Give an item a `depth` when it moves between in front and behind.
- **Colliders.** Items can carry their 3D volume (`collider=`, see `scene.Item`); the helpers do.
  `build.py clip <keys>` then reports where the figure passes through equipment, the floor or
  itself, how deep and when. Contact is fine (hands close around items marked `grip=True`); fix
  what goes through, or explain why it can't be seen from this camera. It also reports `reach` (a
  hand or foot short of its target: the IK went straight and gave up), `cross` (left and right
  swapped), `slide` (a foot, knee or hand on the floor sliding along it; expected for walking and
  running in place, nowhere else) and `sunk` (equipment below the floor).
- **Held equipment on a fixed path** (a lever's arc, a bar pivoting on the floor) must stay within
  reach: past it the hands leave the handles, and a lever drawn to the hands changes length. End
  the path with `common.reach_limit` (the machine shoulder press and landmine press do).

## Review checklist (look at the sheet before calling an exercise done)

1. Contacts hold: feet planted, hands on the bar/handles/floor, nothing sinks into the floor or bench.
2. Joints are human: knees and elbows bend the right way, no hyperextension, spine plausible.
3. The movement matches the exercise's instructions in `LOGIT/Resources/default_exercises.json`.
4. The highlight sits on the working muscles and glides (run `build.py jumps <key>`). A high
   `jumps` value is not always a pop: fast limbs and an arm sliding over the highlight raise it too,
   so look at the frames around the worst one. What must never happen is a region flipping to the
   other side of a limb or vanishing for good (the forearm region derives its front from the elbow
   hinge for this reason; the traps' upper edge rides on the shoulders so a shrug lifts it).
5. The loop is seamless and the figure stays in frame.
6. It holds up in 3D: nothing nearer the camera is hidden behind something farther away, nothing
   passes through anything (`build.py clip <key>`), and the camera shows the movement's plane.
