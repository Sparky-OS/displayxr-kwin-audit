# Running the kit against KWin in a chroot with a logind session

This is the setup DisplayXR used for the first panel run on DisplayXR/displayxr-runtime#1928 (2026-10-14): the Sparky Stereo OS bench root in a chroot on the laptop's own kernel, `kwin_wayland` started in a logind session on a free virtual terminal, the runtime and `cube_handle_vk_linux` running from the host as Wayland clients against a separate session bus.
The kit runs on the host side too, the way their runtime does, or from inside the root, which carries it at `/opt/displayxr-kwin-audit` with everything it needs.

## What KWin needs for the audit

Two variables in KWin's environment let the kit's clients in:

- `KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1`: the captures come from KWin's ScreenShot2 D-Bus interface, which otherwise answers only processes KWin trusts.
- `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`: the drags come through KWin's fake input protocol (`org_kde_kwin_fake_input`), which KWin otherwise offers only to clients it started.

For the move-sync columns that read KWin's own debug lines, add `DISPLAYXR_DEBUG=1 QT_LOGGING_RULES=kwin_displayxr.debug=true` and point `AUDIT_KWIN_LOG` at KWin's log (`journalctl -u <unit> -o cat > kwin.log` for a `systemd-run` unit).
The audit itself needs none of this: every table but those columns is measured from the bus, the captures and the screen cast.

A `systemd-run` line in the shape of theirs, with the variables added (one line):

```sh
systemd-run --unit kwin-audit -p PAMName=login -p RootDirectory=/path/to/sparky-root -p TTYPath=/dev/tty3 \
  -E KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 -E KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
  -E XDG_RUNTIME_DIR=/run/user/1000 -E DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/kwin-bus \
  --uid 1000 /usr/bin/kwin_wayland --socket wayland-kwin --no-lockscreen --no-global-shortcuts --no-kactivities
```

`/run/user/1000` must be the same directory inside and outside the root (bind-mount `/run` into it), so the bus socket, the Wayland socket, the PipeWire socket and the kit's KWin scripts (`AUDIT_SCRIPT_DIR`, default `XDG_RUNTIME_DIR`) are seen at one path by KWin and by the kit.
Start the separate session bus first (`dbus-daemon --session --address=unix:path=/run/user/1000/kwin-bus --fork`), so KWin's publisher registers its name on it.

## The kit's side

On the host, with the kit's tools built there (`tools/build.sh`), or inside the root (`chroot --userspec 1000:1000 /path/to/sparky-root`, where `/opt/displayxr-kwin-audit/build` holds them already):

```sh
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/kwin-bus XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-kwin
export AUDIT_OUTPUT=HDMI-A-1            # the panel, as KWin names it (tools/outputs.py lists them)
export AUDIT_OUT=$PWD/out AUDIT_BIN=/opt/displayxr-kwin-audit/build
export DXR_APP=/path/to/run_cube_handle_vk_linux.sh AUDIT_SIM=0
tests/smoke.sh
```

`AUDIT_SIM=0` lets the runtime drive the real panel; the origin stamp the tests read (`DXR_WL_ORIGIN_STAMP=1`) is drawn over the woven frame either way.
Set the output's scale as a user would, with `kscreen-doctor output.HDMI-A-1.scale.2` from inside the root (the root's `libkscreen` matches its KWin), before a run; the tests read the scale from the publisher's snapshot.

## The screen cast

`tests/movesync.sh` reads every frame KWin's screen cast sends through PipeWire.
KWin connects to the PipeWire daemon at `$XDG_RUNTIME_DIR/pipewire-0`; with `/run` shared, the host's daemon serves both, and the root carries PipeWire's client configuration, its modules, `pipewire` and `wireplumber` for a session without one.
The reader (`gst-launch-1.0` with `pipewiresrc`) must reach the same daemon: the same `XDG_RUNTIME_DIR`, or `PIPEWIRE_REMOTE`.
