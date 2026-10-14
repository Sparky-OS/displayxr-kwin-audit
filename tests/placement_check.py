# SPDX-License-Identifier: BSL-1.0
# placement_check.py OUTDIR TAG: placement.sh's comparison, a Markdown table. Per window and frame position:
# buffer_device from the snapshot; the painted rect from the capture (the red or blue surface's bounding
# box; the cube's woven surface's top-left from its origin stamp, its size from the snapshot); and the old
# conversion of buffer, round((buffer - monitor) * scale) (consumer-convert when built, else the rule in
# tools/convert.py). The last lines are the row of DisplayXR/displayxr-runtime#1928's table: captures,
# buffer_device = painted, old conversion = painted.
import os
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import convert  # noqa: E402

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
AUDIT_BIN = os.environ.get('AUDIT_BIN') or os.path.join(KIT, 'build')
out, tag = sys.argv[1], sys.argv[2]

print(f'\n### Placement, output scale {tag}\n')
print('| frame position (logical, from the output origin) | window | buffer_device | painted | old conversion of buffer | buffer_device = painted |')
print('|---|---|---|---|---|---|')
ok = n = differ = 0
used_consumer = False
for line in open(f'{out}/positions-{tag}.txt'):
    k, x, y = line.split()
    snap_text = open(f'{out}/snap-{tag}-{k}.json').read()
    snap = convert.load(f'{out}/snap-{tag}-{k}.json')
    a = np.asarray(Image.open(f'{out}/cap-{tag}-{k}.png').convert('RGB')).astype(int)
    for w in snap['windows']:
        if w['title'] not in ('bd', 'bn') and 'cube' not in w['app_id'].lower():
            continue
        bd = w['buffer_device']
        conv = convert.converted_by_consumer(snap_text, w['pid'], AUDIT_BIN)
        used_consumer |= conv is not None
        conv = list(conv) if conv else list(convert.converted(w))
        if w['title'] in ('bd', 'bn'):
            colour = (255, 0, 0) if w['title'] == 'bd' else (0, 0, 255)
            mask = (a[:, :, 0] == colour[0]) & (a[:, :, 1] == colour[1]) & (a[:, :, 2] == colour[2])
            ys, xs = np.nonzero(mask)
            painted = [int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)] if len(xs) else None
            name = w['title'] + (' (surface 10 px above the frame)' if w['title'] == 'bd' else '')
        else:
            st = subprocess.run([sys.executable, '-I', f'{KIT}/tools/stamp.py', f'{out}/cap-{tag}-{k}.png'], capture_output=True, text=True).stdout.split()
            painted = [int(st[2]), int(st[3]), bd[2], bd[3]] if len(st) > 3 else None
            name = 'cube (title bar subsurface; size not measured)'
        good = painted == bd
        n += 1
        ok += good
        differ += (painted is not None and conv[:2] != painted[:2])
        print(f'| {x}, {y} | {name} | {bd} | {painted} | {conv} | {"yes" if good else "NO"} |')
print(f'\n{ok} of {n} equal; the old conversion of buffer differs from the painted origin in {differ} of {n}.')
print(f'Old conversion by {"consumer-convert (the runtime\'s own code)" if used_consumer else "tools/convert.py"}.')
print(f'\n| scale | captures | buffer_device = painted | old conversion = painted |\n|---|---|---|---|\n| {tag} | {n} | {ok}/{n} | {n - differ}/{n} |')
