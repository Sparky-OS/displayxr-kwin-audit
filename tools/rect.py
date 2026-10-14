# SPDX-License-Identifier: BSL-1.0
# rect.py PNG RRGGBB [columns]: the device-pixel rectangle a window of colour RRGGBB occupies in a capture.
# Prints "rect X Y W H count N full yes|no" (full: every pixel inside the bounding box has the colour,
# or for columns, alternate columns of the colour and black starting with the colour at X), and
# "absent" when no pixel has the colour.
import sys
import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(np.int32)
c = int(sys.argv[2], 16)
want = np.array([(c >> 16) & 255, (c >> 8) & 255, c & 255])
hit = np.all(img == want, axis=2)
if not hit.any():
    print('absent')
    sys.exit(1)
ys, xs = np.nonzero(hit)
x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
box = img[y0:y1 + 1, x0:x1 + 1]
if len(sys.argv) > 3 and sys.argv[3] == 'columns':
    expect = np.zeros_like(box)
    expect[:, 0::2] = want
    # the last column is black when the width is even: the box ends on a coloured column
    full = bool(np.all(box == expect))
    w = x1 - x0 + 1 + (1 if (x1 - x0 + 1) % 2 == 1 and len(sys.argv) > 4 else 0)
else:
    full = bool(np.all(box == want))
print(f'rect {x0} {y0} {x1 - x0 + 1} {y1 - y0 + 1} count {int(hit.sum())} full {"yes" if full else "no"}')
