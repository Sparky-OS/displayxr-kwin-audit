#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# handdrag.sh OUTDIR TAG "KINDS": the hand-drag rest case David Fattal found on the Samsung Odyssey 3D
# (DisplayXR/displayxr-runtime#1928, 2026-10-14): a drag whose pointer steps are smaller than a logical
# pixel, then a pause. The window then rests on a fractional position; while move sync held it, the
# publisher reported buffer_device as the conversion of buffer, and at the rest it is where KWin paints,
# which can differ by one device pixel. The publisher must send WindowsChanged when that happens, or the
# runtime keeps weaving for the old pixel. cube_handle_vk_linux with DXR_WL_ORIGIN_STAMP=1 and move sync
# on. Per KIND (drag_driver.py's profiles; rest_F ends on frame fraction F, so rest_0.25 and rest_0.75 land
# on device pixels no whole logical value names at 200 %, rest_0.6 at 125 %; rest_0 is the whole-position
# control): WindowsChanged
# is recorded for the whole drag and the pause; the window is put at 60,120 from the output origin, dragged
# from the middle of its title bar, and 2.5 s after the release the output is captured and GetWindows read.
# handdrag_check.py compares, per drag: GetWindows' buffer_device, the last WindowsChanged payload's
# buffer_device and its time against the release, where the stamp is painted and the origin it encodes.
# Results: OUTDIR/handdrag.md.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_clean_session
need_tools fake-click
need_app
OUT=$1 TAG=$2 KINDS=$3
mkdir -p "$OUT"
export AUDIT_OUT=$OUT
info=$(output_info | head -1)
ox=$(echo "$info" | awk '{print $2}'); oy=$(echo "$info" | awk '{print $3}')
: > "$OUT/marks-$TAG.txt"
: > "$OUT/rests-$TAG.txt"
DXR_APP_ENV="${DXR_APP_ENV:-} DXR_WL_ORIGIN_STAMP=1" "$KIT/bin/app.sh" "$OUT/runtime-$TAG.log" 600 &
app=$!
sleep 12
for kind in $KINDS; do
    place Cube "$((ox + 60))" "$((oy + 120))"
    sleep 1.5
    press=$(winfield "w['frame'][0] + w['frame'][2] / 2, w['frame'][1] + (w['buffer'][1] - w['frame'][1]) / 2" Cube | tr -d '(),')
    py "$KIT/tools/dxr.py" signals 9 Cube > "$OUT/signals-$TAG-$kind.txt" &
    sig=$!
    sleep 0.7
    py "$KIT/bin/drag_driver.py" $kind $press "$OUT/marks-$TAG.txt"
    sleep 2.5
    capture "$OUT/rest-$TAG-$kind.png" > /dev/null
    snapshot > "$OUT/rest-$TAG-$kind.json"
    echo "$kind $(now_us)" >> "$OUT/rests-$TAG.txt"
    wait $sig || true
done
kill -INT "$(winfield "w['pid']" Cube 2>/dev/null || echo 0)" 2>/dev/null || true
wait $app || true
py "$KIT/tests/handdrag_check.py" "$OUT" "$TAG" | tee -a "$OUT/handdrag.md"
