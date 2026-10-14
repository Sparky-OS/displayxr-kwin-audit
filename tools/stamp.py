# SPDX-License-Identifier: BSL-1.0
# stamp.py PNG [PERIOD]: reads DisplayXR's origin stamp (DXR_WL_ORIGIN_STAMP=1: 44 blocks of 8x8 device px
# at the top-left of the woven surface, white = 1; blocks 0-3 a 1010 marker, then x + 32768 and y + 32768,
# 16 bits each, MSB first, then an 8-bit counter; comp_vk_native_compositor.c vk_debug_origin_stamp)
# from a capture. Prints where the stamp is painted, the origin it encodes (the present origin the
# runtime wove that frame for), and, with PERIOD, where the interlace stripe boundaries fall in panel
# columns: the residue modulo PERIOD of the columns with the strongest horizontal change inside the
# woven surface below the stamp. A correct phase puts them at residue 0 (sim_display's
# floor((column + phase) / period) mod 2 with phase = the window's panel x).
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.int32)
H, W, _ = a.shape
white = np.all(a == 255, axis=2)
black = np.all(a == 0, axis=2)
found = None
for y in range(H - 8):
    row_w, row_b = white[y], black[y]
    xs = np.nonzero(row_w[:W - 352])[0]
    for x in xs:
        if (white[y:y + 8, x:x + 8].all() and black[y:y + 8, x + 8:x + 16].all() and white[y:y + 8, x + 16:x + 24].all()
                and black[y:y + 8, x + 24:x + 32].all() and (y == 0 or not white[y - 1, x:x + 8].all())
                and (x == 0 or not white[y:y + 8, x - 1].all())):
            found = (int(x), int(y))
            break
    if found:
        break
if not found:
    print('stamp none')
    sys.exit(1)
x0, y0 = found
bits = [1 if a[y0:y0 + 8, x0 + 8 * i:x0 + 8 * i + 8].mean() > 128 else 0 for i in range(44)]
val = lambda b: int(''.join(map(str, b)), 2)
ox, oy, seq = val(bits[4:20]) - 32768, val(bits[20:36]) - 32768, val(bits[36:44])
print(f'stamp painted {x0} {y0} encodes {ox} {oy} seq {seq} match {"yes" if (ox, oy) == (x0, y0) else "no"}')
if len(sys.argv) > 2:
    period = int(sys.argv[2])
    # The woven surface: from the stamp's row + 16 down, as wide as the window's dark background row.
    region = a[y0 + 16:min(H, y0 + 600), x0:min(W, x0 + 1200)]
    grad = np.abs(np.diff(region, axis=1)).sum(axis=(0, 2))  # change between column c and c + 1
    cols = np.arange(x0 + 1, x0 + 1 + grad.size)  # the panel column where the new value starts
    sums = np.array([grad[(cols % period) == r].sum() for r in range(period)], dtype=float)
    r = int(sums.argmax())
    others = np.delete(sums, r)
    print(f'stripes period {period} boundary_residue {r} contrast {sums[r] / max(np.median(others), 1):.1f}')
