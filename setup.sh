#!/usr/bin/env bash
#
# vaporOS-nuttx/setup.sh [board-config]
#
# Sets up a NuttX workspace next to this repo, wires this repo in as
# apps/external (see NuttX's apps/README.md, "Adding Applications
# Outside the Apps Directory"), and builds the given sim:<board-config>
# target so you can boot into a real NuttX shell with zero real hardware.
#
# board-config defaults to "nsh" (the everyday text-console target).
# Each board config is a genuinely separate build -- NuttX doesn't have
# "one image, graphics toggle at runtime" -- so building the graphical
# target is a real second build, not a flag on the first one:
#
#   ./setup.sh          # sim:nsh  -- the usual text console
#   ./setup.sh nx11     # sim:nx11 -- opens a real X11 window on your
#                        #            desktop instead (Linux/Mac with
#                        #            XQuartz/Windows with an X server)
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

BOARD_CONFIG="${1:-nsh}"

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
  # X11 dev headers, only needed for graphical (nx11-style) targets --
  # confirmed required (Xlib.h, link libs) when actually building one.
  case "$BOARD_CONFIG" in
    nx11|lvgl_fb)
      dpkg -s libx11-dev >/dev/null 2>&1 || MISSING="$MISSING libx11-dev"
      ;;
  esac
  if [ -n "$MISSING" ]; then
    echo "Installing missing build tools:$MISSING"
    sudo apt-get update -qq
    sudo apt-get install -y $MISSING
  fi
fi

cd nuttx

# If this workspace was configured before (e.g. before a new app
# directory like portable_wc/ existed, or for a different board
# config), the Kconfig aggregation under apps/external/ won't have
# picked it up -- configure.sh alone doesn't force that rescan.
# distclean guarantees a fresh one. Harmless/no-op on a truly first
# run, since there's nothing to clean yet.
if [ -f .config ]; then
  echo "Existing configuration found -- running distclean so new apps are picked up"
  make distclean
fi

./tools/configure.sh sim:$BOARD_CONFIG

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
# INTERPRETERS_LUA (via its CORELIBS suboption) does `select SYSTEM_SYSTEM`,
# which itself `depends on NSH_LIBRARY` -- and Kconfig's `select` bypasses
# `depends on` checks rather than satisfying them. On a board config that
# doesn't already enable NSH_LIBRARY for its own reasons (nx11 is the one
# we've hit; likely any non-nsh config), that mismatch leaves apps/system/
# system.c compiling without a real declaration of waitpid() in scope,
# producing a confusing "implicit declaration" error that has nothing to
# do with our own code. Enabling it directly avoids relying on some other
# option happening to pull it in first.
kconfig-tweak --enable CONFIG_NSH_LIBRARY
# nsh_script.c calls readline_fd() unconditionally, but its prototype
# in apps/include/system/readline.h is wrapped entirely in #ifdef
# CONFIG_SYSTEM_READLINE -- while the .c file implementing it still
# gets built regardless. Same shape of gap as NSH_LIBRARY above: an
# implementation that exists without the config flag needed to see its
# own declaration. Confirmed via a full clean build to LD: nuttx with
# just this one flag added; whether your compiler treats the resulting
# implicit-declaration as a warning or a hard error depends on its
# version (GCC 14+ defaults to erroring on this), so this may build
# fine for one person and fail for another without it.
kconfig-tweak --enable CONFIG_SYSTEM_READLINE
kconfig-tweak --enable CONFIG_VAPOROS_VLUA
kconfig-tweak --enable CONFIG_VAPOROS_PORTABLE_CAT
# NuttX's own tiny vi work-alike (apps/system/vi) -- no external
# dependency (termcurses is another in-tree NuttX module), no reason
# to port kilo/mle when this already exists and already fits the same
# embedded constraints they'd target.
kconfig-tweak --enable CONFIG_SYSTEM_VI
make olddefconfig

make -j"$(nproc)"

echo ""
echo "Build complete. Run it with:"
echo "  ${WORKSPACE}/nuttx/nuttx"
