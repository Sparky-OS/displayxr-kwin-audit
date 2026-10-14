#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# movewindow.sh OUTDIR [TAG]: MoveWindow lands the buffer on round((buffer + move - monitor) * scale) (spec
# section 7.1 as DisplayXR/displayxr-runtime#1985 words it). The kit client "mw" (red, its window geometry
# 10 logical px below its surface's top, so its surface sits at an offset inside the frame as a
# client-decorated window's does) starts at a fractional frame position and asks MoveWindow, from its own
# process, for eight whole frame positions. Before each: the snapshot (published frame and buffer); after:
# the capture (the red surface's top-left) and the snapshot again. movewindow_check.py compares. Results:
# OUTDIR/movewindow.md. MoveWindow acts only on the calling process's own windows (the process is taken
# from the bus connection), which is why the client asks for itself.
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
"$KIT/bin/client.sh" mw CLIENT_COLOR=ff0000 CLIENT_GEOMETRY_TOP=10 > /dev/null
place mw "$ox + 200.4" "$oy + 201.6"
sleep 0.6
: > "$OUT/moves-$t.txt"
k=0
for p in "300 250" "301 251" "302 253" "417 333" "418 334" "519 287" "520 288" "613 401"; do
    set -- $p
    snapshot > "$OUT/before-$t-$k.json"
    reply=$("$KIT/bin/cmd.sh" mw "move $((ox + $1)) $((oy + $2))")
    sleep 0.6
    capture "$OUT/after-$t-$k.png" > /dev/null
    snapshot > "$OUT/after-$t-$k.json"
    echo "$k $((ox + $1)) $((oy + $2)) $reply" >> "$OUT/moves-$t.txt"
    k=$((k + 1))
done
kill "$(sed -n 's/^pid //p' "$OUT/client-mw.log")" 2>/dev/null || true
py "$KIT/tests/movewindow_check.py" "$OUT" "$t" | tee -a "$OUT/movewindow.md"
find "$OUT" -name "after-$t-*.png" ! -name "after-$t-1.png" -delete
