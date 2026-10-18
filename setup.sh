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

# vaporOS's changes to NuttX itself (see patches/UPSTREAM.md); idempotent.
"$DIR/tools/apply-patches.sh" || echo "WARNING: some patches did not apply" >&2

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
	if ! command -v kconfig-conf >/dev/null 2>&1; then    # not packaged for Fedora
		git clone https://github.com/patacongo/tools
		cd tools/kconfig-frontends
		./configure --enable-mconf --disable-nconf --disable-gconf --disable-qconf
		aclocal
		automake
		make
		sudo make install
	fi
else
  echo "No apt-get or dnf -- install kconfig-frontends, genromfs, xxd, libx11-dev manually." >&2
fi

echo "Done. cd $DIR && make -f dev.mk build to compile vaporOS"
echo "generate compile-commands.json with scripts/gen-compile-commands.sh"
