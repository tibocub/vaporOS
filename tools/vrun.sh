#!/usr/bin/env bash
# tools/vrun.sh <board> flash|term|run -- dispatch to the board's runner.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$(python3 "$DIR/tools/vconfig.py" meta "${1:?board}" runner)"
[ -n "$RUNNER" ] || { echo "board '$1' has no runner" >&2; exit 1; }
exec "$DIR/tools/runners/$RUNNER.sh" "${2:-run}"
