# SPDX-License-Identifier: BSL-1.0
# dxr.py windows|state|caps|owner|introspect PATH|signals SECONDS [TITLE]: the window-geometry service,
# read from the session bus as any client sees it (python3-dbus).
#   windows     GetWindows, the JSON snapshot
#   state       CaptureExclusion1.GetState
#   caps        WindowPlacement1.GetPlacementCapabilities
#   owner       the unique name owning org.displayxr.WindowGeometry
#   introspect  the introspection XML of an object path
#   signals     records WindowsChanged for SECONDS: one line per signal, "signal T_US json" (T_US:
#               CLOCK_MONOTONIC in microseconds, the clock of KWin's debug lines); with TITLE, only the
#               entry of the window whose title starts with it, as "signal T_US moving BUFFER_DEVICE BUFFER"
import json
import sys
import time

import dbus

bus = dbus.SessionBus()
name = 'org.displayxr.WindowGeometry'
cmd = sys.argv[1]
if cmd == 'windows':
    print(bus.get_object(name, '/org/displayxr/WindowGeometry').GetWindows(dbus_interface='org.displayxr.WindowGeometry1'))
elif cmd == 'state':
    print(bus.get_object(name, '/org/displayxr/CaptureExclusion').GetState(dbus_interface='org.displayxr.CaptureExclusion1'))
elif cmd == 'caps':
    print(int(bus.get_object(name, '/org/displayxr/WindowPlacement').GetPlacementCapabilities(dbus_interface='org.displayxr.WindowPlacement1')))
elif cmd == 'owner':
    print(bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus').GetNameOwner(name, dbus_interface='org.freedesktop.DBus'))
elif cmd == 'introspect':
    print(bus.get_object(name, sys.argv[2]).Introspect(dbus_interface='org.freedesktop.DBus.Introspectable'))
elif cmd == 'signals':
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    seconds = float(sys.argv[2])
    title = sys.argv[3] if len(sys.argv) > 3 else None
    bus = dbus.SessionBus(mainloop=DBusGMainLoop(), private=True)
    seen = []
    bus.add_signal_receiver(lambda j: seen.append((int(time.monotonic() * 1e6), str(j))), 'WindowsChanged', 'org.displayxr.WindowGeometry1')
    loop = GLib.MainLoop()
    GLib.timeout_add(int(seconds * 1000), loop.quit)
    print('ready', flush=True)
    loop.run()
    for t, j in seen:
        if title is None:
            print('signal', t, j)
            continue
        for w in json.loads(j)['windows']:
            if w['title'].startswith(title):
                print('signal', t, w['moving'], json.dumps(w['buffer_device']).replace(' ', ''), json.dumps(w['buffer']).replace(' ', ''))
    print('count', len(seen))
else:
    print(__doc__ or 'dxr.py windows|state|caps|owner|introspect PATH|signals SECONDS [TITLE]', file=sys.stderr)
    sys.exit(2)
