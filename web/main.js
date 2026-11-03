// vaporOS (NuttX rv-virt) on QEMU compiled to wasm, with a wterm terminal.
// QEMU's serial port is the emscripten TTY; xterm-pty turns a terminal into that TTY's other end. It was
// written for xterm.js, so a small shim lets wterm look like one.
import { WTerm } from "@wterm/dom";
import "@wterm/dom/css";
import { openpty } from "xterm-pty";

const term = new WTerm(document.getElementById("terminal"), { cursorBlink: true });
await term.init();

const listeners = (set) => (cb) => { set.add(cb); return { dispose: () => set.delete(cb) }; };
const data = new Set(), resize = new Set();
term.onData = (s) => data.forEach((cb) => cb(s));
term.onResize = (cols, rows) => resize.forEach((cb) => cb({ cols, rows }));
const xtermLike = {
  write: (bytes, done) => { term.write(bytes); if (done) done(); },
  onData: listeners(data), onBinary: listeners(new Set()), onResize: listeners(resize),
};

const { master, slave } = openpty();
master.activate(xtermLike);
term.focus();

// Show problems in the terminal itself: a blank screen tells nobody anything.
const say = (s) => term.write(String(s).replace(/\r?\n/g, "\r\n") + "\r\n");
window.addEventListener("error", (e) => say(`[error] ${e.message}`));
window.addEventListener("unhandledrejection", (e) => say(`[error] ${e.reason?.stack || e.reason}`));
say(`[vaporOS] cross-origin isolated: ${self.crossOriginIsolated} (needed for wasm threads)`);
say("[vaporOS] loading QEMU (41 MB wasm)...");

// Module (module.js) is a global the emscripten output reads its arguments from.
const { default: init } = await import(/* @vite-ignore */ new URL("out.js", document.baseURI).href);
Module.print = say;
Module.printErr = say;
Module.pty = slave;
Module.mainScriptUrlOrBlob = location.origin + "/out.js";
say("[vaporOS] starting the virtual machine...");
const instance = await init(Module);
// xterm-pty's poll shim (from qemu-wasm's own example): report "readable" only when there is input.
const oldPoll = Module.TTY.stream_ops.poll;
Module.TTY.stream_ops.poll = (stream, timeout) =>
  slave.readable ? oldPoll.call(stream, timeout) : (slave.writable ? 4 : 0);

// ?type=<text>&after=<ms>: type into the terminal through the same path as the keyboard (for testing without one).
// "\n" in the text is Enter.
const q = new URLSearchParams(location.search);
if (q.has("type")) setTimeout(() => data.forEach((cb) => cb(q.get("type").replace(/\\n/g, "\r"))), +q.get("after") || 10000);
