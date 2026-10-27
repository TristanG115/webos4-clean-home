#!/usr/bin/env python
# cursorclear.py - runs ON the TV (Python 2.7). Copies LG's pointer image folder and swaps every pointer picture for a fully transparent PNG of the same size.
# usage: python cursorclear.py <source dir> <target dir>
# LG's compositor draws the Magic Remote arrow from /usr/share/im/cursorType*.png (arrow, hover, hold, entrance/exit animation, three sizes). cursorclear.sh bind-mounts the
# target folder over the original, so a "shown" pointer is drawn as nothing. Other files in the folder are copied unchanged. Nothing is written to the real folder.
import os, sys, struct, binascii, shutil, subprocess

SIG = '\x89PNG\r\n\x1a\n'

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)

def zlib_zeros(n):
    # this Python has no zlib module: BusyBox gzip compresses n zero bytes, its raw deflate stream is re-wrapped as a zlib stream (adler32 of zeros: A=1, B=n)
    p = subprocess.Popen(['gzip', '-9', '-c'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    gz = p.communicate('\0' * n)[0]
    if gz[:3] != '\x1f\x8b\x08' or ord(gz[3]) != 0:
        raise Exception('unexpected gzip header')
    return '\x78\xda' + gz[10:-8] + struct.pack('>I', ((n % 65521) << 16) | 1)

def clear_png(w, h):
    # RGBA, 8 bit, every pixel 0,0,0,0; each row starts with a filter byte (0)
    return SIG + chunk('IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk('IDAT', zlib_zeros((1 + 4 * w) * h)) + chunk('IEND', '')

def main():
    src, dst = sys.argv[1], sys.argv[2]
    if not os.path.isdir(dst):
        os.makedirs(dst)
    made = copied = 0
    cache = {}
    for name in sorted(os.listdir(src)):
        s, d = os.path.join(src, name), os.path.join(dst, name)
        if not os.path.isfile(s):
            continue
        head = open(s, 'rb').read(24)
        if name.startswith('cursorType') and name.endswith('.png') and head[:8] == SIG and len(head) == 24:
            w, h = struct.unpack('>II', head[16:24])
            if 0 < w <= 512 and 0 < h <= 512:
                if (w, h) not in cache:
                    cache[(w, h)] = clear_png(w, h)
                open(d, 'wb').write(cache[(w, h)])
                made += 1
                continue
        shutil.copyfile(s, d)
        copied += 1
    print('cleared=%d copied=%d sizes=%d' % (made, copied, len(cache)))

main()
