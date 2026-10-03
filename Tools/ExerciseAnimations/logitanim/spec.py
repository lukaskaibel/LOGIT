"""The figure spec: the only place that decides how the character looks.

Everything that draws the character (animations, step stills, muscle-group figures) reads these
values. Exercise definitions never set sizes or colours of their own, so a change here restyles
every output at once and nothing can drift.
"""
import numpy as np


def hexc(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def rgb(r, g, b):
    return np.array([r / 255.0, g / 255.0, b / 255.0], np.float32)


# --- Proportions (cm), a ~178 cm figure ----------------------------------------------------

SHANK = 43.7        # knee -> ankle
THIGH = 43.6        # hip -> knee
TORSO = 49.0        # hip-joint midpoint -> shoulder-joint line
UPPER = 31.0        # shoulder -> elbow
FORE = 31.5         # elbow -> grip centre
FORE_WRIST = 26.0   # elbow -> wrist, for flat palms
ANKLE_H = 7.8       # ankle height when standing
HIP_HALF = 8.6      # hip joint distance from the midline
SHOULDER_HALF = 18.0
HIP_H = ANKLE_H + SHANK + THIGH

NECK_BASE = 55.0    # along the spine from the hips
HEAD_UP = 16.0      # head centre above the neck base
HEAD_FWD = 2.5      # ... and slightly forward

# Foot, in the foot frame (sole normal n, toe direction t), relative to the ankle.
HEEL = (-3.7, -4.2)     # (along n, along t)
TOE = (-4.8, 14.6)

# --- Widths (cm) ---------------------------------------------------------------------------

R_THIGH = (9.0, 6.9)
R_SHANK = (6.9, 4.9)
R_UPPER = (6.1, 5.2)
R_FORE = (5.2, 4.3)
R_HAND = 4.9
R_HEEL = 4.1
R_TOE = 3.0
R_HEAD = 12.5
# Seen from the front the legs read slimmer than their side-on depth, so the crotch opens.
R_THIGH_F = (7.9, 6.5)
R_SHANK_F = (6.5, 5.1)

GAP = 1.6           # knockout between overlapping parts (SF Symbols language)

# --- Palette (dark) ------------------------------------------------------------------------

PAL = dict(
    bg=hexc('1C1C1E'),          # the app's card colour (secondarySystemBackground)
    fig=hexc('F5F5F7'),
    plate=hexc('3A3A3C'),
    plate_rim=hexc('48484A'),
    metal=hexc('8E8E93'),
    pad=hexc('3A3A3C'),         # benches, machine pads
    frame=hexc('48484A'),       # machine frames, racks
    floor=hexc('2C2C2E'),
    ghost=hexc('313134'),
    far=hexc('636366'),
    accent=hexc('A6FE00'),      # LOGIT's lime accent in sRGB
    water=hexc('2C3A4A'),
)

MUSCLE = dict(
    chest=rgb(166, 206, 134), triceps=rgb(132, 190, 232), shoulders=rgb(240, 176, 128),
    biceps=rgb(118, 207, 192), back=rgb(142, 150, 222), legs=rgb(230, 202, 114),
    abdominals=rgb(168, 146, 214), cardio=rgb(224, 138, 166),
)

# --- Output --------------------------------------------------------------------------------

VIDEO_PX = 1080
SCALE = 4.0         # px per cm at 1080 px: the character is the same size in every clip
FPS = 60
