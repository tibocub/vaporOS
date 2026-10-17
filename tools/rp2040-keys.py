#!/usr/bin/env python3
"""rp2040-keys.py 'raw text with \\t \\r escapes' ... -- send keystrokes
verbatim (no Enter appended) and print what comes back, for testing line
editing / tab completion. Each argument is sent, then output is drained."""
import glob, os, select, sys, termios, time
dev = sorted(glob.glob("/dev/ttyACM*"))[-1]
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd); t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)
def drain(idle=1.0):
    out = b""; end = time.time() + idle
    while time.time() < end:
        if select.select([fd], [], [], 0.1)[0]:
            out += os.read(fd, 4096); end = time.time() + idle
    return out.decode(errors="replace")
def send(s):
    for ch in s.encode().decode("unicode_escape").encode("latin1"):
        os.write(fd, bytes([ch])); time.sleep(0.005)
send("\\r\\r\\r"); drain(1.5)
for a in sys.argv[1:]:
    send(a); print(repr(drain(1.2)))
