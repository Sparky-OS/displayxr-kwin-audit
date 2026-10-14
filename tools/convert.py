# SPDX-License-Identifier: BSL-1.0
# convert.py: the consumer's conversion of the integer wire, as a Python function the checks share.
# A consumer that knows no buffer_device converts round((buffer - monitor) * device_scale), half away
# from zero (displayxr-runtime u_wayland_geom.h, u_wl_logical_to_px); the kit's checks use it to say
# where the old conversion lands, next to buffer_device and the paint. tools/build.sh also builds
# consumer-convert from the runtime's own header when DXR_SRC is set; the checks prefer it and say
# which one they used.
import json
import math
import os
import subprocess


def rnd(v):
    return int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1)


def converted(window):
    """The device rect the old conversion gives for a window entry: (x, y, w, h)."""
    m, s = window['monitor'], window['monitor']['device_scale']
    b = window['buffer']
    return (rnd((b[0] - m['x']) * s), rnd((b[1] - m['y']) * s), rnd(b[2] * s), rnd(b[3] * s))


def converted_by_consumer(snapshot_text, pid, audit_bin):
    """consumer-convert's answer, (x, y, w, h), when the tool is built, else None."""
    tool = os.path.join(audit_bin, 'consumer-convert')
    if not os.path.exists(tool):
        return None
    out = subprocess.run([tool, str(pid)], input=snapshot_text, capture_output=True, text=True).stdout.split()
    if not out or out[0] != 'device':
        return None
    return tuple(int(v) for v in out[1:5])


def find(snapshot, title=None, app_id=None):
    """The first window entry whose title starts with title, or whose app_id contains app_id."""
    for w in snapshot['windows']:
        if title is not None and w['title'].startswith(title):
            return w
        if app_id is not None and app_id in w['app_id']:
            return w
    return None


def load(path):
    return json.load(open(path))
