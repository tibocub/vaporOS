#!/usr/bin/env bash
# scripts/gen-compile-commands.sh -- generates compile_commands.json
# (via bear) for clangd/IDE support, in the one place every sibling
# repo's own .clangd already expects it: nuttx/, next to this repo.
#
# Assumes a working nuttx/.config already exists (i.e. `make -f
# dev.mk build` has already succeeded at least once) -- this
# regenerates object files under that same, already-working
# configuration, it doesn't reconfigure anything.
#
# Why this needs a real, dedicated script rather than "just run bear
# yourself" (confirmed directly, the hard way, building this project
# fresh and inspecting the real result):
#
# - bear only records compiler invocations that actually run during
#   the wrapped command -- any object file already up to date from a
#   prior build is silently skipped by make, so it never shows up in
#   compile_commands.json at all. Confirmed directly: an incremental
#   build produced a compile_commands.json with a *single* vaporshell
#   entry, missing 13 of its own 14 source files, simply because they
#   hadn't needed rebuilding.
#
# - each app's own .o files live inside that app's own source
#   directory (e.g. vaporshell/*.o), not under nuttx/ -- this is
#   nuttx-apps' own Application.mk convention, not something specific
#   to vaporOS. That means every one of vaporshell/, vaporOS-coreutils/,
#   and vaporOS-nuttx/'s own apps needs its object files gone too, not
#   just nuttx/'s own, for a truly complete capture.
#
# Deliberately not going through scripts/build.sh's own distclean
# step for this: that's the right call for a real, from-scratch
# build, but heavier than needed here, when the goal is just "recompile
# everything under the config that's already working" -- and
# confirmed directly, running this via build.sh's own distclean can
# stall in some environments where the apps/external symlink
# structure isn't exactly what it expects (a difference in the
# sandbox used to write this script, not this project's own fault --
# but a real explicit-clean approach here sidesteps it either way,
# rather than depending on distclean's own, much broader behavior).
#
# See docs/ide-setup.md for the full picture, including the one,
# unavoidable editor-side setting (clangd's own --query-driver) this
# script's own output still depends on.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$DIR")"

if ! command -v bear >/dev/null 2>&1; then
  echo "bear not found -- install it first (e.g. 'apt install bear')." >&2
  exit 1
fi

cd "$WORKSPACE"

if [ ! -e nuttx-apps/external ]; then
  echo "nuttx-apps/external missing -- run setup.sh (or setup.ps1) first." >&2
  exit 1
fi

if [ ! -f nuttx/.config ]; then
  echo "nuttx/.config missing -- run a real build first" >&2
  echo "('make -f dev.mk build sim:nsh' in $DIR), then retry." >&2
  exit 1
fi

echo "Generating compile_commands.json (recompiling everything under" >&2
echo "nuttx/'s own, already-configured .config -- bear only captures" >&2
echo "commands that actually run, so an incremental build would" >&2
echo "silently produce an incomplete database)." >&2

find nuttx nuttx-apps vaporOS-nuttx vaporOS-coreutils vaporshell \
  -name '*.o' -delete 2>/dev/null || true

cd nuttx
bear --output compile_commands.json -- make

echo "Wrote nuttx/compile_commands.json. Each sibling repo's own" >&2
echo ".clangd already points here -- see docs/ide-setup.md for the" >&2
echo "remaining, one-time editor setting clangd itself still needs." >&2
