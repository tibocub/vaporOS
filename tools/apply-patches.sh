#!/usr/bin/env bash
# tools/apply-patches.sh [patch-name ...] -- apply vaporOS's patches to the
# sibling ../nuttx and ../nuttx-apps checkouts, idempotently.
#
#   patches/nuttx/*.patch       -> ../nuttx
#   patches/nuttx-apps/*.patch  -> ../nuttx-apps
#
# With no arguments every patch is applied. Already-applied patches are
# recognised (the reverse applies cleanly) and skipped, so it is safe to run
# on every build. A patch whose header says "does NOT apply" is known-broken
# and only tried when asked for by name. Why each patch exists, and whether it
# could go upstream, is in its own header and in patches/UPSTREAM.md.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$DIR")"
rc=0

apply_one() {
  local repo="$1" patch="$2" name; name="$(basename "$patch")"
  if git -C "$WORKSPACE/$repo" apply -R --check "$patch" >/dev/null 2>&1; then
    echo "  applied    $repo: $name"
  elif git -C "$WORKSPACE/$repo" apply "$patch" 2>/dev/null; then
    echo "  APPLIED    $repo: $name"
  else
    echo "  FAILED     $repo: $name (does not apply to this checkout)" >&2
    rc=1
  fi
}

wanted() { [ $# -eq 1 ] && return 0; local n="$1"; shift; for w in "$@"; do [ "$w" = "$n" ] && return 0; done; return 1; }

for repo in nuttx nuttx-apps; do
  [ -d "$WORKSPACE/$repo" ] || continue
  for patch in "$DIR/patches/$repo"/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if [ $# -gt 0 ]; then
      wanted "$name" "$@" || continue
    elif head -12 "$patch" | grep -q "does NOT apply"; then
      echo "  skipped    $repo: $name (known not to apply; see its header)"
      continue
    fi
    apply_one "$repo" "$patch"
  done
done
exit $rc
