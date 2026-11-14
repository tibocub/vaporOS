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
say("[vaporOS] loading QEMU (wasm)...");

// Module (module.js) is a global the emscripten output reads its arguments from.
const { default: init } = await import(/* @vite-ignore */ new URL("out.js", document.baseURI).href);
Module.print = say;
Module.printErr = say;
Module.pty = slave;
Module.mainScriptUrlOrBlob = new URL("out.js", document.baseURI).href;
say("[vaporOS] starting the virtual machine...");
const instance = await init(Module);
// xterm-pty's poll shim (from qemu-wasm's own example): report "readable" only when there is input.
const oldPoll = Module.TTY.stream_ops.poll;
Module.TTY.stream_ops.poll = (stream, timeout) =>
  slave.readable ? oldPoll.call(stream, timeout) : (slave.writable ? 4 : 0);
// Same for read: xterm-pty parks the calling thread until the next keystroke when no byte is ready, and QEMU's main
// loop (timers, the guest's clock tick) shares that thread. Report "nothing yet" (EAGAIN) instead.
Module.TTY.stream_ops.read = (stream, buffer, offset, length) => {
  const bytes = slave.read(length);
  if (length && !bytes.length) throw new Module.FS.ErrnoError(6 /* EAGAIN */);
  buffer.set(bytes, offset);
  return bytes.length;
};

// ?type=<text>&after=<ms>: type into the terminal through the same path as the keyboard (for testing without one).
// "\n" in the text is Enter.
const q = new URLSearchParams(location.search);
if (q.has("type")) {
  const send = () => data.forEach((cb) => cb(q.get("type").replace(/\\n/g, "\r")));
  setTimeout(send, +q.get("after") || 10000);
  if (q.has("every")) setInterval(send, +q.get("every"));  // keep typing: shows whether input is lost or just slow
}

// ?trace: a timeline of terminal traffic (seconds since page start; i = key, o<n> = n bytes from the guest),
// printed once at 14 s, plus main-thread stalls. For chasing lag.
if (q.has("trace")) {
  const ev = [], t = () => ((performance.now()) / 1000).toFixed(1);
  data.add(() => ev.push(`${t()}i`));
  const write = xtermLike.write;
  xtermLike.write = (b, d) => { o += b.length; write(b, d); };
  // how often QEMU polls/reads the terminal per second (p = polls, y = polls that said "readable", r = reads)
  let p = 0, y = 0, r = 0, o = 0;
  const ops = Module.TTY.stream_ops, poll = ops.poll, read = ops.read;
  ops.poll = (...a) => { const m = poll(...a); p++; if (m & 1) y++; return m; };
  ops.read = (...a) => { r++; return read(...a); };
  setInterval(() => { ev.push(`${t()}[p${p} y${y} r${r} o${o}]`); p = y = r = o = 0; }, 1000);
  let last = performance.now(), worst = 0;
  setInterval(() => { const n = performance.now(); worst = Math.max(worst, n - last - 100); last = n; }, 100);
  setTimeout(() => say(`[trace] stall ${Math.round(worst)} ms; ${ev.join(" ")}`), 25000);
}
