# SPDX-License-Identifier: BSL-1.0
# movewindow_check.py OUTDIR TAG: movewindow.sh's comparison, a Markdown table. Per MoveWindow(x, y): the pixel
# the runtime expects the buffer on, round((buffer + (x, y) - frame - monitor) * scale) from the snapshot
# before; where the buffer is painted after (the red surface's top-left in the capture); the published
# buffer after, converted the old way; and buffer_device after.
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import convert  # noqa: E402

out, tag = sys.argv[1], sys.argv[2]
rnd = convert.rnd


def mw(path):
    return convert.find(convert.load(path), title='mw')


print(f'\n### MoveWindow, output scale {tag}\n')
print('| MoveWindow(x, y) | reply | expected buffer pixel | painted | buffer after, old conversion | buffer_device after | all equal |')
print('|---|---|---|---|---|---|---|')
ok = n = 0
for line in open(f'{out}/moves-{tag}.txt'):
    p = line.split()
    k, x, y, reply = p[0], int(p[1]), int(p[2]), ' '.join(p[3:])
    b, a = mw(f'{out}/before-{tag}-{k}.json'), mw(f'{out}/after-{tag}-{k}.json')
    m, s = b['monitor'], b['monitor']['device_scale']
    exp = (rnd((b['buffer'][0] + x - b['frame'][0] - m['x']) * s), rnd((b['buffer'][1] + y - b['frame'][1] - m['y']) * s))
    img = np.asarray(Image.open(f'{out}/after-{tag}-{k}.png').convert('RGB')).astype(int)
    ys, xs = np.nonzero((img[:, :, 0] == 255) & (img[:, :, 1] == 0) & (img[:, :, 2] == 0))
    painted = (int(xs.min()), int(ys.min())) if len(xs) else None
    conv = convert.converted(a)[:2]
    dev = tuple(a['buffer_device'][:2])
    good = exp == painted == conv == dev
    n += 1
    ok += good
    print(f'| {x}, {y} | {reply.replace("reply ", "")} | {exp} | {painted} | {conv} | {dev} | {"yes" if good else "NO"} |')
print(f'\n{ok} of {n} equal.')
