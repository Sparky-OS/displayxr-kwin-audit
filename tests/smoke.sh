#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# smoke.sh [OUTDIR]: is the audit possible here? The publisher's bus name and its owner, the capability
# bits, KWin's outputs (the audited one first), one capture of the audited output (its device size), and
# one kit client on it: its published monitor (x, y, w, h, scale, device_scale) and buffer_device, and
# the painted rect in the capture. Expected: the owner present, capabilities 27 (bits 0, 1, 3, 4), the
# capture at the output's device size, the client's buffer_device equal to the painted rect.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_tools solid-window
OUT=${1:-$AUDIT_OUT/smoke}
mkdir -p "$OUT"
export AUDIT_OUT=$OUT
{
    echo "owner of org.displayxr.WindowGeometry: $(py "$KIT/tools/dxr.py" owner)"
    echo "GetPlacementCapabilities: $(py "$KIT/tools/dxr.py" caps)"
    echo "outputs (name x y w h scale):"
    py "$KIT/tools/outputs.py" | sed 's/^/  /'
    info=$(output_info | head -1)
    name=$(echo "$info" | awk '{print $1}'); ox=$(echo "$info" | awk '{print $2}'); oy=$(echo "$info" | awk '{print $3}')
    echo "audited output: $name (logical origin $ox,$oy)"
    pid=$("$KIT/bin/client.sh" smoke CLIENT_COLOR=ff0000)
    place smoke $((ox + 100)) $((oy + 100))
    sleep 0.5
    echo "capture: $(capture "$OUT/smoke.png")"
    snapshot > "$OUT/smoke.json"
    py -c "
import json, sys
w = [w for w in json.load(open(sys.argv[1]))['windows'] if w['title'] == 'smoke'][0]
print('client: pid', w['pid'], 'frame', w['frame'], 'buffer', w['buffer'])
print('        monitor', w['monitor'])
print('        buffer_device', w['buffer_device'], 'move_sync', w['move_sync'], 'moving', w['moving'])
" "$OUT/smoke.json"
    echo "painted: $(py "$KIT/tools/rect.py" "$OUT/smoke.png" ff0000)"
    kill "$pid" 2>/dev/null || true
    [ -n "${DXR_APP:-}" ] && echo "DXR_APP: $DXR_APP" || echo "DXR_APP not set: placement runs without the cube, dropsnap, movesync and handdrag need it"
    [ -x "$AUDIT_BIN/consumer-convert" ] && echo "consumer-convert: built (the runtime's own conversion)" || echo "consumer-convert: not built (tools/convert.py's rule is used)"
} | tee "$OUT/smoke.txt"
