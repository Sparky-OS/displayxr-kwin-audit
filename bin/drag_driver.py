# SPDX-License-Identifier: BSL-1.0
# drag_driver.py KIND X Y MARKS [BUTTON]: one injected drag with DisplayXR's own drag profiles (the motion of
# displayxr-runtime scripts/linux/move_sync/driver.py, there through mutter's RemoteDesktop, here through
# KWin's fake input via fake-click follow). Press at X,Y (logical px), the profile's pause, its motion
# steps every 8 ms, its release pause, release. Each command waits for fake-click's "done", so the times
# written to MARKS (CLOCK_MONOTONIC, microseconds, the clock KWin's debug lines use) are when the
# compositor received each event. BUTTON "right" presses the right button (a content drag).
# Profiles: slow_h slow_hold fast_h slow_d short_d fast_d reverse rest_start release_mid back_h tile_top
# tile_left, plus the hand-drag rest profiles rest_F (F a fraction, rest_0.25, rest_0.6, ...): 300 steps of
# less than a logical pixel each, ending 90 + F logical px right and 30 + F down, so the window rests on a
# frame position with fraction F on both axes (DisplayXR/displayxr-runtime#1928, the Odyssey 3D rest case).
import os
import subprocess
import sys
import time

BIN = os.environ.get('AUDIT_BIN') or os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build')


def profile(kind):
    if kind.startswith('rest_') and kind != 'rest_start':
        f = float(kind[5:])
        return (0.3, [((90 + f) / 300, (30 + f) / 300)] * 300, 0.008, 0.3)
    return {
        'slow_h': (0.3, [(1.0, 0.0)] * 300, 0.008, 0.3),
        'slow_hold': (0.3, [(1.0, 0.0)] * 150, 0.008, 2.0),
        'fast_h': (0.3, [(10.0, 0.0)] * 60, 0.008, 0.3),
        'slow_d': (0.3, [(0.94, 0.34)] * 300, 0.008, 0.3),
        'short_d': (0.3, [(0.94, 0.34)] * 100, 0.008, 0.3),
        'fast_d': (0.3, [(9.4, 3.4)] * 60, 0.008, 0.3),
        'reverse': (0.3, [(4.0, 0.0)] * 60 + [(-4.0, 0.0)] * 60, 0.008, 0.3),
        'rest_start': (1.0, [(3.0, 0.0)] * 100, 0.008, 0.3),
        'release_mid': (0.3, [(6.0, 0.0)] * 80, 0.008, 0.0),
        'back_h': (0.3, [(-6.0, 0.0)] * 100, 0.008, 0.3),
        'tile_top': (0.3, [(0.0, -12.0)] * 80, 0.008, 0.6),
        'tile_left': (0.3, [(-15.0, 0.0)] * 120, 0.008, 0.6),
    }[kind]


kind, x, y, marks = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
button = sys.argv[5] if len(sys.argv) > 5 else 'left'
down, up = ('rdown', 'rup') if button == 'right' else ('down', 'up')
p = subprocess.Popen([os.path.join(BIN, 'fake-click'), 'follow'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def send(line):
    p.stdin.write(line + '\n')
    p.stdin.flush()
    while not p.stdout.readline().startswith('done'):
        pass
    return int(time.monotonic() * 1e6)


pre, steps, dt, rel = profile(kind)
send(f'{x:.4f} {y:.4f}')
time.sleep(0.3)
t_press = send(down)
time.sleep(pre)
t_move = None
for dx, dy in steps:
    x, y = x + dx, y + dy
    t = send(f'{x:.4f} {y:.4f}')
    t_move = t_move or t
    time.sleep(dt)
t_stop = int(time.monotonic() * 1e6)
time.sleep(rel)
t_release = send(up)
time.sleep(0.8)
p.stdin.close()
p.wait()
with open(marks, 'a') as m:
    m.write(f'{kind} press={t_press} move={t_move} stop={t_stop} release={t_release}\n')
