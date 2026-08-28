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

  # Small, targeted patch to upstream apps/system/readline: adds
  # readline_history_load()/readline_history_save() (no public API
  # exists otherwise -- g_cmdhist is file-private, so an application
  # has no way to persist history to a file without this) and
  # Ctrl+P/Ctrl+N history navigation (only the escape-sequence up/down
  # arrow path exists upstream). Kept as a checked-in patch file here,
  # applied once right after cloning, rather than a fork of
  # nuttx-apps -- keeps the modification tracked in version control
  # (unlike a manual, local-only edit, which a fresh `apps` clone on
  # another machine would silently lose) without the ongoing
  # maintenance of a full fork. See patches/README.md.
  git -C apps apply "$DIR/patches/nuttx-apps/readline-history-ctrlpn.patch"
fi

# vaporOS-coreutils and vaporshell: both split into their own repos
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
