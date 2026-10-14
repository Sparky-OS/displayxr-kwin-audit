# SPDX-License-Identifier: BSL-1.0
# movesync_report.py OUTDIR TAG [--md]: one row per drag of movesync.sh. From the screen cast audit
# (cast-TAG-KIND.txt): the frames the cast sent, those whose stamp is painted at the origin it encodes, those
# painted elsewhere, and of those, how many fall while KWin held the window (a hold interval from KWin's
# debug lines, minus 100 ms after each change of state: the cast delivers a frame up to about three
# refreshes after KWin rendered it, so a frame rendered before the change may still arrive). From KWin's
# summary for the drag (its log at AUDIT_KWIN_LOG, with DISPLAYXR_DEBUG=1): frames held, advances on a woven
# frame, timeouts, back hops, max behind (logical px), holds and tag-lost releases, why the hold ended. Then
# the snapshot after the drop. Without KWin's log those columns read "-". A stamp that reads as an origin
# from which the whole stamp could not be on the output is not counted.
import os
import re
import sys

out, tag = sys.argv[1], sys.argv[2]
md = '--md' in sys.argv
kwin_log = os.environ.get('AUDIT_KWIN_LOG')
events = []  # (t, state) with state 'held' / 'plain' / 'end'
dones = []
if kwin_log and os.path.exists(kwin_log):
    for line in open(kwin_log, errors='replace'):
        m = re.search(r'move sync (begin|tag appeared|tag gone|timeout|resync|done) t=(\d+)(.*)', line)
        if not m:
            continue
        kind, t, rest = m.group(1), int(m.group(2)), m.group(3)
        if kind == 'begin':
            events.append((t, 'held' if rest.strip().endswith('held') else 'plain'))
        elif kind in ('tag appeared', 'resync'):
            events.append((t, 'held'))
        elif kind in ('tag gone', 'timeout'):
            events.append((t, 'plain'))
        else:
            events.append((t, 'end'))
            dones.append(rest.strip())
drops = [l.rstrip('\n').split(' ', 1) for l in open(f'{out}/drops-{tag}.txt') if l.strip()]
marks = {}
for line in open(f'{out}/marks-{tag}.txt'):
    p = line.split()
    if len(p) > 1 and '=' in p[1] and p[1].startswith('press'):
        marks[p[0]] = dict(kv.split('=') for kv in p[1:])


def state_at(t):
    s, since = 'none', 0
    for et, es in events:
        if et > t:
            break
        s, since = es, et
    return s, t - since


rows = []
for i, (kind, drop) in enumerate(drops):
    frames = woven = off = off_held = held_frames = 0
    try:
        for line in open(f'{out}/cast-{tag}-{kind}.txt'):
            p = line.split()
            if len(p) < 3 or p[2] in ('none', 'clipped'):
                continue
            frames += 1
            t = int(p[-1][2:])
            st, age = state_at(t)
            held = st == 'held' and age > 100000
            held_frames += held
            if p[-2] == 'match':
                woven += 1
            else:
                off += 1
                off_held += held
    except FileNotFoundError:
        pass
    # KWin's summary for this drag: the first "done" after the drag's press.
    d = ''
    mk = marks.get(kind.split('@')[0]) or marks.get(kind)
    if mk and events:
        press = int(mk['press'])
        for (t, s), text in zip([e for e in events if e[1] == 'end'], dones):
            if t > press:
                d = text
                break
    m = re.search(r'\((.*?)\): (\d+) frames, (\d+) advances .*?, (\d+) timeouts, (\d+) back hops, (\d+) untagged, max behind (\d+) logical px, (\d+) holds, (\d+) tag-lost', d)
    k = m.groups() if m else ('-',) + ('-',) * 8
    held_col = f'{off_held} of {held_frames}' if events else '-'
    rows.append([kind, str(frames), str(woven), str(off), held_col, k[1], k[2], k[3], k[4], k[6], f'{k[7]} / {k[8]}' if m else '-', k[0], drop.strip()])
hdr = ['drag', 'cast frames', 'stamp where woven', 'stamp elsewhere', 'elsewhere while held', 'KWin frames held', 'advances',
       'timeouts', 'back hops', 'max behind', 'holds / tag lost', 'ended', 'after the drop']
if md:
    print(f'\n### Move sync, run {tag}\n')
    print('| ' + ' | '.join(hdr) + ' |')
    print('|' + '---|' * len(hdr))
for r in rows:
    print(('| ' + ' | '.join(r) + ' |') if md else '  '.join(r))
if md:
    total = sum(int(r[1]) for r in rows)
    print(f'\n{sum(int(r[2]) for r in rows)} of {total} cast frames painted where woven; '
          f'{"KWin\'s own columns from " + kwin_log if events else "no KWin log (AUDIT_KWIN_LOG): KWin\'s own columns left out"}.')
