#!/usr/bin/env bash
# runner: RP2040 boards with a USB console and the UF2 bootloader.
#   rp2040-uf2.sh flash   reboot into BOOTSEL (if running) and copy the UF2
#   rp2040-uf2.sh term    open the serial console (picocom)
#   rp2040-uf2.sh run     flash, then term
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "${1:-run}" in
  flash) exec "$DIR/tools/rp2040-flash.sh" ;;
  term)  exec "$DIR/tools/rp2040-console.sh" ;;
  run)   "$DIR/tools/rp2040-flash.sh" && exec "$DIR/tools/rp2040-console.sh" ;;
  *) echo "usage: rp2040-uf2.sh flash|term|run" >&2; exit 2 ;;
esac
