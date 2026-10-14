#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# placement.sh OUTDIR [TAG]: placement against buffer_device. Is buffer_device the rect KWin paints the main
# surface at? Two kit clients: "bd" (red) with its window geometry 10 logical px below its surface's top,
# so its surface sits at an offset inside the frame as a client-decorated window's does, and "bn" (blue)
# without; and, when DXR_APP is set, cube_handle_vk_linux with its own title bar and DXR_WL_ORIGIN_STAMP=1.
# Each window is put by a KWin script at six frame positions, whole and fractional, relative to the audited
# output; at each, the snapshot is read and the output captured. placement_check.py compares, per window
# and position: buffer_device, the painted rect (the colour's bounding box; the cube's top-left from its
# origin stamp), the old conversion of buffer, and whether buffer_device equals the paint. TAG names the
# run (default: the output's scale). Results: OUTDIR/placement.md, the captures of position 1, the snapshots.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_clean_session
need_tools solid-window
OUT=$1
mkdir -p "$OUT"
export AUDIT_OUT=$OUT
info=$(output_info | head -1)
ox=$(echo "$info" | awk '{print $2}'); oy=$(echo "$info" | awk '{print $3}'); scale=$(echo "$info" | awk '{print $6}')
t=${2:-$scale}
"$KIT/bin/client.sh" bd CLIENT_COLOR=ff0000 CLIENT_GEOMETRY_TOP=10 > /dev/null
"$KIT/bin/client.sh" bn CLIENT_COLOR=0000ff > /dev/null
app=
if [ -n "${DXR_APP:-}" ]; then
    DXR_APP_ENV="${DXR_APP_ENV:-} DXR_WL_ORIGIN_STAMP=1" "$KIT/bin/app.sh" "$OUT/runtime-$t.log" 120 &
    app=$!
    sleep 12
fi
: > "$OUT/positions-$t.txt"
k=0
for p in "200 200" "200.4 201.6" "333.7 250.25" "517.123 300.9" "401.5 333.5" "250.6 120.3"; do
    set -- $p
    kwin_script "for (const w of workspace.windowList()) {
        if (w.caption == 'bd') w.frameGeometry = {x: $ox + $1, y: $oy + $2, width: w.frameGeometry.width, height: w.frameGeometry.height};
        if (w.caption == 'bn') w.frameGeometry = {x: $ox + $1 + 700, y: $oy + $2, width: w.frameGeometry.width, height: w.frameGeometry.height};
        if (w.caption.startsWith('Cube')) w.frameGeometry = {x: $ox + $1, y: $oy + $2 + 500, width: w.frameGeometry.width, height: w.frameGeometry.height};
    }"
    sleep 1
    snapshot > "$OUT/snap-$t-$k.json"
    capture "$OUT/cap-$t-$k.png" > /dev/null
    echo "$k $1 $2" >> "$OUT/positions-$t.txt"
    k=$((k + 1))
done
for n in bd bn; do kill "$(sed -n 's/^pid //p' "$OUT/client-$n.log")" 2>/dev/null || true; done
if [ -n "$app" ]; then
    kill -INT "$(winfield "w['pid']" Cube 2>/dev/null || echo 0)" 2>/dev/null || true
    wait $app || true
fi
py "$KIT/tests/placement_check.py" "$OUT" "$t" | tee -a "$OUT/placement.md"
find "$OUT" -name "cap-$t-*.png" ! -name "cap-$t-1.png" -delete
