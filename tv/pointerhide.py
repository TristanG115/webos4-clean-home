#!/usr/bin/env python
# pointerhide.py - runs ON the TV (Python 2.7). Keeps the Magic Remote pointer hidden.
# How the pointer works (found by recording the real remote, see docs/AUDIT.md): the remote's driver (lginput2) sends two custom key codes to the compositor on the
# device "LGE M-RCU - Builtin [n]": 1198 = "show the pointer" (right before every pointer movement or wheel turn) and 1199 = "hide the pointer" (sent when you press an
# arrow, digit or OK). This watcher READS those devices (no grab: if it dies or is stopped nothing breaks, the remote keeps working) and, the moment it sees 1198, writes a
# 1199 press + release into the same device, so the compositor hides the pointer again right away. Clicks and keys are untouched.
# Usage: python pointerhide.py        stop: touch /tmp/pointerhide.stop        log: /tmp/pointerhide.log (counters only)
import os, sys, struct, select, time

EVS = struct.Struct('<llHHi')
SHOW, HIDE = 1198, 1199
STOP = '/tmp/pointerhide.stop'
LOG = '/tmp/pointerhide.log'

def devices():
    found = {}
    cur = None
    try:
        for line in open('/proc/bus/input/devices'):
            if line.startswith('N: Name='):
                cur = line.split('=', 1)[1].strip().strip('"')
            elif line.startswith('H: Handlers=') and cur and cur.startswith('LGE'):
                for h in line.split('=', 1)[1].split():
                    if h.startswith('event'):
                        found['/dev/input/' + h] = cur
    except Exception:
        pass
    return found

def press(code):
    return (EVS.pack(0, 0, 1, code, 1) + EVS.pack(0, 0, 0, 0, 0) +
            EVS.pack(0, 0, 1, code, 0) + EVS.pack(0, 0, 0, 0, 0))

def main():
    try:
        os.remove(STOP)
    except OSError:
        pass
    fds = {}
    paths = {}
    seen = hidden = 0
    last_scan = 0
    last_log = 0
    while not os.path.exists(STOP):
        now = time.time()
        if now - last_scan > 2:
            last_scan = now
            names = devices()
            for p in names:
                if p not in paths:
                    try:
                        fd = os.open(p, os.O_RDWR | os.O_NONBLOCK)
                    except OSError:
                        continue
                    fds[fd] = p; paths[p] = fd
            for p in list(paths):
                if p not in names:
                    fd = paths.pop(p); fds.pop(fd, None)
                    try:
                        os.close(fd)
                    except OSError:
                        pass
        try:
            ready = select.select(list(fds), [], [], 0.5)[0] if fds else []
        except Exception:
            ready = []
            time.sleep(0.5)
        for fd in ready:
            try:
                data = os.read(fd, EVS.size * 64)
            except OSError:
                continue
            for i in range(0, len(data) - EVS.size + 1, EVS.size):
                sec, usec, typ, code, val = EVS.unpack_from(data, i)
                if typ == 1 and code == SHOW and val == 1:
                    seen += 1
                    try:
                        os.write(fd, press(HIDE))
                        hidden += 1
                    except OSError:
                        pass
        if now - last_log > 5:
            last_log = now
            try:
                open(LOG, 'w').write('show_seen=%d hide_sent=%d devices=%d\n' % (seen, hidden, len(fds)))
            except Exception:
                pass

main()
