#!/usr/bin/env python3
"""Send commands to the vaporOS RP2040 over its USB CDC-ACM console.

usage: rp2040-term.py [-d /dev/ttyACM0] [-t secs] 'cmd1' 'cmd2' ...

NSH's USB console ignores input until it has seen three Enters in a row,
so those are sent first. Each command is sent in turn and the output printed.
"""
import argparse, os, select, sys, termios, time

ap = argparse.ArgumentParser()
ap.add_argument("-d", default="/dev/ttyACM0")
ap.add_argument("-t", type=float, default=1.5, help="idle seconds per command")
ap.add_argument("cmds", nargs="*")
a = ap.parse_args()

fd = os.open(a.d, os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd)
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)

def drain(idle):
    out = b""; end = time.time() + idle
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            out += os.read(fd, 4096); end = time.time() + idle
    return out.decode(errors="replace")

def send(b):
    # type slowly: bursts right after boot have wedged the USB console
    for ch in b:
        os.write(fd, bytes([ch])); time.sleep(0.004)

for _ in range(3):
    send(b"\r"); time.sleep(0.3)
sys.stdout.write(drain(a.t))
for c in a.cmds:
    send(c.encode() + b"\r")
    sys.stdout.write(drain(a.t))
print()
