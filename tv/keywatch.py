# keywatch.py DEVICE... - prints "BACK" (one line, flushed) each time the remote's Back key goes down on any of the given evdev devices.
# Read-only: it only reads /dev/input/event*, like the system does. Python 2.7 (the only Python on the TV); 32-bit ARM struct input_event = 16 bytes.
import os, select, struct, sys
EV_KEY, KEY_BACK = 1, 158
fds = []
for p in sys.argv[1:]:
    try:
        fds.append(os.open(p, os.O_RDONLY | os.O_NONBLOCK))
    except OSError:
        pass
if not fds:
    sys.exit(1)
while True:
    r, _, _ = select.select(fds, [], [])
    for fd in r:
        try:
            data = os.read(fd, 16 * 32)
        except OSError:
            continue
        for i in range(0, len(data) - 15, 16):
            _, _, t, c, v = struct.unpack('<iiHHi', data[i:i + 16])
            if t == EV_KEY and c == KEY_BACK and v == 1:
                sys.stdout.write('BACK\n')
                sys.stdout.flush()
