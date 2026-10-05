#!/bin/bash
# Build the macOS harness for the app's real-time exercise figure into out/metal/.
# It compiles the app's own sources, so it tests exactly what ships.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/../../../LOGIT/SharedUI/Views"
OUT="$HERE/../out/metal"
mkdir -p "$OUT"
xcrun -sdk macosx swiftc -O -o "$OUT/harness" \
  "$APP/ExerciseRig.swift" "$APP/ExerciseFigureScene.swift" "$APP/ExerciseFigureShaders.swift" "$HERE/main.swift"
echo "built $OUT/harness"
