#!/usr/bin/env bash
# rp2040-flash.sh [uf2] -- copy a UF2 to the board's RPI-RP2 drive. If the
# board is running a vaporOS build, `reboot 1` is sent first to enter BOOTSEL.
set -euo pipefail
UF2="${1:-$(dirname "$0")/../../nuttx/nuttx.uf2}"
. "$(dirname "$0")/rp2040-tty.sh"
if [ -n "$(tty)" ]; then
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
