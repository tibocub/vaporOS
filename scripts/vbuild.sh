#!/usr/bin/env bash
# scripts/vbuild.sh <board> [--configure-only] -- build vaporOS for a board.
#
# Everything board-specific comes from boards/<board>/board.conf (see
# boards/README.md and tools/vconfig.py): the base NuttX configuration, the
# features, the hardware descriptors, the host toolchain and the patches the
# board needs. This script holds no per-target knowledge.
#
#   --configure-only   stop after producing nuttx/.config (fast; used to check
#                      that a board resolves and to compare configurations)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$DIR")"
VCONFIG="$DIR/tools/vconfig.py"

BOARD_ARG="${1:-sim-nsh}"
CONFIGURE_ONLY=0
[ "${2:-}" = "--configure-only" ] && CONFIGURE_ONLY=1

BOARD="$(python3 "$VCONFIG" meta "$BOARD_ARG" name)" || exit 1
[ -n "$BOARD" ] || { echo "unknown board '$BOARD_ARG' (try: make -f dev.mk boards)" >&2; exit 1; }

cd "$WORKSPACE"
if [ ! -e nuttx-apps/external ]; then
  echo "nuttx-apps/external missing -- run setup.sh first." >&2
  exit 1
fi

# Host toolchain for this board (PATH additions, env vars), then check it.
eval "$(python3 "$VCONFIG" env "$BOARD")"
for tool in $VCONFIG_REQUIRE; do
  command -v "$tool" >/dev/null || {
    echo "$BOARD needs '$tool' on PATH (see boards/$BOARD/board.conf [tools] for where it looks)" >&2
    exit 1
  }
done

# The board's NuttX changes must be in the checkouts (idempotent).
# shellcheck disable=SC2046
"$DIR/tools/apply-patches.sh" $(python3 "$VCONFIG" patches "$BOARD") >/dev/null \
  || { echo "a patch required by $BOARD does not apply; run tools/apply-patches.sh" >&2; exit 1; }

source "$DIR/scripts/lib.sh"
cd nuttx
[ -f .config ] && distclean_preserving_lua
clean_stale_objects

./tools/configure.sh "$(python3 "$VCONFIG" meta "$BOARD" nuttx_config)"
python3 "$VCONFIG" apply "$BOARD" .
make olddefconfig

# Kconfig silently drops options with unmet dependencies; make that loud.
if ! python3 "$VCONFIG" verify "$BOARD" . ; then
  [ "${VCONFIG_LENIENT:-0}" = 1 ] || { echo "Set VCONFIG_LENIENT=1 to build anyway." >&2; exit 1; }
fi

if [ "$CONFIGURE_ONLY" = 1 ]; then
  echo "Configured $BOARD (nuttx/.config)."
  exit 0
fi

make -j"$(nproc)"
echo "Done: $BOARD. Next: make -f dev.mk run BOARD=$BOARD"
