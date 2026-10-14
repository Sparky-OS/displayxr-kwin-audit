#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# start-kwin-virtual.sh SCALE [DEVICE_W DEVICE_H]: a headless Stereo KWin on its virtual backend, for a bench
# without a panel: a private session bus, PipeWire and WirePlumber (for the screen cast), then kwin_wayland
# with one output of DEVICE_W x DEVICE_H device pixels (default 3840x2160) at SCALE, started so that the
# audit's clients are allowed (KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1, KWIN_WAYLAND_NO_PERMISSION_CHECKS=1).
# Writes $XDG_RUNTIME_DIR/audit-env, the exports every other script of the kit needs; source it.
#   KWIN_WAYLAND   the kwin_wayland binary (default: kwin_wayland on PATH), or
#   KWIN_ROOT      a root file system to run KWin from, under bubblewrap (the Sparky Stereo OS bench root)
#   KWIN_GPU       a render node for KWin (/dev/dri/renderD128), or none (default: Mesa's software renderer)
#   KWIN_ENV       extra VAR=VALUE words for KWin (DISPLAYXR_DEBUG=1 QT_LOGGING_RULES=kwin_displayxr.debug=true)
#   KWIN_ARGS      extra arguments for kwin_wayland
#   KWINRC         lines for a fresh kwinrc ("[Plugins]\ndisplayxrEnabled=false" for the plugin-off control)
#   AUDIT_PIPEWIRE 1 (default) starts pipewire and wireplumber in the session; 0 does not
#   AUDIT_OUT      where KWin's log goes ($AUDIT_OUT/kwin.log; AUDIT_KWIN_LOG then points at it)
# The configuration directory is fresh for every session: KWin stores output settings there and would
# otherwise restore the last session's scale. kwin_wayland --scale sizes the mode; the output's scale is
# then set the way a user sets it, through KScreen's output management (kscreen-doctor, from the root when
# KWIN_ROOT is set; KWin rounds it to 1/120, so 1.6667 is exactly 5/3).
set -eu
. "$(dirname "$0")/../lib/common.sh"
SCALE=$1 DW=${2:-3840} DH=${3:-2160}
[ -n "${XDG_RUNTIME_DIR:-}" ] || die "XDG_RUNTIME_DIR is not set"
R=$XDG_RUNTIME_DIR
mkdir -p "$AUDIT_OUT"
"$KIT/session/stop-kwin-virtual.sh" 2>/dev/null || true
W=$(py -c "import sys; print(round(int(sys.argv[1]) / float(sys.argv[2])))" "$DW" "$SCALE")
H=$(py -c "import sys; print(round(int(sys.argv[1]) / float(sys.argv[2])))" "$DH" "$SCALE")
rm -rf "$R/audit-config" "$R/audit-home"
mkdir -p "$R/audit-config" "$R/audit-home"
[ -n "${KWINRC:-}" ] && printf "$KWINRC\n" > "$R/audit-config/kwinrc"

dbus-daemon --session --address="unix:path=$R/audit-bus" --nofork --nopidfile --syslog-only &
echo $! > "$R/audit-dbus.pid"
for i in $(seq 50); do [ -S "$R/audit-bus" ] && break; sleep 0.1; done
export DBUS_SESSION_BUS_ADDRESS="unix:path=$R/audit-bus"
export WAYLAND_DISPLAY=wayland-audit
SW=
[ "${KWIN_GPU:-none}" = none ] && SW="LIBGL_ALWAYS_SOFTWARE=1"
cat > "$R/audit-env" <<ENV
export XDG_RUNTIME_DIR=$R
export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
export WAYLAND_DISPLAY=$WAYLAND_DISPLAY
export QT_QPA_PLATFORM=wayland
export AUDIT_OUT=$AUDIT_OUT
export AUDIT_KWIN_LOG=$AUDIT_OUT/kwin.log
export AUDIT_SCALE=$SCALE AUDIT_DEVICE_W=$DW AUDIT_DEVICE_H=$DH
${KWIN_ROOT:+export KWIN_ROOT=$KWIN_ROOT}
${SW:+export $SW}
ENV
. "$R/audit-env"
if [ "${AUDIT_PIPEWIRE:-1}" = 1 ]; then
    pipewire > "$AUDIT_OUT/pipewire.log" 2>&1 &
    echo $! > "$R/audit-pipewire.pid"
    for i in $(seq 50); do [ -S "$R/pipewire-0" ] && break; sleep 0.1; done
    wireplumber > "$AUDIT_OUT/wireplumber.log" 2>&1 &
    echo $! > "$R/audit-wireplumber.pid"
fi
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 XDG_CONFIG_HOME="$R/audit-config" HOME="$R/audit-home"
# shellcheck disable=SC2086
[ -n "${KWIN_ENV:-}" ] && export ${KWIN_ENV}
ARGS="--virtual --width $W --height $H --scale $SCALE --socket $WAYLAND_DISPLAY --no-lockscreen --no-global-shortcuts --no-kactivities ${KWIN_ARGS:-}"
if [ -n "${KWIN_ROOT:-}" ]; then
    # shellcheck disable=SC2086
    "$KIT/session/in-root.sh" /usr/bin/kwin_wayland $ARGS > "$AUDIT_OUT/kwin.log" 2>&1 &
else
    # shellcheck disable=SC2086
    "${KWIN_WAYLAND:-kwin_wayland}" $ARGS > "$AUDIT_OUT/kwin.log" 2>&1 &
fi
echo $! > "$R/audit-kwin.pid"
up=
for i in $(seq 100); do
    if [ -S "$R/$WAYLAND_DISPLAY" ] && dbus-send --session --print-reply --dest=org.kde.KWin /KWin org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
        up=1; break
    fi
    kill -0 "$(cat "$R/audit-kwin.pid")" 2>/dev/null || { echo "KWin exited:"; tail -30 "$AUDIT_OUT/kwin.log"; exit 1; }
    sleep 0.3
done
[ -n "$up" ] || { echo "KWin's D-Bus name did not appear:"; tail -30 "$AUDIT_OUT/kwin.log"; exit 1; }
name=$(output_info | head -1 | awk '{print $1}')
if [ "$SCALE" != 1 ]; then
    if [ -n "${KWIN_ROOT:-}" ]; then
        "$KIT/session/in-root.sh" kscreen-doctor "output.$name.scale.$SCALE" > /dev/null 2>&1 || echo "kscreen-doctor failed in the root" >&2
    else
        "${KSCREEN_DOCTOR:-kscreen-doctor}" "output.$name.scale.$SCALE" > /dev/null 2>&1 || echo "kscreen-doctor failed" >&2
    fi
    sleep 1
fi
echo "export AUDIT_OUTPUT=$name" >> "$R/audit-env"
echo "session: . $R/audit-env"
output_info
