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
#   ./setup.sh          # sim:nsh    -- the usual text console
#   ./setup.sh nx11     # sim:nx11   -- opens a real X11 window on your
#                        #              desktop instead (Linux/Mac with
#                        #              XQuartz/Windows with an X server),
#                        #              but only runs NuttX's static
#                        #              nx graphics demo, not a shell
#   ./setup.sh nxterm   # sim:nx11 base, with the demo swapped for a
#                        #              real NSH session rendered into
#                        #              that same X11 window (NxTerm) --
#                        #              see the note on keyboard input
#                        #              below before expecting this to
#                        #              feel like a normal terminal
#   ./setup.sh vterm_fb -- sim:nx11 base again, but vterm_fb itself is
#                        #              the boot entrypoint (like
#                        #              nxterm_main is for nxterm) --
#                        #              not an NSH command. Runs
#                        #              immediately at boot, no shell
#                        #              involved. Milestone 2 of
#                        #              vaporterm.md: static content
#                        #              rendered straight to /dev/fb0,
#                        #              no NX window involved
#
# nxterm isn't an upstream NuttX board config (no sim:nxterm exists) --
# it's assembled here from sim:nx11's base (X11 framebuffer, NX) with
# NuttX's own apps/examples/nxterm swapped in for the static demo app,
# giving a real nsh_consolemain() session -- all our own vaporOS-nuttx
# apps included -- with its *output* rendered into the X11 window.
#
# IMPORTANT, confirmed from NuttX's own nxterm documentation: keyboard
# INPUT is not redirected by default. You still type in the terminal
# you launched ./nuttx from; only the text output appears in the X11
# window. This is a real, documented property of NuttX's own example,
# not something broken in this setup. True in-window typing needs
# CONFIG_NXTERM_NXKBDIN plus real X11 keyboard-event forwarding, which
# is a separate, less-certain undertaking -- not attempted here.
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
    nx11|nxterm|vterm_fb|lvgl_fb)
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

if [ "$BOARD_CONFIG" = "nxterm" ]; then
  ./tools/configure.sh sim:nx11
  # Swap NuttX's static graphics demo for a real NSH session rendered
  # into the same X11 window -- apps/examples/nxterm's own main()
  # calls nsh_consolemain() internally, so this is genuinely full NSH,
  # not a toy. Confirmed via a clean build to LD: nuttx with exactly
  # this combination.
  kconfig-tweak --disable CONFIG_EXAMPLES_NX
  kconfig-tweak --enable CONFIG_NXTERM
  kconfig-tweak --enable CONFIG_EXAMPLES_NXTERM
  kconfig-tweak --set-str CONFIG_INIT_ENTRYPOINT nxterm_main
  # NxTerm's own VT100 support is genuinely minimal -- its source
  # comment says so directly: "a placeholder for a future, more
  # complete VT100 emulation." It recognizes exactly one escape
  # sequence (erase-to-end-of-line). NSH's default line editor on a
  # non-DEFAULT_SMALL config is CLE, which assumes a real VT100
  # terminal and uses cursor hide/show + full-line-clear sequences
  # for smooth redraws -- confirmed (via grep on the compiled objects)
  # that those sequences come from cle.c specifically, not from
  # readline. Anything NxTerm doesn't recognize gets dumped back out
  # as literal text, which is exactly the garbled output this
  # produces. NSH_READLINE is NuttX's own "minimal readline()" --
  # backspace-only editing, no cursor tricks -- and is the documented
  # right choice for a limited-VT100 terminal. This is a choice
  # option, so enabling it deselects CLE automatically.
  kconfig-tweak --enable CONFIG_NSH_READLINE
elif [ "$BOARD_CONFIG" = "vterm_fb" ]; then
  ./tools/configure.sh sim:nx11
  # vterm_fb runs directly as the boot entrypoint -- same pattern as
  # nxterm_main above, not an NSH command. This is deliberate, not
  # just simpler: making it an NSH command (nsh_main as entrypoint,
  # vterm_fb registered as a builtin to run by hand) hit a real,
  # reproducible NuttX build-system bug where the app would compile
  # and link cleanly but never actually get registered -- confirmed
  # across multiple genuinely fresh clones, confirmed to affect other
  # apps too under the same nsh_main/SYSTEM_NSH combination, and never
  # fully root-caused despite real effort. Using vterm_fb itself as
  # INIT_ENTRYPOINT sidesteps that registration mechanism entirely and
  # has been reliable every time it's been tried.
  kconfig-tweak --disable CONFIG_EXAMPLES_NX
  kconfig-tweak --set-str CONFIG_INIT_ENTRYPOINT vterm_fb_main
else
  ./tools/configure.sh sim:$BOARD_CONFIG
fi

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
# Milestone-1 proof for docs/vaporterm.md -- not a real vaporOS command,
# but it needs to build so `vtermtest` stays available without a manual
# kconfig-tweak every time this script runs.
kconfig-tweak --enable CONFIG_VAPOROS_VTERMTEST
if [ "$BOARD_CONFIG" = "vterm_fb" ]; then
  kconfig-tweak --enable CONFIG_DRIVERS_VIDEO
  kconfig-tweak --enable CONFIG_VIDEO_FB
  # SIM_FRAMEBUFFER is a choice option (vs. SIM_LCDDRIVER) nested
  # inside SIM_X11FB -- it's what actually pulls in sim_framebuffer.c,
  # the file with the sim_x11loop() symbol nx11/nxterm never needed
  # but a raw /dev/fb0 consumer does. Missing this produces a real
  # link-time "undefined reference to sim_x11loop", not a config
  # warning -- confirmed by hitting it directly before adding this.
  kconfig-tweak --enable CONFIG_SIM_FRAMEBUFFER
  kconfig-tweak --enable CONFIG_NXFONTS
  # NXFONT_SANS23X27 is a proportional font -- forcing it into a fixed
  # per-cell grid (every cell sized for the font's *widest* glyph)
  # left narrow characters looking like they had gaps around them.
  # X11_MISC_FIXED_10X20 is a genuine monospace font (the classic X11
  # "fixed" family), so every glyph actually fills its cell -- no
  # forcing needed. Also just plain bigger and more legible.
  kconfig-tweak --enable CONFIG_NXFONT_X11_MISC_FIXED_10X20
  # Default sim display is 320x240 -- tiny on a real desktop. 800x600
  # at 10x20 cells works out to exactly 80x30, the classic terminal
  # size -- not a coincidence, chosen because it lines up exactly.
  kconfig-tweak --set-val CONFIG_SIM_FBWIDTH 800
  kconfig-tweak --set-val CONFIG_SIM_FBHEIGHT 600
  # nx11's own defconfig doesn't enable this (a graphics demo has no
  # reason to shut the board down) -- needed both for "poweroff" to
  # exist as an NSH command at all, and for our own boardctl() call
  # after nsh_consolemain() returns to do anything.
  kconfig-tweak --enable CONFIG_BOARDCTL_POWEROFF
  kconfig-tweak --enable CONFIG_VAPOROS_VTERM_FB
fi
make olddefconfig

make -j"$(nproc)"

echo ""
echo "Build complete. Run it with:"
echo "  ${WORKSPACE}/nuttx/nuttx"
