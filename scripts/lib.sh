#!/usr/bin/env bash
# Shared by build.sh and clean.sh. Source after `cd nuttx`.

# apps/interpreters/lua's own distclean deletes the downloaded lua
# tarball every time, forcing a re-download (and GitHub rate-limit
# risk) on every rebuild even though lua's source never changed.
# Preserve it across distclean instead.
distclean_preserving_lua() {
  local TARBALL DIR="../apps/interpreters/lua/lua"
  TARBALL=$(ls ../apps/interpreters/lua/v*.tar.gz 2>/dev/null | head -1)

  [ -n "$TARBALL" ] && mv "$TARBALL" /tmp/vaporos-lua.tar.gz
  if [ -d "$DIR" ] && [ -f "$DIR/lualib.h" ]; then
    rm -rf /tmp/vaporos-lua-dir
    mv "$DIR" /tmp/vaporos-lua-dir
  elif [ -d "$DIR" ]; then
    rm -rf "$DIR"  # incomplete/wrong layout, don't cache it
  fi

  make distclean

  [ -f /tmp/vaporos-lua.tar.gz ] && mv /tmp/vaporos-lua.tar.gz "../apps/interpreters/lua/$(basename "$TARBALL")"
  [ -d /tmp/vaporos-lua-dir ] && mv /tmp/vaporos-lua-dir "$DIR"

  # Tarball present but never unpacked (e.g. manually placed): unpack
  # it. Handles both GitHub's flat layout and lua.org's src/ layout.
  if [ -n "$TARBALL" ] && [ ! -f "$DIR/lualib.h" ]; then
    local VER; VER=$(basename "$TARBALL" .tar.gz | sed 's/^v//')
    (
      cd ../apps/interpreters/lua &&
      tar -xzf "$(basename "$TARBALL")" &&
      [ -d "lua-${VER}/src" ] && mv "lua-${VER}"/src/*.c "lua-${VER}"/src/*.h "lua-${VER}/"
      mv "lua-${VER}" lua
    )
  fi
}
