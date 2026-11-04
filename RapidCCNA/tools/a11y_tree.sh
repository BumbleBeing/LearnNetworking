#!/usr/bin/env bash
# Shows what a Linux screen reader (Orca) gets from each screen, without a desktop:
# starts a virtual display, a D-Bus session and the AT-SPI accessibility bus, runs the game
# with accessibility always on, and prints each screen's accessibility tree.
#
# Ubuntu packages: xvfb at-spi2-core python3-pyatspi gir1.2-atspi-2.0
# Usage: tools/a11y_tree.sh <screen>[:answer]...     (screens: see tools/a11y_tour.gd)
#   GODOT=path/to/godot  PYTHON=python3.12  WAIT=7  SIZE=1280x720  LOG=godot.log
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
PYTHON=${PYTHON:-python3}
WAIT=${WAIT:-7}
SIZE=${SIZE:-1280x720}
[ $# -gt 0 ] || set -- main

export DISPLAY=:97
Xvfb "$DISPLAY" -screen 0 "${SIZE}x24" >/dev/null 2>&1 & XPID=$!
eval "$(dbus-daemon --session --fork --print-address=1 --print-pid=1 | { read -r a; read -r p; echo "export DBUS_SESSION_BUS_ADDRESS=$a; DPID=$p"; })"
/usr/libexec/at-spi-bus-launcher --launch-immediately >/dev/null 2>&1 & BPID=$!
sleep 1
for prop in IsEnabled ScreenReaderEnabled; do
  dbus-send --session --dest=org.a11y.Bus /org/a11y/bus org.freedesktop.DBus.Properties.Set \
    string:org.a11y.Status "string:$prop" variant:boolean:true
done
trap 'kill $XPID $BPID $DPID 2>/dev/null' EXIT

for spec in "$@"; do
  screen=${spec%%:*}; after=""; [[ $spec == *:* ]] && after=${spec#*:}
  echo "=== $spec"
  "$GODOT" --path . --accessibility always --display-driver x11 --resolution "$SIZE" \
    res://tools/a11y_tour.tscn -- "$screen" $after >"${LOG:-/dev/null}" 2>&1 & GPID=$!
  sleep "$WAIT"
  "$PYTHON" tools/a11y_dump.py 15 2>/dev/null | grep -v "dbind-WARNING"
  kill $GPID 2>/dev/null; wait $GPID 2>/dev/null
done
