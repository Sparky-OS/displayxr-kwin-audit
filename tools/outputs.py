# SPDX-License-Identifier: BSL-1.0
# outputs.py [NAME]: KWin's outputs from org.kde.KWin's supportInformation, so the kit needs no
# kscreen-doctor on the side it runs on. Prints one line per output: "name X Y W H scale" (logical
# geometry); with NAME, only that output, and exit 1 when KWin has no output of that name.
import re
import sys

import dbus

text = str(dbus.SessionBus().get_object('org.kde.KWin', '/KWin').supportInformation(dbus_interface='org.kde.KWin'))
outputs = []
current = None
for line in text.splitlines():
    m = re.match(r'Name:\s*(\S+)', line.strip())
    if m:
        current = {'name': m.group(1)}
        outputs.append(current)
        continue
    if current is None:
        continue
    m = re.match(r'Geometry:\s*(-?\d+),(-?\d+),(\d+)x(\d+)', line.strip())
    if m:
        current['geometry'] = tuple(int(v) for v in m.groups())
    m = re.match(r'Scale:\s*([0-9.]+)', line.strip())
    if m:
        current['scale'] = float(m.group(1))
outputs = [o for o in outputs if 'geometry' in o and 'scale' in o]
want = sys.argv[1] if len(sys.argv) > 1 else None
if want:
    outputs = [o for o in outputs if o['name'] == want]
    if not outputs:
        print(f'no output named {want}', file=sys.stderr)
        sys.exit(1)
for o in outputs:
    x, y, w, h = o['geometry']
    print(o['name'], x, y, w, h, f"{o['scale']:g}")
