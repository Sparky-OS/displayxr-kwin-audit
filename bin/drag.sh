#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# drag.sh X0 Y0 X1 Y1 [STEPS] [HOLD_MS]: one injected left-button drag through KWin's fake input (logical
# px, KWin's global layout): press at X0,Y0, STEPS moves (default 20, 16 ms apart) to X1,Y1, hold HOLD_MS
# (default 0), release. One fake-click follow session, so the pointer device stays for the whole drag. A
# press on the kit's solid-window starts xdg_toplevel.move, so KWin's own interactive move does the rest.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_tools fake-click
X0=$1 Y0=$2 X1=$3 Y1=$4 N=${5:-20} HOLD=${6:-0}
awk -v x0="$X0" -v y0="$Y0" -v x1="$X1" -v y1="$Y1" -v n="$N" -v hold="$HOLD" 'BEGIN {
    printf "%s %s\nsleep 100\ndown\nsleep 100\n", x0, y0
    for (i = 1; i <= n; i++)
        printf "%.4f %.4f\nsleep 16\n", x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
    if (hold > 0) printf "sleep %d\n", hold
    printf "up\nsleep 100\n"
}' | "$AUDIT_BIN/fake-click" follow > /dev/null
