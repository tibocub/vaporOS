# vaporOS in a browser

The `rv-virt` board (64-bit RISC-V, NuttX on QEMU's `virt` machine) runs unchanged in a web page: QEMU itself is
compiled to WebAssembly ([ktock/qemu-wasm](https://github.com/ktock/qemu-wasm)), and the emulated UART is a
[wterm](https://github.com/vercel-labs/wterm) terminal.

    make -f dev.mk build BOARD=rv-virt       # the kernel, as for native QEMU
    git clone --depth 1 https://github.com/ktock/qemu-wasm ../qemu-wasm
    tools/qemu-wasm.sh all                   # first time: image + qemu take a long time; `pack` + `site` take seconds
    (cd web && npm i)
    python3 web/serve.py                     # http://localhost:8088

After a new vaporOS build only `tools/qemu-wasm.sh pack && tools/qemu-wasm.sh site` is needed.

## How it fits together
- `tools/qemu-wasm.sh`: builds QEMU for emscripten in Docker (the project's pinned emsdk), bundles `../nuttx/nuttx` into
  the emscripten filesystem as `/pack/nuttx`, and assembles `web/site/`.
- `web/module.js`: QEMU's command line (`-M virt -cpu rv64 -bios none -kernel /pack/nuttx`, 64 MB, serial on stdio).
- `web/main.js`: QEMU's serial port is emscripten's TTY; `xterm-pty` is the other end of it, a shim makes wterm look
  like xterm.js. Errors and QEMU's own output are printed in the terminal.
- `web/serve.py`: pthreads need `SharedArrayBuffer`, which needs the COOP/COEP headers (any static host must send them).
- `?type=uname%20-a\n&after=8000` types into the terminal without a keyboard (testing).

## Pitfalls found
- The README's Docker mounts the source read-only; meson wants to download subprojects into it. The script fetches
  `dtc`, `keycodemapdb` and the berkeley float libs on the host first (including each wrap's `patch_directory`).
- `zlib.net` only serves the latest zlib; the Dockerfile in qemu-wasm points at a removed tarball. Use the GitHub release
  URL (we patched the local clone).
- load.js registers the file package on the global `Module`: assign `Module.arguments`, don't replace `Module`.
- Resolve `out.js` against the page, not the bundle.
