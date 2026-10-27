# keywatch.py - reports the remote's Back key, one word per line (flushed):
#   BACK   every press of Back (Linux code 158 = the IR remote, 412 = the Magic Remote; found by recording the real remote)
#   LEAVE  Back held for 0.8 s, or pressed twice within 1.2 s (what counts is chosen in state/back.conf: leave=both|hold|double|off, default both)
# Read-only: it only reads /dev/input/event*, like the system does. It looks for the remote's devices ("LGE ...") every 3 s because the Magic Remote creates
# new ones each time it reconnects. Python 2.7 (the only Python on the TV); 32-bit ARM struct input_event = 16 bytes.
import os, select, struct, sys, time
EV_KEY = 1
ESIZE = struct.calcsize('llHHi')      # struct input_event of THIS CPU: 16 bytes on 32-bit ARM (the dev TV), 24 on 64-bit
BACKS = (158, 412)
CONF = '/media/developer/tv-debloat/state/back.conf'

def mode():
    try:
        for line in open(CONF):
            if line.startswith('leave='):
                v = line.strip().split('=', 1)[1]
                if v in ('both', 'hold', 'double', 'off'):
                    return v
    except Exception:
        pass
    return 'both'

def devices():
    found = []
    cur = None
    try:
        for line in open('/proc/bus/input/devices'):
            if line.startswith('N: Name='):
                cur = line.split('=', 1)[1].strip().strip('"')
            elif line.startswith('H: Handlers=') and cur and cur.startswith('LGE'):
                for h in line.split('=', 1)[1].split():
                    if h.startswith('event'):
                        found.append('/dev/input/' + h)
    except Exception:
        pass
    return found

def say(word):
    sys.stdout.write(word + '\n')
    sys.stdout.flush()

fds = {}
last_scan = 0
down_at = None       # when Back went down (None = not held / already reported)
last_press = 0
while True:
    now = time.time()
    if now - last_scan > 3:
        last_scan = now
        want = devices()
        for p in want:
            if p not in fds.values():
                try:
                    fds[os.open(p, os.O_RDONLY | os.O_NONBLOCK)] = p
                except OSError:
                    pass
        for fd in list(fds):
            if fds[fd] not in want:
                try:
                    os.close(fd)
                except OSError:
                    pass
                del fds[fd]
    try:
        r = select.select(list(fds), [], [], 0.2)[0] if fds else []
    except Exception:
        r = []
        time.sleep(0.2)
    for fd in r:
        try:
            data = os.read(fd, ESIZE * 32)
        except OSError:
            continue
        for i in range(0, len(data) - ESIZE + 1, ESIZE):
            _, _, t, c, v = struct.unpack('llHHi', data[i:i + ESIZE])
            if t == EV_KEY and c in BACKS:
                if v == 1:
                    n = time.time()
                    m = mode()
                    if m in ('both', 'double') and n - last_press < 1.2:
                        say('LEAVE')
                        last_press = 0
                        down_at = None
                    else:
                        say('BACK')
                        last_press = n
                        down_at = n if m in ('both', 'hold') else None
                elif v == 0:
                    down_at = None
    if down_at is not None and time.time() - down_at >= 0.8:      # still held: leave
        say('LEAVE')
        down_at = None
        last_press = 0
