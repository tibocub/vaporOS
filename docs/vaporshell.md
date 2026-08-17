# vaporOS shell (`vaporshell`)

## Design principle

Same split as `vapor-api.md` and `vaporterm.md`: leverage what NuttX's
own POSIX layer already solves, build only what's genuinely
shell-specific and unavailable from any OS regardless of how POSIX-
compliant it is. The first shells were a thin, scriptable interface
over the kernel -- not much more than "read a line, resolve a path,
run a program." That's the feeling to recreate: vaporshell shouldn't
reimplement anything the kernel already does, it should just expose
it comfortably.

Portability is a first-class constraint from the start, not a later
pass: sim first for iteration speed, but every design decision below
is checked against whether it still holds on ESP32/RP2040, and NuttX
architecture-independent code (`sched/`, `libs/libc/`) is preferred
over sim-only shortcuts (`arch/sim/`) wherever both would work. Where
that isn't possible -- see Clipboard below -- it's called out
explicitly rather than quietly assumed to work everywhere.

## What NuttX already provides -- confirmed, not assumed

Checked directly against source, the same way `vapor-api.md` checked
what Lua's stdlib already covers:

- **PATH resolution + program execution**: `posix_spawn`/`posix_spawnp`
  are real (`sched/task/task_posixspawn.c`, `task_spawn.c`) --
  architecture-independent code, not under `arch/sim/`, so this isn't
  a sim-only convenience. `posix_spawnp`'s PATH search is built in via
  `CONFIG_LIBC_ENVPATH` (it's literally `#define posix_spawnp
  posix_spawn` with that flag set). This is the primitive to build on,
  not `fork()`+`exec()` -- NuttX's own docs list `fork()` itself as
  "not appropriate for a deeply-embedded RTOS," and confirmed directly
  that it only has a real implementation for the `sim` architecture
  (`arch/sim/src/sim/sim_fork.c`). `posix_spawn` is the one that
  actually works the same way on sim, ESP32, and RP2040.

- **Pipes and redirection**: `pipe()`/`dup2()` are real and already
  proven under load -- this is exactly what `vterm_fb`'s `openpty()`
  is built on.

- **Environment variables**: `getenv`/`setenv`/`environ` are real,
  per-task. `$PATH`, `$SHELL`, `$USER`, `$PWD` are plain environment
  variables, no special-casing needed.

- **`$PWD`**: `chdir`/`getcwd` are real, confirmed already (see
  `vapor-api.md`'s "WHY NUTTX" equivalent claims, and our own direct
  use of these this whole project).

- **Line editing, history, and raw-mode input**: `apps/system/readline`
  is already vendored, already fought through in detail getting
  `vterm_fb` working -- reuse this instead of writing a second line
  editor. See "Line editing" below for a real nuance this surfaced.

## Confirmed real gap: process groups

Checked directly in `libs/libc/unistd/lib_setpgid.c` -- its own
comment says it plainly: *"NuttX does not implement process groups,
so a process group always contains a single member and its ID equals
the process ID."* `setpgid`/`tcsetpgrp` exist but are stubs.

This is the mechanism real job control (`Ctrl+Z` suspending a whole
pipeline as a unit, `fg`/`bg` reassigning terminal control to a
process group) is built on in a real Unix shell, and it isn't
available here -- not a matter of effort, the underlying primitive
doesn't exist. **Job control is out of scope** for now. `Ctrl+C`
still works against a single foreground child directly (see below);
what doesn't work is the group semantics around it.

## Line editing: a nuance worth designing around, not just reusing blindly

`apps/system/readline` has real command history already built in
(`CONFIG_READLINE_CMD_HISTORY` -- up/down arrow recall, and even a
reverse incremental search under `CONFIG_READLINE_EDIT_EMACS_REVERSE_SEARCH`,
bash-style `Ctrl+R`). This is exactly the comfort NSH doesn't expose
today and vaporshell wants.

The catch: that interactive recall logic lives inside the
`CONFIG_READLINE_EDIT` branch -- the same branch `vterm_fb` had to
turn *off* entirely (`READLINE_EDIT=n`) to fix plain characters not
echoing when typed at the end of a line (see the vterm_fb debugging
history). Confirmed via source: `READLINE_EDIT`'s redraw-based
operations (history recall, Home/End, word movement) all trigger an
explicit `redraw_tail()`-style repaint, which does work correctly on
our terminal -- the bug was narrowly in the *plain append at
end-of-line* case (`cursor == nch`, so `redraw_tail`'s `cursor < nch`
guard never fires). vterm_fb's fix threw away the whole branch
(simplest fix, no NSH-specific behavior depending on history to
preserve) rather than patching that one condition.

vaporshell should not repeat that trade-off blindly. Worth actually
trying: `READLINE_EDIT=y` with a narrow patch to make the end-of-line
append case echo too (rather than disabling the branch wholesale),
which would get history recall, Ctrl+R, and word-movement for free
instead of rebuilding them. Needs a real test before deciding, not an
assumption either way -- flagged here specifically so this doesn't
get silently redecided the same way vterm_fb's tradeoff was, without
re-examining whether it still applies.

One shared-state detail from `readline`'s own Kconfig help text worth
noting: command history lives in one in-memory array shared by every
`readline()` caller in a FLAT build. If NSH and vaporshell ever ran
side by side, they'd share a history array. Probably irrelevant if
vaporshell fully replaces NSH's role rather than coexisting with it,
but worth knowing before assuming isolated history "just works."

## Architecture decision: parser and execution engine

**Decided:** a bash/fish-inspired shell aiming for real POSIX/bash
syntax and behavior where practical, not a custom Lua-syntax shell.
The Lua-as-shell-language idea (Xonsh/Nushell/PowerShell-style --
Lua's own syntax at the prompt, `vapor.*` for process control) was
considered and set aside: a non-POSIX syntax would cost about as much
custom parsing/lexing work as a real grammar, without the payoff of
actually being POSIX/bash-compatible. Execution stays in C via
`posix_spawnp`/pipes/the multicall table -- no second language
runtime in the execution path.

A real third-party option exists for the parser, once one is needed
beyond the whitespace/quote tokenizing Milestone 1 uses:
[`mrsh`](https://mrsh.sh) (emersion, MIT, C99) is a strict POSIX shell
whose parser and AST are explicitly exposed as `libmrsh`, a standalone
public interface -- its own stated purpose is being "a library to
build more elaborate shells," not just a monolithic shell binary.
`mrsh -n script.sh` dumps the parsed AST without executing it,
confirming the parser and interpreter are genuinely separable -- we'd
want the former (real POSIX grammar: pipes, redirection, quoting,
control flow) and write our own executor tied to `posix_spawn`/the
multicall table/`vapor`, not adopt mrsh's own execution engine. Real
caveats: long quiet stretches in its history (most activity
2018-2022), links `librt`, Meson-first build needing adaptation into
this repo's Makefile/Kconfig shape -- same class of porting spike as
toybox, not assumed to just work until actually tried.

**`system()`/`os.execute()`, confirmed rather than assumed:** checked
directly in `apps/system/system/system.c`. The default path is
genuinely hardcoded -- `task_spawn("system", nsh_system, ...)` calls
NSH's own command function directly, no name resolution involved at
all. But NuttX ships a real, already-built escape hatch:
`CONFIG_SYSTEM_SYSTEM_SHPATH`, which switches `system()` to a real
`posix_spawn()` against whatever program name that's set to, calling
it as `{shpath, "-c", cmd, NULL}` -- the exact convention
`vaporshell -c` now implements. The name resolves through NuttX's
binfmt loader chain (`binfmt/builtin.c` matches against the compiled-
in builtin-apps table -- confirmed by reading it directly), the same
mechanism NSH itself uses to resolve command names, so no new
plumbing is needed there. Redirecting `system()`/`os.execute()` here
is just `kconfig-tweak --set-str CONFIG_SYSTEM_SYSTEM_SHPATH
vaporshell` once vaporshell's bareword-command support is solid
enough that things calling `system("some nsh command")` expecting
NSH's own syntax don't quietly break.

## Feature list

### Core execution

- [x] PATH resolution (`posix_spawnp` + `CONFIG_LIBC_ENVPATH`)
- [x] Program execution (`posix_spawn`, not `fork`+`exec`)
- [ ] Multicall dispatch table: `{name -> entry point, synthesized argv[0]}`,
      resolved before falling back to PATH search. This is the actual
      mechanism that makes toybox usable as native-feeling commands
      (`ls`, `cp`, ...) instead of typing `toybox ls` -- see the
      toybox/vaporshell discussion for why this needs to live in the
      shell rather than as N generated stub binaries.
- [x] Builtins -- `cd` implemented (mutates the shell's own state, so
      it can never be a spawned program regardless of how good
      NuttX's spawn story is). `export`, others: not yet.
- [x] `$?` (last exit status) -- shell-internal bookkeeping, no OS
      equivalent to lean on.
- [x] `-c <command>` non-interactive mode -- also what
      `CONFIG_SYSTEM_SYSTEM_SHPATH` needs to redirect `system()`/
      `os.execute()` here instead of NSH (see "Architecture decision"
      above); not built for that alone, any real shell needs this.

**Confirmed while implementing, worth being explicit about:** checked
the actual generated `apps/builtin/builtin_list.h` from a real build
-- NSH's own commands (`ls`, `cat`, `pwd`, `cd`, ...) are internal to
`nshlib`'s own command table, not separate entries in the builtin-apps
table `posix_spawn` resolves against. Right now, only separately-
registered `apps/external` programs (`vhello`, `portable_wc`,
`portable_cat`, `vlua`, `vi`, `vaporshell` itself) are actually
spawnable from vaporshell. Typing `ls` fails with "No such file or
directory" until toybox (or something like it) exists as real,
separately-spawnable programs -- not a bug, the actual current state,
and a concrete reason the toybox port matters architecturally, not
just for command coverage.

### Environment / variables

- [ ] `$PATH`, `$SHELL`, `$USER`, `$PWD` as real environment variables
- [ ] Dynamic prompt, built from shell-internal state (cwd, exit
      status, ...) -- pure string interpolation, no OS dependency

### Comfort NSH lacks

- [ ] rc file for configuration (aliases, prompt format, env
      defaults). Note this is genuinely two different stories right
      now: on sim, hostfs-backed `/data` already works today and could
      hold this immediately; on real hardware, persistence depends on
      the littlefs/FAT32 backends the README's own ROADMAP still marks
      `[WIP]`/unstarted. Fine to build against `/data` on sim first,
      just don't assume the same path is available yet on ESP32/RP2040.
- [ ] History navigation (`Up`/`Down`, `Ctrl+P`/`Ctrl+N`) -- see "Line
      editing" above, this may be substantially free depending on how
      that's resolved
- [ ] Tab completion, for both PATH commands and filesystem paths --
      new work either way; needs the multicall table (for commands)
      and `opendir`/`readdir` (for paths, both real per `vapor-api.md`'s
      own confirmed-gaps section on the Lua side)
- [ ] `Ctrl+L` (clear screen) -- straightforward, shell-internal
- [ ] `Ctrl+C` (interrupt the running foreground child) -- works
      against a single child directly via its pid; without process
      groups, a multi-stage pipeline can't be interrupted as one unit
      the normal way, only by signaling each spawned pid individually.
      Worth designing for explicitly rather than discovering the gap
      later.
- [ ] `Ctrl+A`/`Ctrl+E` (line start/end) -- straightforward cursor
      movement, shell-internal
- [ ] `Ctrl+Shift+C`/`Ctrl+Shift+V` (copy/paste) -- **open question,
      not a settled feature.** On sim, this only means something if
      it's targeting the X11 window `vterm_fb` renders into directly,
      and keyboard input isn't even captured from that window today
      (input is forwarded from the host terminal you launched
      `./nuttx` from -- see `vaporterm.md`'s staged input plan). Pasting
      into that *host terminal* already works today, for free, with no
      vaporshell-specific work, since it arrives as ordinary forwarded
      bytes. On ESP32/RP2040 with a physical keyboard, "clipboard" may
      not correspond to anything real at all. Needs a decision on what
      this feature actually means per-target before it's designed, not
      after.

## Toybox port: spike results

A real spike, not just reading source -- vendored toybox upstream,
generated its own build config for a minimal 4-applet set (`true`,
`false`, `echo`, `pwd`), and compiled the actual generated sources
against NuttX's real headers.

**Multicall dispatch confirmed, no toybox patches needed for this
part.** Read `main.c` directly: it inspects `basename(argv[0])`,
looks it up in a build-generated `toy_list[]` table (name -> applet
`_main` function), and dispatches -- the standard multicall pattern.
Checked NuttX's own spawn chain (`binfmt_exec.c` -> `binfmt/builtin.c`)
confirms `argv[]` passes through from caller to the started task's
`main()` untouched -- nothing overwrites `argv[0]` with the resolved
program name. So vaporshell's multicall table works exactly as
designed: `posix_spawnp(&pid, "toybox", ..., argv, environ)` with
`argv[0]` set to whatever applet name matched (`"ls"`, `"cp"`, ...)
correctly reaches that applet's `_main()`, the same way a real Unix
symlink-based multicall install would, just resolved by vaporshell's
own table instead of the filesystem.

**Two real bugs found and fixed in toybox's own `lib/portability.h`**
(patch kept separately, against toybox upstream, not this repo --
worth submitting there too once proven out further):
- Its generic (non-Apple/BSD) branch assumes `struct statfs` is
  already visible via some transitive include, true on glibc, not
  true on NuttX's more strictly-scoped headers -- needed an explicit
  `#include <sys/statfs.h>`.
- Once visible, NuttX's `struct statfs` (checked directly,
  `sys/statfs.h`) has no `f_frsize` field at all, unlike Linux --
  needed a NuttX-specific case using `f_bsize` for both, same as the
  pre-`f_frsize` Unix convention.

**Current real blocker, confirmed not assumed:** `paths.h` (BSD-
derived, provides `_PATH_DEFPATH` and friends) doesn't exist
anywhere in NuttX's tree at all. Toybox's `toys.h` includes it
unconditionally. Needs a small compatibility header providing
whatever subset of `_PATH_*` macros toybox's code actually
references -- scoped, not a deep architectural problem, just the
next concrete thing to solve.

Also resolved along the way, worth remembering for next time rather
than re-discovering: NuttX's own math library headers
(`libs/libm/newlib/include/math.h` and its `machine/ieeefp.h`) aren't
copied into the top-level `include/` until a build actually reaches
that step -- an incomplete build's `include/` directory will be
missing `math.h` even though NuttX genuinely has it.

## Open questions

- Does `READLINE_EDIT=y` + a narrow end-of-line-echo patch actually
  work cleanly for vaporshell, or does something else in that branch
  also assume NSH-specific behavior we'd need to rip out? Needs a real
  test, not a read of the source alone.
- Multicall dispatch table format/ownership -- generated from toybox's
  own applet list at build time, or hand-maintained? Affects how much
  work it is to track toybox upstream changes later.
- Where vaporshell's rc file lives on sim right now (`/data/...`,
  hostfs-backed) vs. where it should live once real hardware storage
  exists -- worth deciding the sim-only interim path explicitly so it
  doesn't quietly become the permanent one.

## Milestones (proposed, mirroring `vaporterm.md`'s staging)

1. Core loop: read a line (reusing `readline_common.c`, decision on
   `READLINE_EDIT` pending the test above), tokenize (whitespace +
   basic quoting only, no expansion yet), resolve PATH or the
   multicall table, `posix_spawn`, wait, print `$?`. No pipes,
   redirection, or rc file yet -- the smallest thing that can run a
   real command end to end.
2. Redirection and pipes (`dup2`, `pipe`) -- proven primitives, mostly
   sequencing work at this point.
3. Comfort layer: dynamic prompt, rc file (sim/`/data` first), tab
   completion.
4. `Ctrl+C`/`Ctrl+L`/`Ctrl+A`/`Ctrl+E`, history (contingent on the
   `READLINE_EDIT` decision above).
5. Clipboard -- only after the open question above is actually
   answered, not before.
