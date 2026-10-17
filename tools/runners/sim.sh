#!/usr/bin/env bash
# runner: the NuttX simulator, a normal host process.   sim.sh flash|term|run
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
case "${1:-run}" in
  flash) echo "nothing to flash: the simulator is a host executable" ;;
  term|run) exec "$(dirname "$DIR")/nuttx/nuttx" ;;
  *) echo "usage: sim.sh flash|term|run" >&2; exit 2 ;;
esac
