#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# movesync.sh OUTDIR TAG "KINDS": move sync (spec section 9), audited frame by frame from KWin's output
# screen cast. cube_handle_vk_linux with DXR_WL_ORIGIN_STAMP=1 and move sync on (the runtime's default).
# For each KIND (drag_driver.py's profiles): the window is put back at 60,120 from the output origin by a
# KWin script, a screen cast of a band of the output that holds the stamp's path starts, the drag runs from
# the middle of the title bar, and every frame the cast sends is checked by stampcast.py: is the stamp
# painted at the origin it encodes, the one its frame was woven for? KIND@right: the drag on the right
# button from the middle of the content; KIND@frozen: the app is stopped (SIGSTOP) for 670 ms 1.2 s into the
# drag (spec section 9.7). Recorded per kind: the per-frame lines (cast-TAG-KIND.txt) and their summary
# (casts-TAG.txt), the snapshot after the drop; movesync_report.py makes the table, with KWin's own
# columns when AUDIT_KWIN_LOG holds KWin's log with DISPLAYXR_DEBUG=1 and
# QT_LOGGING_RULES=kwin_displayxr.debug=true in KWin's environment. KWin and this script must reach the
# same PipeWire daemon. Results: OUTDIR/movesync.md.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_clean_session
need_tools fake-click screencast-node
need_app
OUT=$1 TAG=$2 KINDS=$3
mkdir -p "$OUT"
export AUDIT_OUT=$OUT
R=$XDG_RUNTIME_DIR
info=$(output_info | head -1)
ox=$(echo "$info" | awk '{print $2}'); oy=$(echo "$info" | awk '{print $3}')
lw=$(echo "$info" | awk '{print $4}'); lh=$(echo "$info" | awk '{print $5}'); scale=$(echo "$info" | awk '{print $6}')
DW=$(py -c "import sys; print(round(int(sys.argv[1]) * float(sys.argv[2])))" "$lw" "$scale")
DH=$(py -c "import sys; print(round(int(sys.argv[1]) * float(sys.argv[2])))" "$lh" "$scale")
: > "$OUT/marks-$TAG.txt"
: > "$OUT/drops-$TAG.txt"
: > "$OUT/casts-$TAG.txt"
DXR_APP_ENV="${DXR_APP_ENV:-} DXR_WL_ORIGIN_STAMP=1" "$KIT/bin/app.sh" "$OUT/runtime-$TAG.log" 600 &
app=$!
sleep 12
for kind in $KINDS; do
    place Cube "$((ox + 60))" "$((oy + 120))"
    sleep 0.8
    base=${kind%@*} variant=${kind#"$base"}
    if [ "$variant" = @right ]; then
        set -- $(winfield "w['buffer'][0] + w['buffer'][2] / 2, w['buffer'][1] + w['buffer'][3] / 2, w['buffer_device'][1], w['pid']" Cube | tr -d '(),')
    else
        set -- $(winfield "w['frame'][0] + w['frame'][2] / 2, w['frame'][1] + (w['buffer'][1] - w['frame'][1]) / 2, w['buffer_device'][1], w['pid']" Cube | tr -d '(),')
    fi
    px=$1 py_=$2 sy=$3 pid=$4
    # The band: from the output's left edge, up to 2560 px wide, from just above the stamp down past the
    # drag's path (a thin one for a straight drag, so the audit keeps up with the cast).
    top=$((sy - 24)) H=48
    W=$DW; [ "$W" -gt 2560 ] && W=2560
    case $base in *_d) H=320 ;; esac
    [ $((top + H)) -gt "$DH" ] && H=$((DH - top))
    (
        "$AUDIT_BIN/screencast-node" ${AUDIT_OUTPUT:-} > "$R/audit-cast-node.log" 2>&1 &
        echo $! > "$R/audit-cast-node.pid"
        for i in $(seq 50); do grep -q "^node" "$R/audit-cast-node.log" && break; sleep 0.1; done
        node=$(sed -n "s/^node //p" "$R/audit-cast-node.log")
        timeout -s INT 9 gst-launch-1.0 -q -e pipewiresrc path="$node" ! videocrop left=0 top="$top" right="$((DW - W))" bottom="$((DH - top - H))" \
            ! videoconvert ! video/x-raw,format=RGBx ! fdsink fd=1 2> "$R/audit-cast-gst.log" \
            | py "$KIT/tools/stampcast.py" "$W" "$H" 0 "$top" "$OUT/cast-$TAG-$kind.txt" "$DW" "$DH" > "$R/audit-cast-summary.txt"
        kill "$(cat "$R/audit-cast-node.pid")" 2>/dev/null || true
    ) &
    cast=$!
    sleep 2
    if [ "$variant" = @frozen ]; then
        py "$KIT/bin/drag_driver.py" $base $px $py_ "$OUT/marks-$TAG.txt" &
        drag=$!
        sleep 1.2
        kill -STOP "$pid"
        echo "$kind stopped t=$(now_us)" >> "$OUT/marks-$TAG.txt"
        sleep 0.67
        kill -CONT "$pid"
        wait $drag
    else
        py "$KIT/bin/drag_driver.py" $base $px $py_ "$OUT/marks-$TAG.txt" $([ "$variant" = @right ] && echo right)
    fi
    wait $cast || true
    echo "$kind $(cat "$R/audit-cast-summary.txt")" >> "$OUT/casts-$TAG.txt"
    echo "$kind $(winfield "w['frame'], 'buffer_device', w['buffer_device'], 'move_sync', w['move_sync'], 'moving', w['moving']" Cube)" >> "$OUT/drops-$TAG.txt"
done
kill -INT "$(winfield "w['pid']" Cube 2>/dev/null || echo 0)" 2>/dev/null || true
wait $app || true
py "$KIT/tests/movesync_report.py" "$OUT" "$TAG" --md | tee -a "$OUT/movesync.md"
