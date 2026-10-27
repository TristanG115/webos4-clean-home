#!/usr/bin/env python
# remote-recorder.py - runs ON the TV (Python 2.7). READ-ONLY: records everything the remote does, changes nothing.
#   ./tv.sh 'cat > /tmp/rec.py' < tools/remote-recorder.py ; ./tv.sh -s <<< '( setsid python /tmp/rec.py </dev/null >/dev/null 2>&1 & )'
#   stop: touch /tmp/rec/stop     result: /tmp/rec/events.log
# It opens every /dev/input/event* node for reading only (no grab, so the TV keeps working normally), re-scans every 2 s (the Magic Remote creates new nodes when it
# reconnects), and follows /var/log/messages for the lines that name the button (lginput2 NL_BUTTON_CLICK ...), the cursor and the windows that open.
# Output lines:  <arrival time> EV <device name> type=<n> code=<n> value=<n>      (key presses, wheel, buttons)
#                <arrival time> MOVE <device name> type=<n> code=<n> count=<n> last=<v>   (pointer motion, summarised twice a second)
#                <arrival time> LOG <log line>
import os, sys, struct, select, time, re

OUT_DIR = '/tmp/rec'
OUT = OUT_DIR + '/events.log'
LOGF = '/var/log/messages'
EVS = struct.Struct('<llHHi')          # struct input_event on 32-bit ARM: timeval (2 x 4 bytes), type, code, value
KEEP = re.compile(r'lginput2|NL_BUTTON|NL_VSC|NL_APP_LAUNCH_BEGIN|cursor|Cursor|mrcu|qs:')

def device_names():
    names = {}
    cur = None
    try:
        for line in open('/proc/bus/input/devices'):
            if line.startswith('N: Name='):
                cur = line.split('=', 1)[1].strip().strip('"')
            elif line.startswith('H: Handlers=') and cur is not None:
                for h in line.split('=', 1)[1].split():
                    if h.startswith('event'):
                        names['/dev/input/' + h] = cur
    except Exception:
        pass
    return names

def main():
    try:
        os.makedirs(OUT_DIR)
    except OSError:
        pass
    try:
        os.remove(OUT_DIR + '/stop')
    except OSError:
        pass
    out = open(OUT, 'a')
    def w(kind, text):
        out.write('%.3f %s %s\n' % (time.time(), kind, text))
        out.flush()
    w('LOG', 'recorder started')
    fds = {}                     # fd -> (path, name)
    paths = {}                   # path -> fd
    moves = {}                   # (name, type, code) -> [count, last value, last written]
    last_scan = 0
    log_f = None
    log_ino = None
    while True:
        now = time.time()
        if os.path.exists(OUT_DIR + '/stop') or os.path.getsize(OUT) > 4000000:
            w('LOG', 'recorder stopped')
            return
        if now - last_scan > 2:
            last_scan = now
            names = device_names()
            for p in sorted(names):
                if p not in paths:
                    try:
                        fd = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
                    except OSError:
                        continue
                    fds[fd] = (p, names[p]); paths[p] = fd
                    w('LOG', 'opened %s = %s' % (p, names[p]))
            for p in list(paths):
                if p not in names:
                    fd = paths.pop(p)
                    fds.pop(fd, None)
                    try:
                        os.close(fd)
                    except OSError:
                        pass
                    w('LOG', 'gone %s' % p)
        try:
            ready = select.select(list(fds), [], [], 0.2)[0] if fds else []
        except Exception:
            ready = []
            time.sleep(0.2)
        for fd in ready:
            try:
                data = os.read(fd, EVS.size * 64)
            except OSError:
                continue
            name = fds[fd][1]
            for i in range(0, len(data) - EVS.size + 1, EVS.size):
                sec, usec, typ, code, val = EVS.unpack_from(data, i)
                if typ == 0:
                    continue
                if typ in (2, 3):                       # REL / ABS: summarise
                    m = moves.setdefault((name, typ, code), [0, 0, 0.0])
                    m[0] += 1; m[1] = val
                    if time.time() - m[2] > 0.5:
                        w('MOVE', '%s type=%d code=%d count=%d last=%d' % (name, typ, code, m[0], val))
                        m[0] = 0; m[2] = time.time()
                else:
                    w('EV', '%s type=%d code=%d value=%d' % (name, typ, code, val))
        # follow the system log (it rotates every minute or two and sometimes does not exist)
        try:
            st = os.stat(LOGF)
            if log_f is None or st.st_ino != log_ino:
                log_f = open(LOGF)
                log_ino = st.st_ino
                if log_f is not None and log_ino is not None:
                    pass
            for line in log_f.readlines():
                if KEEP.search(line):
                    w('LOG', line.strip()[:300])
        except Exception:
            log_f = None
            log_ino = None

main()
