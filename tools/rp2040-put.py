#!/usr/bin/env python3
"""Copy a host file onto the board's filesystem over the USB console.

usage: rp2040-put.py [-d /dev/ttyACM0] LOCAL REMOTE [LOCAL REMOTE ...]

Sends the file as hex through `xxd -r -p >> REMOTE`, one command per chunk, waits for each
command to finish (it echoes a computed marker the typed text cannot contain) and checks the
md5sum at the end. Slow (a few KB/s) but needs nothing on the board beyond tbx.
"""
import argparse, hashlib, os, re, select, sys, termios, time

CHUNK = 96      # bytes per command (192 hex characters on the line)

ap = argparse.ArgumentParser()
ap.add_argument("-d", default="/dev/ttyACM0")
ap.add_argument("files", nargs="+")
a = ap.parse_args()
if len(a.files) % 2:
    sys.exit("need LOCAL REMOTE pairs")

fd = os.open(a.d, os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd)
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)


class Lost(Exception):
    pass


def read_until(pat, timeout):
    buf = b""
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            buf += os.read(fd, 4096)
            m = re.search(pat, buf)
            if m:
                return buf, m
    raise Lost(buf[-200:])


n = 0
def run(cmd):
    """Run one command, return what it printed after the marker."""
    global n
    n += 1
    os.write(fd, b"\x15")  # ^U: clear any half-typed line
    marker = 7 * n + 100000
    line = ("%s; echo M$((7*%d+100000)):" % (cmd, n)).encode()
    for i in range(0, len(line), 32):
        os.write(fd, line[i:i + 32]); time.sleep(0.02)
    os.write(fd, b"\r")
    buf, m = read_until(rb"\nM%d:" % marker, 20)
    return buf


for _ in range(3):
    os.write(fd, b"\r"); time.sleep(0.3)
run("true")
for local, remote in zip(a.files[::2], a.files[1::2]):
    data = open(local, "rb").read()
    run("rm -f %s" % remote)
    for i in range(0, len(data), CHUNK):
        for attempt in range(6):
            try:
                run("echo %s | xxd -r -p >> %s" % (data[i:i + CHUNK].hex(), remote))
                break
            except Lost:
                # a garbled line may or may not have appended: resync, cut back to the last good offset
                print("%s: retry at %d" % (remote, i), file=sys.stderr)
                time.sleep(1)
                os.write(fd, b"\x03\r\r"); time.sleep(1)
                termios.tcflush(fd, termios.TCIFLUSH)
                try:
                    run("truncate -s %d %s" % (i, remote))
                except Lost:
                    pass
        else:
            sys.exit("giving up at offset %d" % i)
        if i % (CHUNK * 50) == 0:
            print("%s %d/%d" % (remote, i, len(data)), file=sys.stderr)
    out = run("md5sum %s" % remote).decode(errors="replace")
    ok = hashlib.md5(data).hexdigest() in out
    print("%s: %s" % (remote, "ok" if ok else "MD5 MISMATCH"))
    if not ok:
        sys.exit(1)
