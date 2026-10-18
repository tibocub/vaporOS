#!/usr/bin/env bash
# Shared by vbuild.sh and clean.sh. Source after `cd nuttx`.

# apps/interpreters/lua's own distclean deletes the downloaded lua
# tarball every time, forcing a re-download on every rebuild even
# though lua's source never changed. Preserve it across distclean
# instead.
distclean_preserving_lua() {
  local TARBALL DIR="../nuttx-apps/interpreters/lua/lua" KEEP
  TARBALL=$(ls ../nuttx-apps/interpreters/lua/v*.tar.gz 2>/dev/null | head -1 || true)  # none yet is fine (first build, or a manual distclean removed it)
  KEEP=$(mktemp -d)

  [ -n "$TARBALL" ] && mv "$TARBALL" "$KEEP/tarball"
  if [ -d "$DIR" ] && [ -f "$DIR/lualib.h" ]; then
    mv "$DIR" "$KEEP/dir"
  elif [ -d "$DIR" ]; then
    rm -rf "$DIR"  # incomplete/wrong layout, don't cache it
  fi

  make distclean

  [ -f "$KEEP/tarball" ] && mv "$KEEP/tarball" "../nuttx-apps/interpreters/lua/$(basename "$TARBALL")"
  [ -d "$KEEP/dir" ] && mv "$KEEP/dir" "$DIR"
  rmdir "$KEEP"

  # Tarball present but never unpacked (e.g. manually placed): unpack
  # it. Handles both GitHub's flat layout and lua.org's src/ layout.
  if [ -n "$TARBALL" ] && [ ! -f "$DIR/lualib.h" ]; then
    local VER; VER=$(basename "$TARBALL" .tar.gz | sed 's/^v//')
    (
      cd ../nuttx-apps/interpreters/lua &&
      tar -xzf "$(basename "$TARBALL")" &&
      [ -d "lua-${VER}/src" ] && mv "lua-${VER}"/src/*.c "lua-${VER}"/src/*.h "lua-${VER}/"
      mv "lua-${VER}" lua
    )
  fi
}

# `make distclean` leaves the apps' object files behind, so switching between
# the sim and an ARM target links foreign objects ("file in wrong format").
# Run from the nuttx directory after distclean.
clean_stale_objects() {
  find ../nuttx-apps ../vaporOS ../vaporshell ../vaporOS-coreutils \
       -name '*.o' -delete 2>/dev/null || true
  rm -f staging/*.a ../nuttx-apps/libapps.a
}
