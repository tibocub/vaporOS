#!/usr/bin/env bash
# scripts/clean.sh -- called by `make -f dev.mk clean`.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$DIR")"
cd "$WORKSPACE"

if [ ! -d nuttx ]; then
  echo "nuttx/ doesn't exist -- nothing to clean." >&2
  exit 0
fi

source "$DIR/scripts/lib.sh"
cd nuttx
[ -f .config ] && distclean_preserving_lua || echo "No .config -- nothing to clean."
