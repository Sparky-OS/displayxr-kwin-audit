# SPDX-License-Identifier: BSL-1.0
# capture.py OUT.png [OUTPUT]: one frame of KWin's ScreenShot2 interface (CaptureScreen for OUTPUT, else
# CaptureActiveScreen) at the output's native resolution, in DEVICE pixels, without the cursor, saved as
# PNG. Prints "size WxH format F". KWin must allow the caller: start it with
# KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 for the audit. Over the session bus with python3-dbus; no Qt.
# The pixels come through a pipe, as Spectacle reads them; the format is a QImage::Format number.
import os
import select
import sys

import dbus
import numpy as np
from PIL import Image

out = sys.argv[1]
output = sys.argv[2] if len(sys.argv) > 2 else None
bus = dbus.SessionBus()
iface = dbus.Interface(bus.get_object('org.kde.KWin.ScreenShot2', '/org/kde/KWin/ScreenShot2'), 'org.kde.KWin.ScreenShot2')
options = dbus.Dictionary({'include-cursor': dbus.Boolean(False), 'native-resolution': dbus.Boolean(True)}, signature='sv')
r, w = os.pipe()
fd = dbus.types.UnixFd(w)
os.close(w)
try:
    if output:
        reply = iface.CaptureScreen(output, options, fd, timeout=30)
    else:
        reply = iface.CaptureActiveScreen(options, fd, timeout=30)
except dbus.exceptions.DBusException as e:
    print(f'capture failed: {e.get_dbus_name()}: {e.get_dbus_message()}', file=sys.stderr)
    sys.exit(3)
width, height, stride, fmt = (int(reply[k]) for k in ('width', 'height', 'stride', 'format'))
size = stride * height
data = bytearray()
while len(data) < size:
    if not select.select([r], [], [], 30)[0]:
        print(f'capture timed out after 30 s with {len(data)}/{size} bytes', file=sys.stderr)
        sys.exit(5)
    chunk = os.read(r, size - len(data))
    if not chunk:
        break
    data += chunk
os.close(r)
if len(data) != size:
    print(f'short capture: {len(data)}/{size} bytes', file=sys.stderr)
    sys.exit(5)
a = np.frombuffer(bytes(data), np.uint8).reshape(height, stride)[:, :width * 4].reshape(height, width, 4)
# QImage formats: 4 RGB32, 5 ARGB32, 6 ARGB32_Premultiplied are B,G,R,A in memory on little-endian
# machines; 16 RGBX8888, 17 RGBA8888, 18 RGBA8888_Premultiplied are R,G,B,A.
if fmt in (4, 5, 6):
    rgb = a[:, :, [2, 1, 0]]
elif fmt in (16, 17, 18):
    rgb = a[:, :, :3]
else:
    print(f'capture format {fmt} is not handled', file=sys.stderr)
    sys.exit(4)
Image.fromarray(np.ascontiguousarray(rgb), 'RGB').save(out)
print(f'size {width}x{height} format {fmt}')
