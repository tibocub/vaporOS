#!/usr/bin/env bash
# rp2040-flash.sh [uf2] -- copy a UF2 to the board's RPI-RP2 drive. A running board is sent to BOOTSEL
# first: 1200 baud touch (works even when hung), else Ctrl-C + `reboot 1` in the shell. Already in BOOTSEL: just copies.
set -euo pipefail
UF2="${1:-$(dirname "$0")/../../nuttx/nuttx.uf2}"
. "$(dirname "$0")/rp2040-tty.sh"
bootsel_present() { lsblk -rno LABEL | grep -qx RPI-RP2; }
if ! bootsel_present && [ -n "$(tty)" ]; then
  # 1. The 1200 baud touch (patches/nuttx/cdcacm-reset-on-1200bps.patch): handled in the USB interrupt, so it
  #    works whatever the board is doing, hung apps included. Firmware without the patch just ignores it.
  stty -F "$(tty)" 1200 >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6; do bootsel_present && break; sleep 0.5; done
fi
if ! bootsel_present && [ -n "$(tty)" ]; then
  # 2. Older firmware: `reboot 1` typed into the shell. An app that owns the console (a vaporUI program)
  #    never sees it, so Ctrl-C first, which such apps treat as quit.
  timeout 3 python3 -I -c 'import os,sys,time; fd=os.open(sys.argv[1],os.O_RDWR|os.O_NOCTTY); os.write(fd,b"\x03\x03"); time.sleep(1)' "$(tty)" >/dev/null 2>&1 || true
  timeout 10 python3 -I "$(dirname "$0")/rp2040-term.py" -d "$(tty)" -t 0.3 'reboot 1' >/dev/null 2>&1 || true
fi
for _ in $(seq 1 15); do
  DEV=$(lsblk -rno PATH,LABEL | awk '$2=="RPI-RP2"{print $1}' | head -1)
  [ -n "$DEV" ] && break
  sleep 1
done
[ -n "$DEV" ] || { echo "no RPI-RP2 drive found" >&2; exit 1; }
MNT=$(findmnt -n -o TARGET "$DEV" || { udisksctl mount -b "$DEV" >/dev/null; findmnt -n -o TARGET "$DEV"; })
# The bootrom sometimes ignores the first copy; retry until the drive goes away.
for try in 1 2 3; do
  cp "$UF2" "$MNT/" && sync
  sleep 4
  lsblk -rno LABEL | grep -qx RPI-RP2 || { echo "flashed $UF2"; exit 0; }
  MNT=$(findmnt -n -o TARGET "$DEV" || { udisksctl mount -b "$DEV" >/dev/null; findmnt -n -o TARGET "$DEV"; })
done
echo "board still in BOOTSEL after 3 tries" >&2; exit 1
