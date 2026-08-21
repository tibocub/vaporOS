#!/usr/bin/env bash
# vaporOS-nuttx/setup.sh -- one-time environment setup (Linux/macOS).
# Clones nuttx+apps, wires this repo in as apps/external. Does not
# build -- see dev.mk (`make -f dev.mk build`).
set -euo pipefail

NUTTX_COMMIT="a0fcbb7957e916d03e346de9bdf5d1be2dd4ccd0"
APPS_COMMIT="569d8f31dbd7934a7e20606db311fcfb1e86b59d"
COREUTILS_COMMIT="2e5c5bc5d66ac272f149c2d175adfcecbd4ed5d9"
VAPORSHELL_COMMIT="26c7f94674eaa8f59f8c9f995c1b6d20331459fa"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$DIR")"

if [ ! -d nuttx ]; then
  git clone https://github.com/apache/nuttx.git
  git -C nuttx checkout "$NUTTX_COMMIT"
fi

if [ ! -d apps ]; then
  git clone https://github.com/apache/nuttx-apps.git apps
  git -C apps checkout "$APPS_COMMIT"
fi

# vaporOS-coreutils and vaporshell: both split into their own repos
# once each grew past what "part of vaporOS-nuttx" meant -- coreutils
# once it became a real toybox/NSH fork with its own commands, not
# just a compatibility port; vaporshell so it can be independent of
# any specific command set, usable by other NuttX projects with a
# different one entirely. Both cloned as siblings here, same pattern
# as nuttx/apps above, and referenced via symlinks rather than
# restructuring apps/external itself -- keeps every existing
# $(APPDIR)/external/<name> path reference (in each repo's own
# Makefile) working unchanged, since that logical path still resolves
# correctly through the extra symlink hop.
if [ ! -d vaporOS-coreutils ]; then
  git clone https://github.com/tibocub/vaporOS-coreutils.git
  git -C vaporOS-coreutils checkout "$COREUTILS_COMMIT"
fi

if [ ! -d vaporshell ]; then
  git clone https://github.com/tibocub/vaporshell.git
  git -C vaporshell checkout "$VAPORSHELL_COMMIT"
fi

[ -e apps/external ] || ln -s "$DIR" apps/external
[ -e "$DIR/toybox" ] || ln -s ../vaporOS-coreutils "$DIR/toybox"
[ -e "$DIR/vaporshell" ] || ln -s ../vaporshell "$DIR/vaporshell"

if command -v apt-get >/dev/null 2>&1; then
  MISSING=""
  command -v kconfig-tweak >/dev/null || MISSING="$MISSING kconfig-frontends"
  command -v genromfs >/dev/null || MISSING="$MISSING genromfs"
  command -v xxd >/dev/null || MISSING="$MISSING xxd"
  dpkg -s libx11-dev >/dev/null 2>&1 || MISSING="$MISSING libx11-dev"
  [ -n "$MISSING" ] && { sudo apt-get update -qq; sudo apt-get install -y $MISSING; }
else
  echo "No apt-get -- install kconfig-frontends, genromfs, xxd, libx11-dev manually." >&2
fi

echo "Done. cd $DIR && make -f dev.mk build"
