#!/usr/bin/env bash
# vaporOS-nuttx/setup.sh -- one-time environment setup (Linux/macOS).
# Clones nuttx+apps, wires this repo in as apps/external. Does not
# build -- see dev.mk (`make -f dev.mk build`).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$DIR")"

if [ ! -d nuttx ]; then
  git clone https://github.com/apache/nuttx.git
  git -C nuttx checkout "releases/13.0"
fi

if [ ! -d apps ]; then
  git clone https://github.com/apache/nuttx-apps.git

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
  git -C nuttx-apps apply "$DIR/patches/nuttx-apps/readline-history-ctrlpn.patch"
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

[ -e apps/external ] || ln -s "$DIR" nuttx-apps/external
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
