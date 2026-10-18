#!/usr/bin/env bash
# rp2040-try.sh 'nsh cmd' -- run one NSH command on the board, auto-finding the
# tty and waiting out a crash/watchdog reset. Prints the output, then
# whether the board survived.
T=$(dirname "$0")/rp2040-term.py
. "$(dirname "$0")/rp2040-tty.sh"
for i in $(seq 1 20); do [ -n "$(tty)" ] && break; sleep 1; done
timeout 25 python3 -I "$T" -d "$(tty)" -t "${TRY_IDLE:-3}" "$@" 2>&1
sleep 9
echo "--- board: $(tty || echo none)"
