# displayxr-kwin-audit

The audit kit behind the KWin tables on [DisplayXR/displayxr-runtime#1928](https://github.com/DisplayXR/displayxr-runtime/issues/1928): how Sparky Stereo OS measured its KWin publisher of `org.displayxr.WindowGeometry1` against where KWin paints, so the same numbers can be taken on a real panel, in the same columns.
It works from KWin alone: the bus, KWin's own screenshots and screen cast, KWin's fake input and KWin scripts.
Nothing in it reads the GNOME extension's log, and nothing in it is tied to our machines: every path comes from the environment.

Licence: BSL-1.0, the same as DisplayXR, so it can be taken in there.

## What it measures

Each test writes one Markdown table, in the columns of the issue.

| Test | The question | How it is read |
|---|---|---|
| `tests/smoke.sh` | Is the audit possible here? | The publisher's bus name and owner, the capability bits (27: bits 0, 1, 3 and 4), KWin's outputs, one capture at device size, one kit window with `buffer_device` against its painted rect. |
| `tests/placement.sh` | Placement against `buffer_device`: is `buffer_device` the rect KWin paints the main surface at? | Two kit windows, one with its surface 10 logical px inside its frame as a client-decorated window has it, and `cube_handle_vk_linux` with its own title bar, each put by a KWin script at six frame positions, whole and fractional. Per window and position: `buffer_device` from `GetWindows`, the painted rect from a ScreenShot2 capture (the colour's bounding box; the cube's top-left from its origin stamp), and the old conversion `round((buffer - monitor) * device_scale)`. Last line: captures, `buffer_device = painted`, `old conversion = painted`. |
| `tests/movewindow.sh` | Does `MoveWindow` land the buffer on `round((buffer + move - monitor) * scale)` (spec 7.1)? | A kit window at a fractional start asks `MoveWindow` for eight whole frame positions from its own process; per call: the pixel the runtime expects, the painted top-left, the published buffer converted, `buffer_device`. |
| `tests/dropsnap.sh` | Drop landings: after a plain drag, does the runtime's drop snap (spec 7.2) land where it asked, and does `buffer_device` name it? | The cube with move sync and the drag table off; per drag profile: the runtime's `phase snap` lines, the stamp's painted position against the origin it encodes, `buffer_device`. |
| `tests/movesync.sh` | Move sync (spec 9): is every frame painted where it was woven for? | The cube with move sync on; per drag profile, every frame of KWin's screen cast of the output, read through PipeWire: the origin stamp's painted position against the origin it encodes; plus KWin's own counts when its log is given. |
| `tests/handdrag.sh` | The rest case: after a hand drag in sub-logical-pixel steps and a pause, do `GetWindows`, the last `WindowsChanged`, the paint and the weave name the same pixel? | Drag profiles ending on chosen frame fractions; per drag: `buffer_device` from `GetWindows` at rest, the last signal's `buffer_device` and when it was sent, the stamp's position and encoding. |

### How each value is read

- **The paint** is a KWin ScreenShot2 `CaptureScreen` of the output at native resolution (`tools/capture.py`): device pixels, as KWin composed them, no cursor. KWin renders a screenshot with the same item renderer at the output's scale, so it shows where each item is painted.
- **The origin stamp** is DisplayXR's `DXR_WL_ORIGIN_STAMP=1`: 44 blocks of 8x8 device px at the top-left of the woven surface, white for 1, a `1010` marker, then x + 32768 and y + 32768 in 16 bits each, then an 8-bit counter (`comp_vk_native_compositor.c`, `vk_debug_origin_stamp`). `tools/stamp.py` finds it in a capture and prints where it is painted and the origin it encodes, the present origin the runtime wove that frame for. Equal means the frame was woven for the pixel it reached.
- **The old conversion** is what a consumer without `buffer_device` does: `round((buffer - monitor) * device_scale)`, half away from zero (`u_wayland_geom.h`, `u_wl_logical_to_px`). `tools/build.sh` builds `consumer-convert` from the runtime's own header when `DXR_SRC` names a checkout; the checks prefer it and say which one they used.
- **The screen cast** is KWin's `zkde_screencast_unstable_v1` stream of the output through PipeWire, read by GStreamer's `pipewiresrc` and `tools/stampcast.py`, one stamp reading per frame, with the time the frame arrived (`CLOCK_MONOTONIC`, the clock of KWin's debug lines).
- **Drags** go through KWin's fake input protocol (`tools/src/fake-click.c`, one session per drag so the pointer device stays), with DisplayXR's own drag profiles (`bin/drag_driver.py`, the motion of `scripts/linux/move_sync/driver.py`), pressed on the middle of the window's title bar.
- **Placement** of a window at a fractional frame position is a KWin script (`workspace.windowList()`, `frameGeometry`), which keeps the fraction as a pointer move would.
- **`MoveWindow`** acts only on the calling process's own windows; the process is taken from the bus connection, and the `pid` argument must name it or be 0. A call from another process returns false. That is why the kit's client asks for itself.

## Running it

Needs: a C compiler, `pkg-config`, `wayland-scanner`, the Wayland and D-Bus development files, `wayland-protocols` and `plasma-wayland-protocols`; Python 3 with `dbus`, `numpy`, `PIL` and `gi`; `dbus-send`; for the move-sync test, GStreamer with `pipewiresrc`, `videocrop` and `pngenc`.
On Debian: `apt-get install gcc libc6-dev pkg-config libwayland-bin libwayland-dev libdbus-1-dev wayland-protocols plasma-wayland-protocols python3-dbus python3-numpy python3-pil python3-gi gstreamer1.0-pipewire gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good`.
The Sparky Stereo OS bench root carries all of it, with the kit at `/opt/displayxr-kwin-audit` and its tools built.

1. Build the tools: `tools/build.sh` (`DXR_SRC=/path/to/displayxr-runtime` adds `consumer-convert`).
2. Start KWin so the kit's clients are allowed: `KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1` and `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` in its environment. [docs/chroot.md](docs/chroot.md) has the chroot and logind setup, and `session/start-kwin-virtual.sh SCALE` starts a headless one on KWin's virtual backend for a bench without a panel (from a binary, or from the bench root under bubblewrap with `KWIN_ROOT`).
3. Set the environment: copy `env.example`, fill in the bus, the runtime directory, the output's name, the app, and source it.
4. `tests/smoke.sh`, then the tests you want, each in a fresh KWin session (a previous run's windows would be moved and measured too; the tests refuse to start over them).

Each test takes `OUTDIR` and writes its table there (`placement.md`, `movewindow.md`, `dropsnap.md`, `movesync.md`, `handdrag.md`), next to the captures and snapshots it read.
The scale is read from the publisher's snapshot: set the output's scale as a user would (`kscreen-doctor output.NAME.scale.2`) before a run.

## The columns on #1928

`tests/placement.sh`'s last lines are the row of the `buffer_device` table there (captures, `buffer_device = painted`, `old conversion = painted`).
`tests/movesync.sh`'s table is the move-sync table there (cast frames, stamp where woven, stamp elsewhere; timeouts and re-syncs from KWin's log).
`tests/dropsnap.sh`'s table is the drop table (drops painted where woven, `buffer_device` naming the pixel).
`tests/handdrag.sh` is the rest case found on the Samsung Odyssey 3D on 2026-10-14.

## Where it comes from

The kit is the test rig of Sparky Stereo OS's DisplayXR lane, made portable.
Daniel Ramos directed the work; the rig and its measurements (M0 to M4, 2026-10-11 and 2026-10-12) were written by Claude Opus via Claude Code in that lane, and this kit by Claude Fable 5.1 via Claude Code on 2026-10-14, both reviewed by the main session and by Daniel.
`solid-window.c` is adapted from the `vkms-stereo-bench`'s `fullscreen-2d.c`; `fake-click.c` from the stereo-vm lane's injector; the capture follows the qt-stereo lane's `qt-capture.cpp`, here without Qt.
The origin stamp, the drag profiles, the move-sync and drag-table specifications and the `buffer_device` field are DisplayXR's, by David Fattal and the DisplayXR maintainers (`docs/specs/runtime/wayland-window-geometry.md`, `scripts/linux/move_sync/`).
KWin's fake input protocol is Martin Gräßlin's (`plasma-wayland-protocols`, LGPL-2.1-or-later; the kit generates its code from the installed XML and ships no copy); ScreenShot2 and the screen cast are the KWin developers'.
`consumer-convert.c` builds against DisplayXR's `u_wayland_geom.h` and its bundled cJSON (Dave Gamble and contributors, MIT).
