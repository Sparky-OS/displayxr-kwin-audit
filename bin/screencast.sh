#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# screencast.sh OUT.png: one frame of KWin's zkde_screencast stream of the audited output, read through
# PipeWire with GStreamer's pipewiresrc (the first frame of a new stream, rendered from the current
# scene; KWin sends further frames only on damage). KWin and this script must reach the same PipeWire
# daemon (the same XDG_RUNTIME_DIR, or PIPEWIRE_REMOTE).
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_tools screencast-node
R=$XDG_RUNTIME_DIR
rm -f "$R"/audit-sc-*.png
"$AUDIT_BIN/screencast-node" ${AUDIT_OUTPUT:-} > "$R/audit-sc-node.log" 2>&1 &
sc=$!
for i in $(seq 50); do grep -q "^node" "$R/audit-sc-node.log" && break; sleep 0.1; done
node=$(sed -n "s/^node //p" "$R/audit-sc-node.log")
[ -n "$node" ] || { cat "$R/audit-sc-node.log"; kill $sc; exit 1; }
timeout 20 gst-launch-1.0 -q pipewiresrc path="$node" num-buffers=1 ! videoconvert ! pngenc ! multifilesink location="$R/audit-sc-%02d.png" > "$R/audit-sc-gst.log" 2>&1 || { cat "$R/audit-sc-gst.log"; kill $sc; exit 1; }
kill $sc
cp "$(ls "$R"/audit-sc-*.png | tail -1)" "$1"
echo "node $node frames $(ls "$R"/audit-sc-*.png | wc -l)"
