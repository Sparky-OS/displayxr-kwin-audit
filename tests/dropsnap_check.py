# SPDX-License-Identifier: BSL-1.0
# dropsnap_check.py OUTDIR TAG: dropsnap.sh's comparison, a Markdown table. Per drop: where the stamp is
# painted against the origin it encodes (the weave's origin after the snap) and buffer_device; "match"
# when the three are equal. First, the runtime's "phase snap" landing lines, in order, from its log.
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import convert  # noqa: E402

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
out, tag = sys.argv[1], sys.argv[2]
kinds = [l.strip() for l in open(f'{out}/drops-{tag}.txt') if l.strip()]
log = open(f'{out}/runtime-{tag}.log', errors='replace').read()
snaps = re.findall(r'phase snap: (LANDED at \(\S+ \S+\) px|asked for .*?LANDED at \([^)]*\) — off by \([^)]*\))', log)
print(f'\n### Drop landings, run {tag}\n')
print(f'The runtime logged {len(snaps)} snap landing(s): ' + '; '.join(snaps) + '\n')
print('| drag | stamp painted | stamp encodes (woven for) | buffer_device | match |')
print('|---|---|---|---|---|')
ok = 0
for kind in kinds:
    st = subprocess.run([sys.executable, '-I', f'{KIT}/tools/stamp.py', f'{out}/drop-{tag}-{kind}.png'], capture_output=True, text=True).stdout.split()
    w = convert.find(convert.load(f'{out}/drop-{tag}-{kind}.json'), app_id='cube')
    if len(st) < 7 or w is None:
        print(f'| {kind} | {" ".join(st) or "no stamp"} | - | {w["buffer_device"][:2] if w else "no window"} | NO |')
        continue
    painted, woven = (int(st[2]), int(st[3])), (int(st[5]), int(st[6]))
    bd = tuple(w['buffer_device'][:2])
    good = painted == woven == bd
    ok += good
    print(f'| {kind} | {painted} | {woven} | {bd} | {"yes" if good else "NO"} |')
print(f'\n{ok} of {len(kinds)} drops painted where woven, and buffer_device names the pixel.')
