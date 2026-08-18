#!/usr/bin/env bash
# vaporOS-nuttx/setup.sh -- one-time environment setup (Linux/macOS).
# Clones nuttx+apps, wires this repo in as apps/external. Does not
# build -- see dev.mk (`make -f dev.mk build`).
set -euo pipefail

NUTTX_COMMIT="a0fcbb7957e916d03e346de9bdf5d1be2dd4ccd0"
APPS_COMMIT="569d8f31dbd7934a7e20606db311fcfb1e86b59d"

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

[ -e apps/external ] || ln -s "$DIR" apps/external

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
