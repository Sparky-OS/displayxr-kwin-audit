# SPDX-License-Identifier: BSL-1.0
# handdrag_check.py OUTDIR TAG: handdrag.sh's comparison, a Markdown table. Per drag: the frame GetWindows
# published at the rest and its buffer_device; the buffer_device of the last WindowsChanged payload, and
# when it was sent relative to the release (negative: before it; "none after" when the last signal came
# before the release); where the stamp is painted and the origin it encodes (what the runtime wove the
# resting frame for). Pass: GetWindows' buffer_device, the last signal's buffer_device, the stamp's
# position and its encoding are all the same pixel.
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import convert  # noqa: E402

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
out, tag = sys.argv[1], sys.argv[2]
marks = {}
for line in open(f'{out}/marks-{tag}.txt'):
    p = line.split()
    if len(p) > 1 and p[1].startswith('press='):
        marks[p[0]] = dict(kv.split('=') for kv in p[1:])
print(f'\n### Hand-drag rest, run {tag}\n')
print('| drag | frame at rest | GetWindows buffer_device | last WindowsChanged buffer_device | sent (ms after the release) | stamp painted | stamp encodes (woven for) | all equal |')
print('|---|---|---|---|---|---|---|---|')
ok = n = 0
for line in open(f'{out}/rests-{tag}.txt'):
    kind, t_rest = line.split()
    w = convert.find(convert.load(f'{out}/rest-{tag}-{kind}.json'), app_id='cube')
    release = int(marks[kind]['release'])
    last = None
    for s in open(f'{out}/signals-{tag}-{kind}.txt'):
        p = s.split()
        if p and p[0] == 'signal':
            last = (int(p[1]), p[2], json.loads(p[3]))
    st = subprocess.run([sys.executable, '-I', f'{KIT}/tools/stamp.py', f'{out}/rest-{tag}-{kind}.png'], capture_output=True, text=True).stdout.split()
    painted = (int(st[2]), int(st[3])) if len(st) > 6 else None
    woven = (int(st[5]), int(st[6])) if len(st) > 6 else None
    bd = tuple(w['buffer_device'][:2]) if w else None
    sig_bd = tuple(last[2][:2]) if last else None
    if last is None:
        when = 'no signal'
    elif last[0] < release:
        when = f'none after ({(last[0] - release) / 1000:.0f})'
    else:
        when = f'{(last[0] - release) / 1000:.0f}'
    good = bd is not None and bd == sig_bd == painted == woven
    n += 1
    ok += good
    print(f'| {kind} | {w["frame"][:2] if w else None} | {bd} | {sig_bd} | {when} | {painted} | {woven} | {"yes" if good else "NO"} |')
print(f'\n{ok} of {n} rests: GetWindows, the last signal, the paint and the weave name the same pixel.')
