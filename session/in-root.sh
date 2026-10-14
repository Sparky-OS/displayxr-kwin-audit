#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# in-root.sh CMD...: runs CMD inside the root file system $KWIN_ROOT under bubblewrap, with the current
# environment (the session's bus and Wayland socket), the runtime directory, the results directory and
# the kit shared, the render node KWIN_GPU when set, and the root's own /etc. The root is mounted as the
# lower layer of a tmpfs overlay, so it can be read-only and nothing written inside survives the command
# (bubblewrap 0.10 or newer, with unprivileged overlay mounts, Linux 5.11 or newer). Unprivileged:
# bubblewrap needs user namespaces (inside Docker: --security-opt seccomp=unconfined --security-opt
# apparmor=unconfined). KWIN_PLUGIN_OVERRIDE=FILE puts a displayxr.so built elsewhere over the root's
# (the publisher's module, for a fix under test).
set -eu
. "$(dirname "$0")/../lib/common.sh"
[ -n "${KWIN_ROOT:-}" ] || die "KWIN_ROOT is not set"
[ -x "$KWIN_ROOT/usr/bin/kwin_wayland" ] || die "$KWIN_ROOT has no usr/bin/kwin_wayland"
DRI=
[ -n "${KWIN_GPU:-}" ] && [ "$KWIN_GPU" != none ] && DRI="--dev-bind $KWIN_GPU $KWIN_GPU"
PLUGIN=
if [ -n "${KWIN_PLUGIN_OVERRIDE:-}" ]; then
    [ -f "$KWIN_PLUGIN_OVERRIDE" ] || die "$KWIN_PLUGIN_OVERRIDE is missing"
    PLUGIN="--ro-bind $KWIN_PLUGIN_OVERRIDE /usr/lib/x86_64-linux-gnu/qt6/plugins/kwin/plugins/displayxr.so"
fi
mkdir -p "$AUDIT_OUT"
# shellcheck disable=SC2086
exec bwrap --overlay-src "$KWIN_ROOT" --tmp-overlay / --dev /dev $DRI $PLUGIN --ro-bind /sys /sys --proc /proc --tmpfs /tmp \
    --bind "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR" --bind "$AUDIT_OUT" "$AUDIT_OUT" --ro-bind "$KIT" "$KIT" \
    --setenv HOME "${HOME:-$XDG_RUNTIME_DIR/audit-home}" --chdir / "$@"
