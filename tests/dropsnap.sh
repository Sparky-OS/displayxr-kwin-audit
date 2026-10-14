#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# dropsnap.sh OUTDIR TAG "KINDS": drop landings: the runtime's drop-time snap off the drag table (spec section
# 7.2). cube_handle_vk_linux with DXR_WL_ORIGIN_STAMP=1 and move sync and the drag table off
# (DXR_WL_MOVE_SYNC=0, DXR_WL_DRAG_LATTICE=0), so KWin's plain drag drops the window anywhere and the runtime
# then moves it with MoveWindow onto a phase-correct position. Per KIND (drag_driver.py's profiles): the
# window is put back at 60 + i, 120 from the output origin (i the kind's index, so drops land on and off the
# display's lattice), dragged from the middle of its title bar, and 2.5 s after the drop the output is
# captured (the stamp's painted position against the origin it encodes) and the snapshot read
# (buffer_device). The runtime's own "phase snap" lines are in its log. dropsnap_check.py compares.
# Results: OUTDIR/dropsnap.md.
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
: > "$OUT/drops-$TAG.txt"
DXR_APP_ENV="${DXR_APP_ENV:-} DXR_WL_ORIGIN_STAMP=1 DXR_WL_MOVE_SYNC=0 DXR_WL_DRAG_LATTICE=0" "$KIT/bin/app.sh" "$OUT/runtime-$TAG.log" 600 &
app=$!
sleep 12
i=0
for kind in $KINDS; do
    place Cube "$((ox + 60 + i))" "$((oy + 120))"
    i=$((i + 1))
    sleep 2.5
    press=$(winfield "w['frame'][0] + w['frame'][2] / 2, w['frame'][1] + (w['buffer'][1] - w['frame'][1]) / 2" Cube | tr -d '(),')
    py "$KIT/bin/drag_driver.py" $kind $press "$OUT/marks-$TAG.txt"
    sleep 2.5
    capture "$OUT/drop-$TAG-$kind.png" > /dev/null
    snapshot > "$OUT/drop-$TAG-$kind.json"
    echo "$kind" >> "$OUT/drops-$TAG.txt"
done
kill -INT "$(winfield "w['pid']" Cube 2>/dev/null || echo 0)" 2>/dev/null || true
wait $app || true
py "$KIT/tests/dropsnap_check.py" "$OUT" "$TAG" | tee -a "$OUT/dropsnap.md"
