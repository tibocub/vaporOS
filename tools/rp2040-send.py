#!/usr/bin/env python3
"""Send files to the board fast: tools/rp2040-send.py FILE... -> /flash/<basename>.

Runs `vlua /flash/recv.lua` (tools/rp2040-recv.lua, put there once with rp2040-put.py) and streams hex
lines to it: about 2 KB/s, 50 KB in 30 s (rp2040-put.py is ~100 B/s). Checks a byte sum per file.
Needs an idle board with no other helper holding the port."""
import glob, os, select, sys, termios, time
files = sys.argv[1:]
fd = os.open(__import__("glob").glob("/dev/ttyACM*")[0], os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd); t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)
buf = b""
def pump(t=0.05):
    global buf
    r, _, _ = select.select([fd], [], [], t)
    if r: buf += os.read(fd, 8192)
def put(b):
    for i in range(0, len(b), 64):
        os.write(fd, b[i:i+64]); time.sleep(0.012); pump(0)
for _ in range(3): os.write(fd, b"\r"); time.sleep(0.3)
put(b"cd /flash; vlua recv.lua\r"); time.sleep(2); pump(0.5)
for f in files:
    data = open(f, "rb").read(); name = "/flash/" + os.path.basename(f)
    s = sum(data) % 65536
    buf = b""
    put(("F %s %d\r" % (name, len(data))).encode())
    for i in range(0, len(data), 100): put(data[i:i+100].hex().encode() + b"\r")
    end = time.time() + 20
    while time.time() < end and (b"ACK %s %d" % (name.encode(), s)) not in buf: pump(0.1)
    print(name, "ok" if (b"ACK %s %d" % (name.encode(), s)) in buf else "FAILED", flush=True)
put(b"Q\r"); time.sleep(1); pump(0.5)
