# keys.py - the remote "emulator": finds the TV's input devices by what they can do (not by number or name), builds input_event structs of the right size for the CPU,
# injects key presses, and probes whether all of that works on this TV. Python 2.7 or 3, standard library only (the TV's Python has no threading, no zlib).
#   python keys.py devices                  list input devices with the keys we care about
#   python keys.py find <code|name>         print the device path that supports that key (writable first), or nothing
#   python keys.py inject <code|name> [ms]  press and release a key on a device that supports it (hold for ms, default 60)
#   python keys.py probe [--effect]         full self-test, prints PASS / WARN / FAIL lines and a verdict. --effect also presses Home and checks the TV reacts
# Key names: back, home, settings, ok, up, down, left, right, mute, volup, voldown (the Linux codes differ between the IR remote and the Magic Remote; every candidate is tried).
import os, select, struct, subprocess, sys, time

EVSIZE = struct.calcsize('llHHi')            # native struct input_event: 16 bytes on 32-bit CPUs, 24 on 64-bit ones
EV_SYN, EV_KEY = 0, 1
CODES = {                                      # name -> candidate Linux key codes, most likely first (found by recording the real remotes, see AGENTS.md Round 9)
    'back': (412, 158), 'home': (773, 172, 102), 'settings': (139,), 'ok': (28, 352), 'up': (103,), 'down': (108,), 'left': (105,), 'right': (106,),
    'mute': (113,), 'volup': (115,), 'voldown': (114,),
}

def ev(t, c, v):
    return struct.pack('llHHi', 0, 0, t, c, v)

def devices():
    """[{'path','name','handlers','keys': set of supported key codes, 'writable': bool}] from /proc/bus/input/devices and /sys."""
    out, cur = [], None
    try:
        text = open('/proc/bus/input/devices').read()
    except Exception:
        return out
    for block in text.split('\n\n'):
        name, handlers = '', []
        for line in block.splitlines():
            if line.startswith('N: Name='):
                name = line.split('=', 1)[1].strip().strip('"')
            elif line.startswith('H: Handlers='):
                handlers = line.split('=', 1)[1].split()
        for h in handlers:
            if h.startswith('event'):
                path = '/dev/input/' + h
                out.append({'path': path, 'name': name, 'handlers': handlers, 'keys': keybits(h), 'writable': os.access(path, os.W_OK)})
    return out

def keybits(event):
    """supported key codes of /dev/input/<event>, read from the capability bitmap in /sys (hex words, most significant first)."""
    try:
        words = open('/sys/class/input/%s/device/capabilities/key' % event).read().split()
    except Exception:
        return set()
    bits, wbits = set(), struct.calcsize('l') * 8
    for i, w in enumerate(reversed(words)):
        try:
            n = int(w, 16)
        except ValueError:
            continue
        for b in range(wbits):
            if n >> b & 1:
                bits.add(i * wbits + b)
    return bits

def candidates(key):
    try:
        return (int(key),)
    except ValueError:
        return CODES.get(key, ())

def find(key):
    """(path, code) of the best device for this key: writable first, 'LGE' devices before others. None if no device supports it."""
    best = None
    for d in devices():
        for c in candidates(key):
            if c in d['keys']:
                score = (d['writable'], d['name'].startswith('LGE'))
                if best is None or score > best[0]:
                    best = (score, d['path'], c)
                break
    return (best[1], best[2]) if best else None

def inject(key, hold_ms=60):
    f = find(key)
    if not f:
        return None
    path, code = f
    fd = os.open(path, os.O_WRONLY)
    try:
        os.write(fd, ev(EV_KEY, code, 1) + ev(EV_SYN, 0, 0))
        time.sleep(hold_ms / 1000.0)
        os.write(fd, ev(EV_KEY, code, 0) + ev(EV_SYN, 0, 0))
    finally:
        os.close(fd)
    return path, code

def luna(uri, payload='{}'):
    try:
        p = subprocess.Popen(['luna-send', '-n', '1', '-w', '4000', uri, payload], stdin=open(os.devnull), stdout=subprocess.PIPE, stderr=open(os.devnull, 'w'))
        return p.communicate()[0].decode('utf-8', 'replace')
    except Exception:
        return ''

def foreground():
    out = luna('luna://com.webos.applicationManager/getForegroundAppInfo')
    i = out.find('"appId"')
    if i < 0:
        return ''
    j = out.find('"', out.find(':', i) + 1)
    return out[j + 1:out.find('"', j + 1)]

def roundtrip(path, code, wait=1.0):
    """write a key press into a device and read it back from a second handle on the same device: proves that writing events works here."""
    rfd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        time.sleep(0.05)
        wfd = os.open(path, os.O_WRONLY)
        os.write(wfd, ev(EV_KEY, code, 1) + ev(EV_SYN, 0, 0) + ev(EV_KEY, code, 0) + ev(EV_SYN, 0, 0))
        os.close(wfd)
        seen, end = 0, time.time() + wait
        while time.time() < end:
            if select.select([rfd], [], [], 0.1)[0]:
                data = os.read(rfd, EVSIZE * 32)
                for i in range(0, len(data) - EVSIZE + 1, EVSIZE):
                    _, _, t, c, v = struct.unpack('llHHi', data[i:i + EVSIZE])
                    if t == EV_KEY and c == code:
                        seen += 1
        return seen
    finally:
        os.close(rfd)

def say(level, text):
    print('%-5s %s' % (level, text))

def probe(effect):
    bad = warn = 0
    say('INFO', 'python %s, native input_event = %d bytes (%s)' % (sys.version.split()[0], EVSIZE, os.uname()[4] if hasattr(os, 'uname') else '?'))
    if EVSIZE not in (16, 24):
        say('WARN', 'unusual input_event size'); warn += 1
    devs = devices()
    if not devs:
        say('FAIL', 'no input devices found in /proc/bus/input/devices'); return 2
    say('PASS', '%d input event devices' % len(devs))
    for d in devs:
        have = [n for n in ('back', 'home', 'settings', 'ok', 'up', 'mute') if any(c in d['keys'] for c in CODES[n])]
        say('INFO', '%s  %-34s %s  keys: %s' % (d['path'], d['name'][:34], 'writable' if d['writable'] else 'READ-ONLY', ','.join(have) or '-'))
    for n in ('back', 'home', 'settings', 'ok', 'up'):
        f = find(n)
        if f:
            say('PASS', 'key %-8s -> %s code %d' % (n, f[0], f[1]))
        else:
            say('WARN' if n in ('settings',) else 'FAIL', 'key %-8s: no device supports it' % n)
            if n != 'settings':
                bad += 1
            else:
                warn += 1
    target = find('home') or find('back')
    if target:
        path, code = target
        try:
            seen = roundtrip(path, code)
        except Exception as e:
            seen = -1
            say('FAIL', 'writing to %s failed: %s' % (path, e)); bad += 1
        if seen > 0:
            say('PASS', 'round trip: a key written to %s was read back %d time(s): injecting works' % (path, seen))
        elif seen == 0:
            say('FAIL', 'round trip: events written to %s never came back: this TV drops injected events' % path); bad += 1
    if effect:
        fg0 = foreground()
        if not fg0:
            say('WARN', 'cannot read the foreground app (luna-send / SAM): effect test skipped'); warn += 1
        else:
            if 'home' in fg0.lower():           # pressing Home on Home proves nothing: first go somewhere else (every webOS TV has an HDMI 1 input app)
                luna('luna://com.webos.applicationManager/launch', '{"id":"com.webos.app.hdmi1"}')
                time.sleep(4)
                fg0 = foreground()
                if 'home' in fg0.lower():
                    say('WARN', 'effect: could not leave Home to test the Home key'); warn += 1
                    fg0 = ''
            r = inject('home', 80) if fg0 else None
            time.sleep(2.5)
            fg1 = foreground()
            if not fg0:
                pass
            elif r and fg1 != fg0:
                say('PASS', 'effect: Home key moved the TV from %s to %s' % (fg0, fg1))
            elif r:
                say('WARN', 'effect: Home key written but the foreground stayed %s (already on Home, or the TV ignores injected keys)' % fg0); warn += 1
            else:
                say('FAIL', 'effect: no device for the Home key'); bad += 1
    verdict = 'EMULATOR OK' if bad == 0 and warn == 0 else ('EMULATOR PARTLY OK (read the WARN lines)' if bad == 0 else 'EMULATOR WILL NOT WORK as is (read the FAIL lines)')
    print('RESULT: %s' % verdict)
    return 0 if bad == 0 else 1

def main(argv):
    cmd = argv[1] if len(argv) > 1 else 'devices'
    if cmd == 'devices':
        for d in devices():
            print('%s|%s|%s|%s' % (d['path'], d['name'], 'rw' if d['writable'] else 'ro', ','.join(n for n in sorted(CODES) if any(c in d['keys'] for c in CODES[n]))))
    elif cmd == 'find':
        f = find(argv[2]) if len(argv) > 2 else None
        if f:
            print('%s %d' % f)
    elif cmd == 'inject':
        r = inject(argv[2], int(argv[3]) if len(argv) > 3 else 60) if len(argv) > 2 else None
        if r:
            print('%s %d' % r)
        else:
            sys.exit(1)
    elif cmd == 'probe':
        sys.exit(probe('--effect' in argv))
    else:
        print(__doc__)
        sys.exit(2)

if __name__ == '__main__':
    main(sys.argv)
