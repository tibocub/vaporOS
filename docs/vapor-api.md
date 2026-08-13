# vaporOS Lua API (`vapor`)

## Design principle

`vapor` exists **only** for capabilities standard Lua doesn't already
provide. If something is already reachable via Lua's own stdlib
(`io`, `os`, `string`, `table`, `math`, `coroutine`), it does not
belong in `vapor` -- wrapping it under a different name adds a
namespace without adding a capability.

The test for "does this belong in `vapor`": would a plain Lua
interpreter, with no vaporOS underneath it, be unable to do this at
all? If yes, it's a real gap. If it's just a different name for
something `io`/`os`/etc. already do, it isn't.

## What Lua already provides

Confirmed by what's actually compiled into this NuttX Lua build
(`liolib.c`, `loslib.c` both present):

- `io.open` / `io.read` / `io.write` / `io.close` / `io.lines` /
  `file:seek` -- real file I/O, backed by NuttX's actual POSIX
  filesystem. A vaporOS Lua script can already
  `io.open("/data/notes.txt", "w")` today, no `vapor` involved.
- `os.remove`, `os.rename` -- delete/rename a known file.
- `os.time`, `os.clock`, `os.date` -- wall clock + CPU time.
- `string.*`, `table.*`, `math.*`, `coroutine.*` -- the rest of the
  standard library.

None of the above should ever get a `vapor` wrapper.

## Confirmed real gaps -- what actually belongs in `vapor`

### Directory / filesystem metadata

Lua's `io`/`os` cover read/write/rename/remove of a file whose name
you already know. They have no equivalent of:

- listing a directory's contents (no `opendir`/`readdir` analog)
- creating a directory (no `mkdir`)
- checking a file's type or size without opening and reading it (no
  `stat`)

This is the real, narrower version of "filesystem access Lua doesn't
have" -- not file I/O in general, which Lua already covers, but
directory/metadata operations specifically.

### Timing / sleep

Lua has no sleep or delay primitive at all, by design -- blocking is
an OS-level concept a portable language can't provide on its own.
`vapor.sleep(seconds)` is justified here.

Worth checking rather than assuming: whether `os.clock()` already
covers "measure elapsed time" well enough that a dedicated
`vapor.time()` isn't needed either. `os.clock()` in standard Lua
measures CPU time, not wall-clock time, which may or may not be what
we actually want -- needs a real test on this NuttX build before
deciding, not an assumption either way.

### Hardware / peripherals

The actual substance of the ComputerCraft-inspired vision, and none
of it exists in stock Lua at all:

- GPIO -- confirmed real `/dev/gpioN` character devices already
  present on NuttX's `sim` target, `ioctl`-driven
- Displays/screens
- LoRa/radio modules
- Keyboards/other input devices
- Networking, if/when it's ever worth exposing at the Lua level
  rather than leaving it to native vaporOS programs

## Naming / registration convention

Already established, keep it: `vapor.<category>.<action>`, e.g.
`vapor.gpio.write`, `vapor.fs.list`. Each category gets its own
`vapor_<category>_register(lua_State *L)` C function (see
`vapor_core.h`'s existing doc comment), all adding fields onto the
one shared `vapor` global table that `vlua_main.c` creates once at
startup. A new peripheral module never creates its own table or
touches another module's fields -- it only ever adds its own.

## Immediate next steps

1. Retire `vapor.print` / `vapor.write` / `vapor.read` from
   `vapor_core.c` -- confirmed pure duplication of `io`/stock
   `print()`.
2. Verify whether `vapor.time` is also redundant with `os.clock()`
   before deciding to keep or retire it.
3. Keep `vapor.sleep` -- the one function from the current
   `vapor_core.c` that's actually justified.
4. Design `vapor.fs` -- directory listing, `mkdir`, `stat`. The real
   filesystem gap.
5. Design `vapor.gpio` -- the first hardware capability, and the
   proof that the registration convention above works for a second
   module, not just `vapor_core`.
