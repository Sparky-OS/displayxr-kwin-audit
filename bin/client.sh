#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# client.sh NAME [VAR=VALUE...]: starts the kit's test client solid-window with title NAME in the background,
# with a command FIFO ($XDG_RUNTIME_DIR/NAME.fifo, see cmd.sh) and its log in $AUDIT_OUT/client-NAME.log;
# prints its pid once its first buffer is attached. Variables: CLIENT_COLOR=RRGGBB, CLIENT_GEOMETRY_TOP=N
# (the window geometry N logical px below the surface's top, as a client-decorated window has it),
# CLIENT_PATTERN=columns, CLIENT_MOVE_BUTTON=right, HOLD_SECONDS=N.
set -eu
. "$(dirname "$0")/../lib/common.sh"
need_session
need_tools solid-window
NAME=$1; shift
mkdir -p "$AUDIT_OUT"
log=$AUDIT_OUT/client-$NAME.log
: > "$log"
fifo=$XDG_RUNTIME_DIR/$NAME.fifo
rm -f "$fifo"
mkfifo -m 600 "$fifo"
env CLIENT_FIFO="$fifo" CLIENT_TITLE="$NAME" "$@" "$AUDIT_BIN/solid-window" > "$log" 2>&1 &
for i in $(seq 50); do
    pid=$(sed -n 's/^pid //p' "$log")
    [ -n "$pid" ] && grep -q '^buffer' "$log" && break
    sleep 0.1
done
[ -n "${pid:-}" ] || die "solid-window $NAME did not start: $(cat "$log")"
sleep 0.5
echo "$pid"
