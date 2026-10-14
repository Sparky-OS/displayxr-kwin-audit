#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# build.sh [OUTDIR]: builds the kit's C tools into OUTDIR (default <kit>/build): fake-click (KWin's fake
# input), solid-window (the test client), screencast-node (KWin's screen cast stream), and, when DXR_SRC
# names a displayxr-runtime checkout, consumer-convert (the runtime's own conversion of the integer wire).
# Needs: a C compiler, pkg-config, wayland-scanner (libwayland-bin), the Wayland and D-Bus development
# files (libwayland-dev, libdbus-1-dev), wayland-protocols and plasma-wayland-protocols (for xdg-shell,
# viewporter, fractional-scale, fake-input and screencast; FAKE_INPUT_XML and SCREENCAST_XML override the
# paths). On Debian: apt-get install gcc libc6-dev pkg-config libwayland-bin libwayland-dev libdbus-1-dev
# wayland-protocols plasma-wayland-protocols.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/../build}
mkdir -p "$out"
out=$(cd "$out" && pwd)
P=${WAYLAND_PROTOCOLS:-$(pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null || echo /usr/share/wayland-protocols)}
PLASMA=${PLASMA_WAYLAND_PROTOCOLS:-/usr/share/plasma-wayland-protocols}
FAKE_INPUT_XML=${FAKE_INPUT_XML:-$PLASMA/fake-input.xml}
SCREENCAST_XML=${SCREENCAST_XML:-$PLASMA/screencast.xml}
for f in "$P/stable/xdg-shell/xdg-shell.xml" "$P/stable/viewporter/viewporter.xml" "$P/staging/fractional-scale/fractional-scale-v1.xml" "$FAKE_INPUT_XML" "$SCREENCAST_XML"; do
    [ -f "$f" ] || { echo "build.sh: $f is missing (wayland-protocols, plasma-wayland-protocols)" >&2; exit 1; }
done
gen() { # XML NAME: the client header and the private code of a protocol
    wayland-scanner client-header "$1" "$out/$2-client-protocol.h"
    wayland-scanner private-code "$1" "$out/$2-protocol.c"
}
gen "$P/stable/xdg-shell/xdg-shell.xml" xdg-shell
gen "$P/stable/viewporter/viewporter.xml" viewporter
gen "$P/staging/fractional-scale/fractional-scale-v1.xml" fractional-scale-v1
gen "$FAKE_INPUT_XML" fake-input
gen "$SCREENCAST_XML" screencast
CC=${CC:-cc}
$CC -O1 -Wall -I"$out" -o "$out/fake-click" "$here/src/fake-click.c" "$out/fake-input-protocol.c" $(pkg-config --cflags --libs wayland-client)
$CC -O1 -Wall -I"$out" -o "$out/screencast-node" "$here/src/screencast-node.c" "$out/screencast-protocol.c" $(pkg-config --cflags --libs wayland-client)
$CC -O1 -Wall -I"$out" -o "$out/solid-window" "$here/src/solid-window.c" "$out/xdg-shell-protocol.c" "$out/viewporter-protocol.c" \
    "$out/fractional-scale-v1-protocol.c" $(pkg-config --cflags --libs wayland-client dbus-1) -lm
built="fake-click screencast-node solid-window"
if [ -n "${DXR_SRC:-}" ]; then
    [ -f "$DXR_SRC/src/xrt/auxiliary/util/u_wayland_geom.h" ] || { echo "build.sh: $DXR_SRC is not a displayxr-runtime checkout" >&2; exit 1; }
    $CC -O1 -Wall -I"$DXR_SRC/src/xrt/auxiliary" -I"$DXR_SRC/src/external/cjson" -o "$out/consumer-convert" \
        "$here/src/consumer-convert.c" "$DXR_SRC/src/external/cjson/cjson/cJSON.c" -lm
    built="$built consumer-convert"
else
    echo "build.sh: DXR_SRC not set, consumer-convert not built (the checks then use the rule in tools/convert.py)"
fi
rm -f "$out"/*-protocol.c "$out"/*-client-protocol.h
echo "built in $out: $built"
