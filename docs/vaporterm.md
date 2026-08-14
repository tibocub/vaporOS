# vaporOS graphical terminal (`vterm`)

## Design principle

Same split as `vapor-api.md`: leverage what's already solved, build only
what's genuinely missing. `libvterm` solves VT100/xterm escape-sequence
parsing and screen-state tracking -- correctness-sensitive work with
no reason to redo it. NX's font-rendering utilities (`nxfonts`) solve
glyph rasterization -- also not worth redoing. What's actually ours to
build is the glue between `libvterm` and the raw framebuffer, plus
keyboard input.

**Revision, after further thought:** NX is really two separable
things -- a windowing/compositing layer (multiple movable, resizable,
z-ordered windows) and a font/drawing-primitives library sitting
underneath it. We only want the second. See "Rendering target" below
for why, and for the precedent (`apps/examples/fbcon`) that confirms
this split is real and already used elsewhere in NuttX.

## Why not NxTerm

Confirmed directly from its own source: `nxterm_vt100.c` recognizes
exactly one escape sequence (erase-to-end-of-line) and says so itself
-- "a placeholder for a future, more complete VT100 emulation." Any
real line editor's cursor/redraw sequences get dumped back out as
literal text. Not a config problem to work around; a real gap in
NuttX's own graphics stack for this use case.

## Architecture

```
NSH (nsh_consolemain, same pattern as apps/examples/nxterm)
  |
  | stdout
  v
our custom stream/device  ---->  libvterm (parser + screen state)
  ^                                   |
  |                                   | VTermScreenCallbacks
  | stdin                             v
  |                              our render callbacks
keyboard input reader  <---         (damage -> redraw dirty cells,
                                      using nxfonts for glyphs)
                                     |
                                     v
                                  /dev/fb0, direct -- no NX window
                                  server, no compositor (on sim: the
                                  same X11-backed framebuffer device
                                  nx11 already uses; on real hardware:
                                  whatever the board's display driver
                                  exposes as a framebuffer)
```

Same shape `apps/examples/nxterm` already uses for wiring NSH's
console I/O -- we're not inventing a new way to attach NSH to a
display, just replacing the two pieces that are actually inadequate
(the escape-sequence interpreter, and eventually the input path).

No PTY needed. NuttX doesn't have process-level PTY the way Linux
does, and we don't need one -- we're not spawning NSH as a separate
process to attach to, we're redirecting its own I/O streams directly,
same as `nxterm_main.c` does today.

## libvterm integration specifics

- Use the **Screen** layer (`VTermScreen`, `vterm_screen_set_callbacks`),
  not the lower-level State layer. Screen maintains the actual cell
  grid for us (`vterm_screen_get_cell`) -- meaningfully less state
  we'd otherwise have to track ourselves.
- Callbacks needed for v1: `damage` (dirty rectangles -- drives what we
  redraw), `movecursor` (cursor position/visibility). Everything else
  (`settermprop` for color/bold, `bell`, `resize`, `sb_pushline`/
  `sb_popline` for scrollback) can no-op initially -- monochrome,
  fixed-size, no scrollback, matching the same "smallest real thing
  first" discipline as `vapor_core.c`.
- Vendoring: bring the library source into this repo directly (small,
  self-contained, no build-script dependency per its own docs) rather
  than fetching it at build time the way `apps/interpreters/lua` does
  -- one less thing that can fail on a flaky network mid-build, and
  we've already hit that exact failure mode with Lua's own fetch step.

## Rendering target: direct framebuffer, not an NX window

Decided against NX's windowing layer for v1. vaporOS's own preference
is terminal-first -- a single full-screen surface, TUIs running inside
it exactly like `vim`/`htop` do in any real terminal, with actual
multi-window GUI treated as optional future work rather than a
foundation everything else depends on. NX's windowing/compositing
machinery (multiple movable, resizable, z-ordered windows, cross-window
event routing) exists to solve a problem we don't have in v1.

This split is real, not a workaround -- confirmed via
`apps/examples/fbcon`, which already does close to exactly this:
redirects NSH's stdout to `/dev/fb0` directly (`open()` +
`ioctl(FBIOGET_VIDEOINFO)` + `mmap()`), uses NX's `nxf_getbitmap`/
`nxf_getfonthandle` purely for glyph rendering, and never calls
`nx_openwindow` at all. No compositor, one surface, the whole screen.

What we're taking from `fbcon`: the proven mechanics for talking to
the raw framebuffer and blitting glyphs via `nxfonts`. What we're
**not** taking: its own hand-rolled VT100 parser -- its escape table
includes the exact sequences that broke NxTerm (`\e[2K`, `\e[?25l`,
`\e[?25h`), and its completeness is unaudited. No reason to trust an
unverified parser when `libvterm` is already proven correct (Milestone
1). So: `fbcon`'s framebuffer/glyph mechanics + `libvterm`'s
interpretation, not `fbcon` wholesale.

- Reuse `CONFIG_NXFONT_SANS23X27` (already enabled, already proven
  working) via `nxfonts`, rather than building font rendering
  ourselves.
- Redraw only what `libvterm`'s `damage` callback marks dirty, not the
  whole screen on every change -- matters even at sim scale, matters a
  lot more on real hardware.
- NX windowing (`NxWM`, multi-window GUI) stays available as a
  genuinely separate, addable layer later, on top of the same
  framebuffer -- this decision doesn't foreclose it, just doesn't make
  it a dependency of the first working terminal.

## Keyboard input -- staged deliberately, not bundled into v1

This is the piece with genuine open risk, and worth being honest about
rather than folding it into the same milestone as everything else
that's already well-understood:

- **v1 (sim)**: same limitation NxTerm has today -- keyboard input
  comes from the host terminal's stdin, not from clicking into the
  X11 window backing `/dev/fb0` on sim. Gets us a working,
  correctly-rendering terminal without betting the whole plan on the
  uncertain part.
- **v2 (sim)**: real X11 key-event forwarding into that backing
  window, so typing happens there directly. Genuinely uncertain --
  this is the area a recent NuttX GitHub issue (#16802) flagged as
  having rough edges on a different graphics stack using the same
  underlying X11-sim input layer. Worth attempting once v1 proves the
  rendering side works, not before.
- **v3 (real hardware)**: an actual keyboard driver (USB HID, matrix,
  whatever the board has) as NSH's real console input. No X11
  involved at all -- this is arguably the *simpler* case once we're
  off the simulator, since it's the same "device is the console"
  pattern as a UART, just swapped for a keyboard.

## Milestones

1. **Done.** Vendored `libvterm` (`vterm/libvterm/`, MIT, Paul Evans,
   from the Neovim-lineage source -- not the smaller `untodesu`
   reimplementation, since only this one has the Screen API the plan
   above depends on). Built through the real NuttX app pipeline (not
   just host gcc) via a small test app (`vterm/vtermtest_main.c`) that
   feeds it a string containing real ANSI escapes and checks what it
   parsed back. Result, run for real in NSH:

   ```
   nsh> vtermtest
   vtermtest: input  = "Hello, <bold>vaporOS<reset> terminal!"
   vtermtest: parsed = "Hello, vaporOS terminal!"
   vtermtest: PASS -- escape sequences consumed correctly, not leaked
   as literal text
   ```

   Confirms the exact bug class that started this investigation
   (NxTerm leaking unrecognized escapes as literal text) does not
   recur here.

2. Minimal direct-framebuffer setup (`open`/`ioctl(FBIOGET_VIDEOINFO)`/
   `mmap` on `/dev/fb0`, following `fbcon`'s proven mechanics) +
   `damage`/`movecursor` callbacks rendering static test content via
   `nxfonts` glyph blitting -- not real NSH output yet, no NX window
   involved -- proves the render pipeline independent of NSH wiring.
3. Wire NSH's stdout through our stream into `libvterm`, keyboard
   still via host stdin (the v1 input stage above) -- first genuinely
   usable terminal, input limitation and all.
4. Investigate real keyboard forwarding (the v2 input stage) as its
   own follow-up, not a blocker for calling milestone 3 a real,
   working result.
