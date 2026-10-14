#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# cmd.sh NAME COMMAND: sends COMMAND to the client NAME (client.sh) through its FIFO and prints the reply
# lines it writes. Commands: "move X Y" and "movepid PID X Y" (MoveWindow), "exclude PID", "release PID",
# "caps", "lattice", "sync PID", "table explicit|implicit X Y", "newwindow", "fullscreen", "unfullscreen",
# "disconnect" (see tools/src/solid-window.c).
set -eu
. "$(dirname "$0")/../lib/common.sh"
NAME=$1 CMD=$2
log=$AUDIT_OUT/client-$NAME.log
[ -f "$log" ] || die "no client $NAME (no $log)"
before=$(grep -c '^reply' "$log" || true)
printf '%s\n' "$CMD" > "$XDG_RUNTIME_DIR/$NAME.fifo"
for i in $(seq 50); do
    [ "$(grep -c '^reply' "$log" || true)" -gt "$before" ] && break
    sleep 0.1
done
sleep 0.2
grep '^reply' "$log" | tail -n +$((before + 1))
