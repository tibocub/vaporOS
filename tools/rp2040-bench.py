#!/usr/bin/env python3
"""rp2040-bench.py [--setup N] -- how vaporshell's line editor performs on the board.

Times, over the USB console, the delay from a key to the last byte of the redraw (the USB
round trip, about 1.7 ms, is in every number), and reports memory: `free` before/after and
the stack the shell has used (`ps`). Needs a running board; the board runs the shell.

  --setup N   first create N empty files in /flash/t (a directory on littlefs to complete in)
"""
import glob, os, re, select, statistics, sys, termios, time

dev = os.path.realpath(glob.glob("/dev/serial/by-id/usb-NuttX_CDC_ACM*")[0])
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
t = termios.tcgetattr(fd); t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; t[4] = t[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, t)


def drain(idle=0.3, limit=30):
    out, first, last = b"", None, None
    start = quiet = time.time()
    while time.time() - start < limit:
        if select.select([fd], [], [], 0.002)[0]:
            now = time.time(); out += os.read(fd, 65536)
            first = first or now; last = quiet = now
        elif time.time() - quiet > idle:
            break
    return out, first, last


def timed(data, idle=0.3):
    drain(0.1); t0 = time.time(); os.write(fd, data)
    out, first, last = drain(idle)
    return out, (first - t0) * 1000 if first else None, (last - t0) * 1000 if last else None


def clean(b): return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", b.decode(errors="replace")).replace("\r", "")


def memory():
    for _ in range(4):
        out, *_ = timed(b"free\r", 0.8)
        for line in clean(out).splitlines():
            p = line.split()
            if len(p) >= 8 and p[0].isdigit() and p[-1] == "Umem":
                return dict(zip(["total", "used", "free", "maxused", "maxfree"], map(int, p[:5])))


def stack():
    for _ in range(4):
        out, *_ = timed(b"ps\r", 0.8)
        for line in clean(out).splitlines():
            p = line.split()
            if p and p[-1] == "vaporshell" and p[0].isdigit():
                return int(p[-3]), int(p[-2])         # size, used


def measure(label, pre, key, n=5, idle=1.0):
    vals = []
    for _ in range(n):
        if pre: os.write(fd, pre); drain(0.3)
        _, f, l = timed(key, idle); vals.append(l); os.write(fd, b"\x15"); drain(0.3)
    ok = [v for v in vals if v is not None]
    print("  %-50s %8s ms" % (label, "%.1f" % statistics.median(ok) if ok else "n/a"))


os.write(fd, b"\r\r\r"); drain(1)
if "--setup" in sys.argv:
    n = int(sys.argv[sys.argv.index("--setup") + 1])
    os.write(fd, b"mkdir /flash/t; cd /flash/t; i=1; while [ $i -le %d ]; do touch file-number-$i; i=$((i+1)); done; cd /\r" % n)
    drain(2, limit=600)
m0, s0 = memory(), stack()
print("memory at start: %s\nshell stack (size, used): %s" % (m0, s0))
print("key redraw")
measure("one key on an empty line", b"", b"x", 8)
measure("one key after 60 characters", b"echo " + b"a" * 55, b"x")
measure("one key after 5 words that are /bin /proc paths", b"ls /bin /proc /bin /proc /bin ", b"x")
measure("one key after 5 words that are /flash paths", b"ls /flash /flash /flash /flash /flash ", b"x")
measure("one key after 5 words, /flash, a second time (memo)", b"ls /flash /flash /flash /flash /flash ", b"y")
print("Tab")
measure("command (ec -> echo)", b"ec", b"\t")
measure("tbx option (ls --co -> --color)", b"ls --co", b"\t")
measure("variable ($HO -> $HOME)", b"echo $HO", b"\t")
measure("nothing matches (three passes)", b"zzzqq", b"\t")
measure("loose match (cd FLA -> flash)", b"cd FLA", b"\t")
measure("unique path, / (cd /fl -> /flash/)", b"cd /fl", b"\t")
measure("menu of /bin, opening it", b"ls /bin/", b"\t")
measure("menu of /proc, opening it", b"ls /proc/", b"\t")
if True:
    measure("40-file littlefs dir, menu (ls /flash/t/fi)", b"ls /flash/t/fi", b"\t", 3, 4.0)
    measure("same dir, unique (ls /flash/t/file-number-40)", b"ls /flash/t/file-number-4", b"0\t", 3, 4.0)
vals = []
for _ in range(5):
    os.write(fd, b"ls /bin/\t"); drain(0.4); _, f, l = timed(b"\t"); vals.append(l); os.write(fd, b"\x1b\x15"); drain(0.3)
print("  %-50s %8.1f ms" % ("second Tab: choose the first menu entry", statistics.median(vals)))
m1, s1 = memory(), stack()
print("memory after: %s\nshell stack (size, used): %s" % (m1, s1))
print("heap in use changed by %+d bytes; most ever in use: %d -> %d" % (m1["used"] - m0["used"], m0["maxused"], m1["maxused"]))
