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
#                        #              nxterm_main is for nxterm),
#                        #              running immediately at boot.
#                        #              Milestone 3 of vaporterm.md: a
#                        #              real NSH session on a NuttX pty
#                        #              (openpty()), rendered straight
#                        #              to /dev/fb0 via libvterm -- no
#                        #              NX window, and unlike nxterm's
#                        #              note just below, keyboard input
#                        #              does work here (forwarded from
#                        #              the terminal you launched
#                        #              ./nuttx from into the pty)
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

# NuttX's own readline (at least on the releases/13.0-style codebase --
# confirmed by reading it directly) never echoes plain typed characters
# or the Enter keystroke's own newline in its shared core logic. It's
# built assuming the terminal's own kernel-level local echo handles
# this, which only works when stdin and stdout are the same real
# device -- ours aren't (stdin stays on the host terminal, stdout goes
# to our own /dev/vaporterm0). Confirmed directly: replayed the exact
# byte sequence a real debug log captured through libvterm in
# isolation and it correctly reproduced "no visible typing" / "first
# output line lands on the prompt row". The fix is two missing echo
# calls, applied here since it's NuttX's own source, not ours.
# Each patch below has its OWN idempotency guard, checked and applied
# independently -- NOT one shared guard around all of them. A shared
# guard silently skips every later addition once the first one has
# ever applied to a reused apps/ checkout (setup.sh doesn't re-clone
# apps/ if it already exists), which is exactly what happened with the
# diagnostic marker below: confirmed directly by reproducing it in
# isolation before writing this fix, not assumed.
READLINE_SRC="apps/system/readline/readline_common.c"

# Reset to pristine before patching, every run, rather than layering
# idempotent guards on top of whatever a previous run left behind.
# That approach broke down concretely: a diagnostic patch applied in
# an earlier debugging session stayed in this file indefinitely (only
# a manual `git checkout` would remove it), and once READLINE_EDIT
# got disabled it started firing *alongside* the real echo patch --
# both wrapping and un-wrapping the same character, visible as
# doubled output ("<l>l" instead of "l"). A stateless reset removes
# this entire failure class rather than requiring anyone to remember
# a manual revert step. Best-effort (`|| true`): apps/ might not be a
# git checkout in every environment, and that's not fatal -- the
# patches below still have their own guards for that case.
git -C apps checkout -- system/readline/readline_common.c 2>/dev/null || true

if [ -f "$READLINE_SRC" ] && ! grep -q "buf\[nch++\] = ch;" "$READLINE_SRC" && ! grep -q "RL_PUTC(vtbl, ch);" "$READLINE_SRC"; then
  echo "WARNING: readline_common.c doesn't match the expected pattern for the" >&2
  echo "echo patch (different apps branch?) -- skipping, typing may not be" >&2
  echo "visible in vterm_fb/nxterm. See setup.sh for details." >&2
fi

if [ -f "$READLINE_SRC" ] && grep -q "buf\[nch++\] = ch;" "$READLINE_SRC" && ! grep -q "RL_PUTC(vtbl, ch);" "$READLINE_SRC"; then
  sed -i "/buf\[nch++\] = ch;/a\\          RL_PUTC(vtbl, ch);" "$READLINE_SRC"
  echo "Patched readline_common.c: added missing plain-character echo"
fi

# submit_line(buf, nch) doesn't take vtbl as a parameter, so the echo
# has to go at its call sites (both are inside "if (ch == '\n')"
# blocks that do have vtbl in scope), not inside its body. Caught this
# via a real compile error ("vtbl undeclared") on the first version of
# this patch, not assumed.
if [ -f "$READLINE_SRC" ] && grep -q "return submit_line(buf, nch);" "$READLINE_SRC" && ! grep -q "RL_PUTC(vtbl, '\\\\n'); return submit_line" "$READLINE_SRC"; then
  sed -i "s/return submit_line(buf, nch);/RL_PUTC(vtbl, '\\\\n'); return submit_line(buf, nch);/" "$READLINE_SRC"
  echo "Patched readline_common.c: added missing newline echo"
fi

# The diagnostic character marker that used to be patched in here
# (wrapping every read character in <...>) has served its purpose --
# it's what confirmed characters were reaching RL_GETC correctly even
# though nothing was drawn to screen, which pointed at the echo/redraw
# side rather than input. Removed now that the real cause (readline()'s
# own CONFIG_READLINE_EDIT cursor-editing mode being left on -- see
# above) is identified, rather than something in this codepath.
# If readline_common.c in your apps/ checkout still has the marker
# from a previous run of this script, it'll stay there -- this only
# stops re-applying it, it doesn't undo an existing apply. Revert with:
#   git -C apps checkout -- system/readline/readline_common.c
# then re-run this script to get a clean re-patch.
# These patches modify readline_common.c outside of make's own
# dependency tracking. NuttX's build has repeatedly not detected
# source changes made this way (hit this exact class of stale-binary
# issue multiple times already in this project) -- force removal of
# any already-compiled object for this file so a real rebuild is
# guaranteed, rather than trusting make to notice on its own.
# Scoped to apps/ (the only place this .o can exist) rather than the
# whole workspace: searching from "." here means WORKSPACE, which
# also contains the full nuttx/ checkout and apps/external's own
# self-symlink back to this repo -- a huge, irrelevant tree to walk
# for a single known filename, and under `set -e` any traversal error
# anywhere in it (a permission-denied subdirectory, a dangling
# symlink, anything find can't stat) kills the whole build right here
# with zero output, since stderr was being thrown away. `|| true`
# keeps that failure mode from being fatal even if it recurs.
find apps -name "readline_common.c.*.o" -delete 2>/dev/null || true


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
  # NSH_READLINE only picks readline() over CLE -- it does NOT turn
  # off readline()'s OWN separate cursor-editing mode. READLINE_EDIT
  # is a sibling Kconfig option (default y whenever !DEFAULT_SMALL,
  # which a desktop sim build always is) that switches readline_common.c
  # to an entirely different code path: characters are spliced into
  # the buffer and redraw_tail() is called only if cursor < nch, i.e.
  # only when editing mid-line. A plain character typed at the end of
  # the line increments cursor and nch together, so that condition is
  # never true and the character is never echoed at all -- confirmed
  # directly by reading both branches side by side. That's the actual
  # readline() design: on a real serial console, local echo already
  # happens at the terminal/driver level, so this path doesn't
  # duplicate it. Our device has no such local echo, so we need the
  # OTHER branch (READLINE_EDIT off), which does an unconditional
  # RL_PUTC(vtbl, ch) right after appending -- confirmed present in
  # readline_common.c's #else branch.
  kconfig-tweak --disable CONFIG_READLINE_EDIT
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
  # Same fix nxterm already got, mechanically missing here until now:
  # CLE (NSH's default line editor on a non-DEFAULT_SMALL config, which
  # this is) sends a "hide cursor, move left N, erase to EOL, reprint
  # whole buffer, show cursor" sequence on every keystroke. Confirmed
  # directly -- replayed the exact byte sequence from a real debug log
  # through libvterm in isolation and it reproduced the reported bug
  # exactly (typed text overwriting the prompt from the right, one
  # column further each keystroke). NSH_READLINE avoids this whole
  # class of cursor-position redraw entirely -- backspace-only editing,
  # nothing to get subtly out of sync with our own cursor tracking.
  kconfig-tweak --enable CONFIG_NSH_READLINE
  # See the matching comment in the nxterm branch above: NSH_READLINE
  # alone doesn't disable readline()'s own cursor-editing mode, and
  # that mode only echoes a typed character when redrawing mid-line
  # (cursor < nch) -- never for a plain append at the end of the line,
  # which is the normal case. This is the actual, previously-missing
  # fix for "typed characters invisible" -- not something wrong with
  # our own echo patches below, which target the correct branch but
  # were dead code as long as READLINE_EDIT stayed on.
  kconfig-tweak --disable CONFIG_READLINE_EDIT
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
# docs/vaporshell.md, Milestone 1 step 1 -- deliberately enabled
# unconditionally here (not inside the vterm_fb-only block below), so
# `nsh> vaporshell` is available from a plain sim:nsh build. Iterating
# on the shell itself shouldn't require vterm_fb's graphics/pty setup
# at all until it's actually ready to be wired in as a boot entrypoint.
kconfig-tweak --enable CONFIG_VAPOROS_VAPORSHELL
if [ "$BOARD_CONFIG" = "vterm_fb" ]; then
  # vterm_fb_main.c now runs NSH on a real pty (openpty()) instead of
  # its own bespoke character device -- see the comment block at the
  # top of vterm_fb_main.c for why. PSEUDOTERM also pulls in PIPES and
  # ARCH_HAVE_SERIAL_TERMIOS itself (it selects both), so nothing else
  # needs enabling separately for this.
  kconfig-tweak --enable CONFIG_PSEUDOTERM
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
  # sim:nx11's defconfig sets CONFIG_DISABLE_MOUNTPOINT=y globally
  # (reasonable for a plain graphics demo that never mounts anything)
  # -- but FS_HOSTFS itself depends on !DISABLE_MOUNTPOINT, so it
  # silently couldn't be enabled at all until this is turned off
  # first. Confirmed directly: grepping .config for FS_HOSTFS/
  # SIM_HOSTFS came back completely empty even after enabling them,
  # and mount() failed with ret=-1 as a result.
  kconfig-tweak --disable CONFIG_DISABLE_MOUNTPOINT
  # sim:nx11's defconfig never enables these (only sim:nsh's does, via
  # its own rcS init script) -- needed for our own mount() call in
  # vterm_fb_main.c to have an actual filesystem driver to mount.
  kconfig-tweak --enable CONFIG_FS_HOSTFS
  kconfig-tweak --enable CONFIG_SIM_HOSTFS
  kconfig-tweak --enable CONFIG_VAPOROS_VTERM_FB
fi
make olddefconfig

make -j"$(nproc)"

echo ""
echo "Build complete. Run it with:"
echo "  ${WORKSPACE}/nuttx/nuttx"
