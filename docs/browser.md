# vaporOS in a browser

The `rv-virt` board (64-bit RISC-V, NuttX on QEMU's `virt` machine) runs unchanged in a web page: QEMU itself is
compiled to WebAssembly ([ktock/qemu-wasm](https://github.com/ktock/qemu-wasm)), and the emulated UART is a
[wterm](https://github.com/vercel-labs/wterm) terminal.

    make -f dev.mk build BOARD=rv-virt       # the kernel, as for native QEMU
    git clone --depth 1 https://github.com/ktock/qemu-wasm ../qemu-wasm
    tools/qemu-wasm.sh all                   # first time: image + qemu take a long time; `pack` + `site` take seconds
    (cd web && bun i)
    python3 web/serve.py                     # http://localhost:8088

After a new vaporOS build only `tools/qemu-wasm.sh pack && tools/qemu-wasm.sh site` is needed.

## What is in the image
vaporshell + the toybox applets, `vlua` (Lua 5.4), `vi`, the vaporUI examples (`vui_windows`, `vui_buttons`, `vui_colors`,
`vui_input`, `vui_layout`, `vui_textarea`), the demos, and a RAM `/tmp` (the board has no persistent storage: files are
gone on reload). No network, no ELF loading, no Lua libs (lfs/lpeg/cjson).

Verified (headless Firefox, injected keystrokes): boot to `vaporshell$` in under ~8 s, typing and output, `vui_windows`
fills the window (the size comes from vaporUI's cursor-position probe, answered by wterm), `vlua` and `/tmp` natively.
Not yet checked by hand: mouse, `vi`, the other vui_* examples, paste, resizing the window.

Known quirk: a key typed while the kernel is still booting can be lost (the first character of a command).

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

## Lag: what it was, and how to look at it
Two things made the terminal freeze for seconds to a minute (headless-Firefox measurements, `?trace=1&type=ls\n&every=6000`):
- **xterm-pty blocks.** Its `read` parks the calling thread until the next keystroke when no byte is ready, and its `poll`
  waits on the terminal alone (ignoring QEMU's timeout and every other fd). QEMU's main loop, which also runs the guest's
  timers, shares that thread, so the machine stood still until a key arrived. `web/main.js` replaces both with
  non-blocking versions (the poll one comes from qemu-wasm's own example; the read one is ours).
- **emscripten's `poll` never sleeps**, so the non-blocking version spins the main loop. `tools/qemu-wasm-patches/poll-sleeps.patch`
  makes `qemu_poll_ns` sleep in short slices (idle CPU from ~160% of a core to ~40%).

`?trace=1` prints, once at 22 s, a timeline: `<seconds>i` is a key, and `<seconds>[p y r o]` is the polls, readable polls,
reads and guest output bytes in the second ending then. A healthy run polls constantly and answers each key within a second.
`?qemu=a|b|c` replaces QEMU's command line, `?type=..&after=ms&every=ms` injects keystrokes.

Ruled out: the wasm JIT (pure interpreter froze the same), the guest tick rate, and the CPU idle wait.

## Output speed
Pure output (`dd if=/dev/zero bs=1024 count=64`, via `?trace=1`):

| console | rate |
|---|---|
| emulated 16550 UART, one write() per byte | ~2 KB/s |
| UART + `chardev-coalesce.patch` | ~13 KB/s |
| virtio-serial + coalescing | ~128 KB/s |

Each UART byte costs the guest a register write, an interrupt and a trip through the tty layer, all interpreted; the
coalescing patch cuts the host-side round trips (one per byte becomes one per 2 ms). virtio-serial moves whole buffers.
The boot messages still go to the UART, which the browser build discards (`-serial null`); the native runner
(`tools/runners/qemu-riscv.sh`) picks virtio or the UART from the built `.config`.

## Where the guest's speed goes (measured)
Benchmark: `dd if=/dev/zero of=/dev/null bs=512 count=40000` in the browser (guest-bound, no terminal output):

| build | time |
|---|---|
| JIT off (TCI interpreter only) | 8.2 s |
| JIT, threshold 1500 (qemu-wasm default) | 3.0 s |
| JIT, threshold 100 | 2.9 s |
| linked without `-g` (full Binaryen; `qemu-wasm.sh slim`) | 3.0 s, wasm 41 -> 11 MB |
| NuttX release config (no DEBUG_FEATURES / stack coloration) | 3.0 s |

So the wasm JIT is worth 2.7x and is already working, and none of the cheap knobs move it further. What is left is
structural: qemu-wasm compiles each translation block to its own small wasm module, so every block ends back in a C
dispatch loop (no chaining between blocks), and guest memory accesses go through helpers. Beyond that, the options are
a different execution model (NuttX compiled to wasm, i.e. a new architecture port), not tuning.
