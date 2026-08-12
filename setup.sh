#!/usr/bin/env bash
#
# vaporOS-nuttx/setup.sh
#
# Sets up a NuttX workspace next to this repo, wires this repo in as
# apps/external (see NuttX's apps/README.md, "Adding Applications
# Outside the Apps Directory"), and builds the sim:nsh target so you
# can boot into a real NuttX shell with zero real hardware.
#
# Layout after running this (matches NuttX's own expected workspace
# shape -- nuttx/ and apps/ as siblings):
#
#   <parent-dir>/
#     nuttx/                 <- upstream NuttX kernel, pinned below
#     apps/                  <- upstream NuttX apps, pinned below
#       external -> ../../vaporOS-nuttx   (symlink, this repo)
#     vaporOS-nuttx/         <- this repo
#
# Pinned to the exact commits this was last validated against.
# Bump these deliberately, not accidentally -- re-run this script
# after bumping to confirm the build still succeeds.

set -euo pipefail

NUTTX_COMMIT="a0fcbb7957e916d03e346de9bdf5d1be2dd4ccd0"
APPS_COMMIT="569d8f31dbd7934a7e20606db311fcfb1e86b59d"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(dirname "${SCRIPT_DIR}")"

cd "${WORKSPACE}"

if [ ! -d nuttx ]; then
  echo "Cloning nuttx..."
  git clone https://github.com/apache/nuttx.git
  git -C nuttx checkout "${NUTTX_COMMIT}"
fi

if [ ! -d apps ]; then
  echo "Cloning apps..."
  git clone https://github.com/apache/nuttx-apps.git apps
  git -C apps checkout "${APPS_COMMIT}"
fi

if [ ! -e apps/external ]; then
  echo "Linking apps/external -> vaporOS-nuttx"
  ln -s "${SCRIPT_DIR}" apps/external
fi

# Build-time tools NuttX needs beyond gcc/make. If any of these are
# already present this is a no-op; if you're not on apt, install the
# equivalents for your platform (kconfig-frontends, genromfs, xxd).
if command -v apt-get >/dev/null 2>&1; then
  MISSING=""
  command -v kconfig-tweak >/dev/null 2>&1 || MISSING="$MISSING kconfig-frontends"
  command -v genromfs      >/dev/null 2>&1 || MISSING="$MISSING genromfs"
  command -v xxd           >/dev/null 2>&1 || MISSING="$MISSING xxd"
  if [ -n "$MISSING" ]; then
    echo "Installing missing build tools:$MISSING"
    sudo apt-get update -qq
    sudo apt-get install -y $MISSING
  fi
fi

cd nuttx
./tools/configure.sh sim:nsh

# Our own apps default to "n" in their Kconfig (matching NuttX convention
# for optional components) -- enable them explicitly rather than relying
# on the board defconfig to know about a repo it's never seen. Same for
# Lua: the in-tree interpreter itself needs no extra downloads, just the
# option flipped on. (The optional Lua *modules* -- cjson, lfs, luasyslog,
# luv -- each fetch their own tarball at build time and are left off here
# deliberately, to keep this script's only dependency on the network the
# initial git clones.)
kconfig-tweak --enable CONFIG_VAPOROS_VHELLO
kconfig-tweak --enable CONFIG_VAPOROS_PORTABLE_WC
kconfig-tweak --enable CONFIG_INTERPRETERS_LUA
kconfig-tweak --enable CONFIG_VAPOROS_VLUA
kconfig-tweak --enable CONFIG_VAPOROS_PORTABLE_CAT
make olddefconfig

make -j"$(nproc)"

echo ""
echo "Build complete. Run it with:"
echo "  ${WORKSPACE}/nuttx/nuttx"
