#!/usr/bin/env bash
# rp2040-console.sh -- interactive vaporshell on the RP2040 over USB.
# Waits for the board to show up, sends the three Enters vinit waits for, and
# hands over to picocom. Exit with Ctrl-A Ctrl-X. Re-run after a reboot/replug.
set -euo pipefail

tty() { ls /dev/ttyACM* 2>/dev/null | tail -1; }

if [ -z "$(tty)" ]; then
  echo "waiting for the board (/dev/ttyACM*)..." >&2
  until [ -n "$(tty)" ]; do sleep 0.5; done
  sleep 1
fi
DEV=$(tty)
[ -w "$DEV" ] || { echo "$DEV is not writable: see the udev rule in docs/rp2040.md" >&2; exit 1; }

# vinit ignores input until it has seen three Enters in a row.
( sleep 1; printf '\r\r\r' > "$DEV" ) &

echo "connected to $DEV -- Ctrl-A Ctrl-X to quit" >&2
exec picocom -b 115200 --noreset "$DEV"
