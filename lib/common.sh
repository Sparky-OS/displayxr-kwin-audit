# SPDX-License-Identifier: BSL-1.0
# common.sh: sourced by every script of the kit. Reads the environment the kit works in, with
# defaults, and defines the helpers the scripts share. Every path comes from the environment: the kit
# has no idea where KWin, the session bus or the runtime live.
#
#   DBUS_SESSION_BUS_ADDRESS  the session bus KWin's publisher is on (required)
#   XDG_RUNTIME_DIR           where KWin's Wayland socket is (required)
#   WAYLAND_DISPLAY           KWin's socket name (default wayland-0)
#   AUDIT_OUTPUT              the output to audit, by KWin's name (HDMI-A-1, Virtual-1; default: the
#                             first output KWin lists)
#   AUDIT_OUT                 where results go (default ./out)
#   AUDIT_BIN                 where tools/build.sh put the C tools (default <kit>/build)
#   AUDIT_SCRIPT_DIR          a directory KWin can read at the same path, for KWin scripts (default
#                             $XDG_RUNTIME_DIR; in a chroot, a bind-mounted one)
#   AUDIT_PYTHON              the Python 3 with dbus, numpy, PIL and gi (default python3)
#   DXR_APP                   the command that runs cube_handle_vk_linux (its run_*.sh or the binary);
#                             the tests that need the runtime stop without it
#   DXR_APP_ENV               extra VAR=VALUE words for the app (default: none)
#   AUDIT_SIM                 1 (default): run the app on sim_display, interlaced, period 5, with the
#                             panel size of the audited output; 0: let the runtime pick its display
#   DXR_SRC                   a displayxr-runtime checkout, for consumer-convert (optional)
#   AUDIT_KWIN_LOG            KWin's log (its stderr, or a journal export), for the columns that read
#                             KWin's own debug lines (optional)
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
AUDIT_OUT=${AUDIT_OUT:-$PWD/out}
AUDIT_BIN=${AUDIT_BIN:-$KIT/build}
AUDIT_PYTHON=${AUDIT_PYTHON:-python3}
AUDIT_SCRIPT_DIR=${AUDIT_SCRIPT_DIR:-${XDG_RUNTIME_DIR:-}}
AUDIT_SIM=${AUDIT_SIM:-1}
WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
export WAYLAND_DISPLAY AUDIT_OUT AUDIT_BIN AUDIT_PYTHON AUDIT_SCRIPT_DIR

die() {
    echo "$(basename "$0"): $*" >&2
    exit 1
}

need_session() {
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || die "DBUS_SESSION_BUS_ADDRESS is not set: the session bus KWin's publisher is on"
    [ -n "${XDG_RUNTIME_DIR:-}" ] || die "XDG_RUNTIME_DIR is not set: where KWin's Wayland socket is"
    [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || die "no Wayland socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
}

need_tools() {
    for t in "$@"; do
        [ -x "$AUDIT_BIN/$t" ] || die "$AUDIT_BIN/$t is missing: run tools/build.sh $AUDIT_BIN"
    done
}

need_app() {
    [ -n "${DXR_APP:-}" ] || die "DXR_APP is not set: the command that runs cube_handle_vk_linux"
}

py() {
    "$AUDIT_PYTHON" -I "$@"
}

# The audited output: name, logical geometry and scale, from KWin's support information.
output_info() {
    py "$KIT/tools/outputs.py" ${AUDIT_OUTPUT:+"$AUDIT_OUTPUT"}
}

# GetWindows, as any client reads it.
snapshot() {
    py "$KIT/tools/dxr.py" windows
}

# One ScreenShot2 capture of the audited output, device pixels, no cursor.
capture() {
    py "$KIT/tools/capture.py" "$1" ${AUDIT_OUTPUT:+"$AUDIT_OUTPUT"}
}

# A field of the first window whose title starts with $2 (or whose app_id contains it), as a Python
# expression over w.
winfield() {
    snapshot | py -c "
import json, sys
title = sys.argv[1]
ws = [w for w in json.load(sys.stdin)['windows'] if w['title'].startswith(title) or title in w['app_id']]
if not ws:
    sys.exit(1)
w = ws[0]
print($1)
" "$2"
}

# Runs JS as a KWin script (org.kde.kwin.Scripting), from a file KWin can read.
kwin_script() {
    "$KIT/bin/kwin-script.sh" "$1"
}

# Puts the window whose caption starts with $1 at frame position $2,$3 (logical), as a KWin script.
place() {
    kwin_script "for (const w of workspace.windowList()) if (w.caption.startsWith('$1')) w.frameGeometry = {x: $2, y: $3, width: w.frameGeometry.width, height: w.frameGeometry.height};"
}

now_us() {
    py -c 'import time; print(int(time.monotonic() * 1e6))'
}

# A test needs the session to itself: a previous run's windows would be moved and measured too.
need_clean_session() {
    left=$(snapshot | py -c "
import json, sys
ws = [w['title'] for w in json.load(sys.stdin)['windows'] if w['app_id'] in ('dxr-rig-solid', 'com.displayxr.cube_handle_vk_linux')]
print(' '.join(repr(t) for t in ws))
")
    [ -z "$left" ] || die "windows of a previous run are still up ($left): stop them, or start a fresh KWin session"
}
