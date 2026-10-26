#!/usr/bin/env python3
"""Run one command on the board and stream its output to a file until it finishes.

usage: rp2040-stream.py LOGFILE 'command' [max_seconds]

Unlike rp2040-term.py (which prints at the end, after an idle timeout), the log can be read
while the command runs. It ends when the marker line `DONE rc=N` appears or after max_seconds.
"""
import os, re, select, sys, termios, time

log, cmd = sys.argv[1], sys.argv[2]
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 600
fd = os.open(__import__("glob").glob("/dev/ttyACM*")[0], os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd)
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)
for _ in range(3):
    os.write(fd, b"\r"); time.sleep(0.3)
line = (cmd + '; echo DONE rc=$?').encode() + b"\r"
for i in range(0, len(line), 32):
    os.write(fd, line[i:i + 32]); time.sleep(0.02)
out = open(log, "wb", buffering=0)
buf = b""
end = time.time() + limit
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        d = os.read(fd, 4096)
        out.write(d)
        buf = (buf + d)[-200:]
        if re.search(rb"\nDONE rc=\d+", buf):
            break
else:
    out.write(b"\nTIMEOUT after %d s\n" % limit)
