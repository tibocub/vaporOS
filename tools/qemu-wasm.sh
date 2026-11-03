#!/usr/bin/env bash
# tools/qemu-wasm.sh <step> -- run vaporOS (rv-virt) in a browser, with QEMU compiled to WebAssembly.
#
# Uses ktock/qemu-wasm (QEMU patched for emscripten, JIT to wasm), cloned next to this repo as ../qemu-wasm,
# built inside its Docker image (emsdk 3.1.50 + glib/zlib/libffi/pixman cross-compiled). See docs/browser.md.
#
#   image     build the Docker image                                    (slow, once: tens of minutes)
#   qemu      compile qemu-system-riscv64 to wasm in a container        (slow, once)
#   pack      bundle ../nuttx/nuttx into the emscripten filesystem     (seconds; redo after every vaporOS build)
#   site      assemble web/site/ (wasm + page); `web/serve.py` serves it
#   all       image, qemu, pack, site
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QEMU="$(dirname "$DIR")/qemu-wasm"
NUTTX="$(dirname "$DIR")/nuttx/nuttx"
C=build-qemu-wasm
[ -d "$QEMU" ] || { echo "clone it first: git clone --depth 1 https://github.com/ktock/qemu-wasm $QEMU" >&2; exit 1; }

# From qemu-wasm's README: threads (MTTCG), Asyncify for the few blocking spots, a PTY for the serial console.
EXTRA_CFLAGS="-O3 -g -Wno-error=unused-command-line-argument -matomics -mbulk-memory -DNDEBUG -DG_DISABLE_ASSERT -D_GNU_SOURCE -sASYNCIFY=1 -pthread -sPROXY_TO_PTHREAD=1 -sFORCE_FILESYSTEM -sALLOW_TABLE_GROWTH -sTOTAL_MEMORY=2300MB -sWASM_BIGINT -sMALLOC=mimalloc --js-library=/build/node_modules/xterm-pty/emscripten-pty.js -sEXPORT_ES6=1 -sASYNCIFY_IMPORTS=ffi_call_js"

container() { docker inspect "$C" >/dev/null 2>&1 || docker run --rm -d --name "$C" -v "$QEMU":/qemu/:ro buildqemu >/dev/null; }

step_image() { (cd "$QEMU" && docker build --progress=plain -t buildqemu - < Dockerfile); }

step_qemu() {
  container
  # meson fetches these subprojects (libfdt for the riscv64 "virt" machine, the keycode tables) INTO the source
  # tree, which the container mounts read-only: fetch them here, at the revisions the .wrap files pin.
  for sp in dtc keycodemapdb berkeley-softfloat-3 berkeley-testfloat-3; do
    w="$QEMU/subprojects/$sp.wrap" d="$QEMU/subprojects/$sp"
    [ -e "$d/.git/vapor-fetched" ] && continue
    mkdir -p "$d" && git -C "$d" init -q &&
      git -C "$d" fetch -q --depth 1 "$(sed -n 's/^url *= *//p' "$w")" "$(sed -n 's/^revision *= *//p' "$w")" &&
      git -C "$d" checkout -q FETCH_HEAD || exit 1
    # meson applies a wrap's patch_directory (QEMU's meson.build overlay) only after ITS download
    pd="$(sed -n 's/^patch_directory *= *//p' "$w")"
    [ -z "$pd" ] || cp -r "$QEMU/subprojects/packagefiles/$pd/." "$d"/
    touch "$d/.git/vapor-fetched"
  done
  docker exec "$C" emconfigure /qemu/configure --static --target-list=riscv64-softmmu --cpu=wasm32 --cross-prefix= \
    --without-default-features --enable-system --with-coroutine=fiber \
    --extra-cflags="$EXTRA_CFLAGS" --extra-cxxflags="$EXTRA_CFLAGS" \
    --extra-ldflags="-sEXPORTED_RUNTIME_METHODS=getTempRet0,setTempRet0,addFunction,removeFunction,TTY,FS"
  docker exec "$C" emmake make -j"$(nproc)" qemu-system-riscv64
}

step_pack() {
  [ -f "$NUTTX" ] || { echo "no $NUTTX: make -f dev.mk build BOARD=rv-virt" >&2; exit 1; }
  container
  docker exec "$C" sh -c 'rm -rf /pack && mkdir /pack'
  docker cp "$NUTTX" "$C":/pack/nuttx
  docker exec "$C" sh -c '/emsdk/upstream/emscripten/tools/file_packager.py qemu-system-riscv64.data --preload /pack > load.js'
}

step_site() {
  container
  local out="$DIR/web/site"
  rm -rf "$out" && mkdir -p "$out"
  (cd "$DIR/web" && bun build main.js --outdir dist --target browser --external ./out.js >/dev/null)
  cp -r "$DIR"/web/{index.html,module.js,dist} "$out"/
  docker cp "$C":/build/qemu-system-riscv64 "$out/out.js"
  for f in qemu-system-riscv64.wasm qemu-system-riscv64.worker.js qemu-system-riscv64.data load.js; do
    docker cp "$C":/build/"$f" "$out"/
  done
  echo "site ready: python3 $DIR/web/serve.py  (http://localhost:8088)"
}

case "${1:-}" in
  image) step_image ;; qemu) step_qemu ;; pack) step_pack ;; site) step_site ;;
  all) step_image; step_qemu; step_pack; step_site ;;
  *) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
