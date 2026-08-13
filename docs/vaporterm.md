# vaporOS graphical terminal (`vterm`)

## Design principle

Same split as `vapor-api.md`: leverage what's already solved, build only
what's genuinely missing. `libvterm` solves VT100/xterm escape-sequence
parsing and screen-state tracking -- correctness-sensitive work with
no reason to redo it. NX solves windowing, drawing primitives, and
font rendering. What's actually ours to build is the glue between
them, plus keyboard input -- the two things neither library can do for
us, because both are specific to how *we* want this to work.

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
  |                              our NX render callbacks
keyboard input reader  <---         (damage -> redraw dirty cells)
                                     |
                                     v
                                  NX window (on sim: X11; on real
                                  hardware: the actual display)
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

## NX rendering

- Reuse `CONFIG_NXFONT_SANS23X27` (already enabled, already proven
  working in the `nx11`/`nxterm` builds) rather than building font
  rendering ourselves.
- Redraw only what `libvterm`'s `damage` callback marks dirty, not the
  whole screen on every change -- matters even at sim scale, matters a
  lot more on real hardware.
- Single fullscreen NX window. No window manager (`NxWM`) for v1 --
  that's a real, heavier thing (C++, its own widget library) worth
  its own evaluation later, not a dependency for a first working
  terminal.

## Keyboard input -- staged deliberately, not bundled into v1

This is the piece with genuine open risk, and worth being honest about
rather than folding it into the same milestone as everything else
that's already well-understood:

- **v1 (sim)**: same limitation NxTerm has today -- keyboard input
  comes from the host terminal's stdin, not from clicking into the
  window. Gets us a working, correctly-rendering terminal without
  betting the whole plan on the uncertain part.
- **v2 (sim)**: real X11 key-event forwarding into the window, so
  typing happens in the window itself. Genuinely uncertain -- this is
  the area a recent NuttX GitHub issue (#16802) flagged as having
  rough edges on a different graphics stack using the same underlying
  X11-sim input layer. Worth attempting once v1 proves the rendering
  side works, not before.
- **v3 (real hardware)**: an actual keyboard driver (USB HID, matrix,
  whatever the board has) as NSH's real console input. No X11
  involved at all -- this is arguably the *simpler* case once we're
  off the simulator, since it's the same "device is the console"
  pattern as a UART, just swapped for a keyboard.

## Milestones

1. Vendor `libvterm`, confirm it builds standalone against the NuttX
   toolchain (no NX integration yet) -- proves the library itself is
   portable here before we build anything on top of it.
2. Minimal NX window + `damage`/`movecursor` callbacks rendering
   static test content (not real NSH output yet) -- proves the
   render pipeline independent of NSH wiring.
3. Wire NSH's stdout through our stream into `libvterm`, keyboard
   still via host stdin (the v1 input stage above) -- first genuinely
   usable terminal, input limitation and all.
4. Investigate real keyboard forwarding (the v2 input stage) as its
   own follow-up, not a blocker for calling milestone 3 a real,
   working result.
