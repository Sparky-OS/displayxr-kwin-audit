#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# stop-kwin-virtual.sh [LOG]: stops the session start-kwin-virtual.sh started (KWin, WirePlumber,
# PipeWire, the bus), by the pids it wrote; copies KWin's log to LOG when given.
set -u
. "$(dirname "$0")/../lib/common.sh"
R=${XDG_RUNTIME_DIR:-}
[ -n "$R" ] || exit 0
[ -n "${1:-}" ] && [ -f "$AUDIT_OUT/kwin.log" ] && cp "$AUDIT_OUT/kwin.log" "$1"
for p in kwin wireplumber pipewire dbus; do
    f=$R/audit-$p.pid
    if [ -f "$f" ]; then
        pid=$(cat "$f")
        kill "$pid" 2>/dev/null || true
        for i in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$f"
    fi
done
rm -f "$R/audit-bus" "$R/wayland-audit" "$R/wayland-audit.lock" "$R/audit-env" "$R"/*.fifo
exit 0
