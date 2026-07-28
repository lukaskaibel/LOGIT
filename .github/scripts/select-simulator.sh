#!/usr/bin/env bash
#
# Picks an iPhone simulator for the UI test jobs and writes its destination to
# $GITHUB_ENV as IOS_TEST_DESTINATION.
#
# Selects the newest installed iOS runtime that actually has an iPhone device: the
# app's deployment target is iOS 26.0, so older runtimes can't run it at all, and
# runner images gain runtimes over time. Targets the device by UDID rather than by
# name so the destination can't resolve to some other booted device.
#
# Known-good locally is iOS 26.4 — the 26.0 test runner dies nondeterministically
# ("Test crashed with signal kill"). The UI jobs pass -retry-tests-on-failure to
# absorb that class of failure whatever the runner image ships.

set -euo pipefail

DEVICES_JSON=$(xcrun simctl list devices available --json)

SELECTED=$(printf '%s' "$DEVICES_JSON" | jq -r '
  .devices
  | to_entries
  | map(select(.key | test("SimRuntime\\.iOS-")))
  | map(select(.value | map(select(.name | startswith("iPhone"))) | length > 0))
  | sort_by(.key | capture("iOS-(?<major>[0-9]+)-(?<minor>[0-9]+)") | [(.major | tonumber), (.minor | tonumber)])
  | last
  | (.value | map(select(.name | startswith("iPhone"))) | .[0]) as $device
  | "\(.key)\t\($device.name)\t\($device.udid)"
')

if [ -z "$SELECTED" ] || [ "$SELECTED" = "null" ]; then
  echo "No available iPhone simulator on any iOS runtime"
  xcrun simctl list devices available
  exit 1
fi

RUNTIME=$(printf '%s' "$SELECTED" | cut -f1)
NAME=$(printf '%s' "$SELECTED" | cut -f2)
UDID=$(printf '%s' "$SELECTED" | cut -f3)

echo "Using $NAME ($UDID) on ${RUNTIME##*SimRuntime.}"
echo "IOS_TEST_DESTINATION=platform=iOS Simulator,id=$UDID" >> "$GITHUB_ENV"
