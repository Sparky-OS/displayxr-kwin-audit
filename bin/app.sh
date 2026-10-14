#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# app.sh LOG [SECONDS] [ARGS...]: runs DisplayXR's cube_handle_vk_linux ($DXR_APP) against the audited KWin
# as a native Wayland window (--platform=wayland --windowed) for SECONDS (default 12), then stops it with
# SIGINT; its output at XRT_LOG=info goes to LOG, so the window-geometry consumer's lines are in it.
# With AUDIT_SIM=1 (the default) the app runs on the sim_display plug-in only, interlaced at period 5,
# with the audited output's device size as the panel, and a 1600x1000 device px window (DXR_CUBE_WINDOW):
# the configuration of the headless runs on DisplayXR/displayxr-runtime#1928. With AUDIT_SIM=0 nothing is
# set, so the runtime drives the real display. DXR_APP_ENV adds VAR=VALUE words either way; the kit's
# tests add DXR_WL_ORIGIN_STAMP=1 and what each needs. The app's pid is in the published snapshot.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_app
LOG=$1; T=${2:-12}; shift; [ $# -gt 0 ] && shift
mkdir -p "$(dirname "$LOG")"
SIM=
if [ "$AUDIT_SIM" = 1 ]; then
    info=$(output_info | head -1)
    scale=$(echo "$info" | awk '{print $6}')
    dw=$(py -c "import sys; print(round(int(sys.argv[1]) * float(sys.argv[2])))" "$(echo "$info" | awk '{print $4}')" "$scale")
    dh=$(py -c "import sys; print(round(int(sys.argv[1]) * float(sys.argv[2])))" "$(echo "$info" | awk '{print $5}')" "$scale")
    SIM="DXR_PLUGIN_EXCLUSIVE=sim-display SIM_DISPLAY_OUTPUT=${SIM_DISPLAY_OUTPUT:-interlaced} SIM_DISPLAY_INTERLACE_PERIOD=${SIM_DISPLAY_INTERLACE_PERIOD:-5} SIM_DISPLAY_PIXEL_W=$dw SIM_DISPLAY_PIXEL_H=$dh DXR_CUBE_WINDOW=${DXR_CUBE_WINDOW:-1600x1000}"
fi
{
    echo "== app $DXR_APP"
    echo "== env XDG_CURRENT_DESKTOP=KDE XRT_LOG=info $SIM ${DXR_APP_ENV:-}"
} > "$LOG"
# shellcheck disable=SC2086
exec env XDG_CURRENT_DESKTOP=KDE XRT_LOG=info $SIM ${DXR_APP_ENV:-} timeout -s INT "$T" $DXR_APP --platform=wayland --windowed "$@" >> "$LOG" 2>&1
