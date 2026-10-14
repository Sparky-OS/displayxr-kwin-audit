# SPDX-License-Identifier: BSL-1.0
# stampcast.py W H X0 Y0 OUT [PANEL_W PANEL_H]: reads raw RGBx frames of W x H device px (a crop of the output
# whose top-left is X0,Y0 on the output) from stdin, one after the other, as KWin's output screen cast sends them, and
# finds DisplayXR's origin stamp in each (DXR_WL_ORIGIN_STAMP=1: 44 blocks of 8x8 px at the top-left of
# the woven surface, white = 1; blocks 0-3 the marker 1010, then x + 32768 and y + 32768 in 16 bits each,
# MSB first, then an 8-bit counter). Writes one line per frame to OUT: "frame N painted X,Y woven X,Y seq S
# match|OFF t=T" in output device px (T: when the frame arrived, CLOCK_MONOTONIC in microseconds, the clock
# of KWin's debug lines), or "frame N none t=T" when no whole stamp is in the crop, or "frame N clipped ..." when
# what reads as a stamp encodes an origin from which the whole stamp could not be on the output (PANEL_W x
# PANEL_H device px, default 3840x2160; a stamp cut off at the output's edge, read from the middle of its bits);
# prints a summary.
import sys
import time

import numpy as np

w, h, x0, y0, out = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
panel_w = int(sys.argv[6]) if len(sys.argv) > 6 else 3840
panel_h = int(sys.argv[7]) if len(sys.argv) > 7 else 2160
size = w * h * 4
stdin = sys.stdin.buffer
n = matched = off = none = clipped = 0
with open(out, 'w') as f:
    while True:
        buf = stdin.read(size)
        if len(buf) < size:
            break
        t = int(time.monotonic() * 1e6)
        a = np.frombuffer(buf, np.uint8).reshape(h, w, 4)[:, :, :3]
        white = (a == 255).all(axis=2)
        black = (a == 0).all(axis=2)
        # Marker corners: white, black, white, black 8x8 blocks, with no white just above or left of it.
        c = np.zeros((h - 8, w - 352), bool)
        c[:] = white[:h - 8, :w - 352]
        for dy in (0, 7):
            for i, colour in enumerate((white, black, white, black)):
                for dx in (0, 7):
                    c &= colour[dy:dy + h - 8, 8 * i + dx:8 * i + dx + w - 352]
        c[1:, :] &= ~white[:h - 9, :w - 352]
        c[:, 1:] &= ~white[:h - 8, :w - 353]
        ys, xs = np.nonzero(c)
        n += 1
        if len(ys) == 0:
            none += 1
            f.write(f'frame {n} none t={t}\n')
            continue
        y, x = int(ys[0]), int(xs[0])
        bits = [1 if a[y:y + 8, x + 8 * i:x + 8 * i + 8].mean() > 128 else 0 for i in range(44)]
        val = lambda b: int(''.join(map(str, b)), 2)
        ox, oy, seq = val(bits[4:20]) - 32768, val(bits[20:36]) - 32768, val(bits[36:44])
        px, py = x0 + x, y0 + y
        if not (0 <= ox <= panel_w - 352 and 0 <= oy <= panel_h - 8):
            clipped += 1
            f.write(f'frame {n} clipped painted {px},{py} reads {ox},{oy} t={t}\n')
            continue
        good = (ox, oy) == (px, py)
        matched += good
        off += not good
        f.write(f'frame {n} painted {px},{py} woven {ox},{oy} seq {seq} {"match" if good else "OFF"} t={t}\n')
print(f'frames {n}: stamp painted where woven {matched}, off its woven origin {off}, no stamp in the crop {none}, cut off at the output edge {clipped}')
