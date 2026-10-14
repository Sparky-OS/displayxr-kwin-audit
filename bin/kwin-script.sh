#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# kwin-script.sh JS: runs JS as a KWin script (org.kde.kwin.Scripting loadScript, start, unloadScript) from
# a file in AUDIT_SCRIPT_DIR, which KWin must be able to read at the same path (in a chroot, a directory
# bind-mounted into it, such as the runtime directory). print() lines go to KWin's own log.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
[ -n "$AUDIT_SCRIPT_DIR" ] || die "AUDIT_SCRIPT_DIR (or XDG_RUNTIME_DIR) is not set"
n=audit$$
f=$AUDIT_SCRIPT_DIR/$n.js
printf '%s\n' "$1" > "$f"
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:"$f" string:"$n" > /dev/null
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.start > /dev/null
sleep 0.3
dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript string:"$n" > /dev/null
rm -f "$f"
