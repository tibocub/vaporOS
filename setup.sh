#!/usr/bin/env bash
# vaporOS-nuttx/setup.sh -- one-time environment setup (Linux/macOS).
# Clones nuttx+nuttx-apps, wires this repo in as nuttx-apps/external.
# Does not build -- see dev.mk (`make -f dev.mk build`).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$DIR")"

if [ ! -d nuttx ]; then
  git clone https://github.com/apache/nuttx.git
  git -C nuttx checkout "releases/13.0"
fi

if [ ! -d nuttx-apps ]; then
  git clone https://github.com/apache/nuttx-apps.git
  # Kept in lockstep with nuttx's own releases/13.0 above -- nuttx and
  # nuttx-apps are versioned as a matched pair upstream (both carry
  # the same "nuttx-13.0.0"-style tags/branches) specifically because
  # apps code relies on kernel APIs that move between releases;
  # letting nuttx-apps float to its own latest/default branch while
  # nuttx stays pinned is exactly what caused a real, confirmed build
  # break here (nuttx-apps' own testing/ostest referencing
  # atomic_add(), an API added to nuttx after this release branch was
  # cut -- not present in nuttx/include/nuttx/atomic.h at all on
  # releases/13.0, confirmed directly).
  git -C nuttx-apps checkout "releases/13.0"

  # readline-history-ctrlpn.patch (below) does NOT apply here: it was
  # written against a much newer nuttx-apps commit than
  # releases/13.0's own readline_common.c, which is a substantially
  # more primitive implementation -- confirmed directly,
  # CONFIG_READLINE_EDIT_EMACS (the emacs-style editing
  # infrastructure the patch's own Ctrl+P/Ctrl+N navigation depends
  # on) doesn't exist anywhere in this version at all, not just a
  # different line number for the same feature. Re-porting the
  # history-persistence/navigation feature onto this real,
  # structurally different base is real, separate work, not done yet
  # -- applying with || true and a clear warning here rather than
  # letting one optional, non-blocking feature patch halt this whole
  # script.
  git -C nuttx-apps apply "$DIR/patches/nuttx-apps/readline-history-ctrlpn.patch" \
    || echo "WARNING: readline-history-ctrlpn.patch did not apply (a known," \
            "real gap against releases/13.0 -- see this script's own comment" \
            "above). vaporshell/NSH readline itself still works fine without" \
            "it; only history persistence/Ctrl+P/Ctrl+N navigation are missing."
fi

# vaporOS-coreutils and vaporshell: both split into their own repos
# $(APPDIR)/external/<name> path reference (in each repo's own
# Makefile) working unchanged, since that logical path still resolves
# correctly through the extra symlink hop.
if [ ! -d vaporOS-coreutils ]; then
  git clone https://github.com/tibocub/vaporOS-coreutils.git
fi

if [ ! -d vaporshell ]; then
  git clone https://github.com/tibocub/vaporshell.git
fi

[ -e nuttx-apps/external ] || ln -s "$DIR" nuttx-apps/external
[ -e "$DIR/toybox" ] || ln -s ../vaporOS-coreutils "$DIR/toybox"
[ -e "$DIR/vaporshell" ] || ln -s ../vaporshell "$DIR/vaporshell"

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
	sudo apt install \
	bison flex gettext texinfo libncurses5-dev libncursesw5-dev xxd \
  git gperf automake libtool pkg-config build-essential gperf genromfs \
	libgmp-dev libmpc-dev libmpfr-dev libisl-dev binutils-dev libelf-dev \
	libexpat1-dev gcc-multilib g++-multilib picocom u-boot-tools util-linux \
	kconfig-frontend
elif command -v dnf >/dev/null 2>&1; then
	sudo dnf install \
	bison flex gettext texinfo ncurses-devel ncurses ncurses-compat-libs \
	git gperf automake libtool pkgconfig @development-tools gperf genromfs \
	gmp-devel mpfr-devel libmpc-devel isl-devel binutils-devel elfutils-libelf-devel \
	expat-devel gcc-c++ g++ picocom uboot-tools util-linux
elif command -v dnf >/dev/null 2>&1 && ! command -v kconfig >/dev/null 2>&1; then
	git clone https://github.com/patacongo/tools
	cd tools/kconfig-frontends
	./configure --enable-mconf --disable-nconf --disable-gconf --disable-qconf
	aclocal
	automake
	make
	sudo make install
else
  echo "No apt-get or dnf -- install kconfig-frontends, genromfs, xxd, libx11-dev manually." >&2
fi

echo "Done. cd $DIR && make -f dev.mk build"
