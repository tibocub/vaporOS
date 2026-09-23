# IDE / clangd setup

vaporOS's own build genuinely doesn't fit a standard, single-repo
clangd setup: source lives across five separate git repos
(`nuttx/`, `nuttx-apps/`, `vaporOS-nuttx/`, `vaporOS-coreutils/`,
`vaporshell/`, as siblings), headers are generated per-build
(`nuttx/include/nuttx/config.h` doesn't exist until you've configured
a board), and the build deliberately uses `-nostdinc` (see
`vapor-nostdinc.mk`'s own comment for why) so a plain `bear` capture
plus opening the folder isn't enough on its own. This is the real,
working setup -- confirmed directly, not guessed.

## One-time setup

1. Build normally first (`make -f dev.mk build sim:nsh`, or whichever
   board) -- this needs a real, working `nuttx/.config` to already
   exist.
2. From this repo (`vaporOS-nuttx/`), run:

   ```
   ./scripts/gen-compile-commands.sh
   ```

   This needs `bear` installed (`apt install bear` / `brew install
   bear`). It recompiles everything under the config from step 1 --
   see the script's own comment for exactly why a real rebuild is
   required here, not just running `bear` once yourself: bear only
   records commands that actually run, so anything already up to
   date from a prior build silently never appears in the database at
   all.
3. Re-run step 2 whenever you add a new source file, change which
   apps are enabled, or reconfigure the board -- same reasoning: the
   database only reflects what got compiled *while bear was
   watching*.

That's it for the database itself. `vaporOS-nuttx/.clangd`,
`vaporshell/.clangd`, and `vaporOS-coreutils/.clangd` already point
at `../nuttx/compile_commands.json` (`nuttx/` being a sibling of all
three, same as `setup.sh` itself already assumes) -- confirmed
directly this is enough for clangd to find the real database
regardless of which of these five repos your editor is actually
opened at, even though they're separate git repos, not nested under
one another.

## The one setting `.clangd` genuinely can't set for you

By default, clangd won't trust an arbitrary compiler path found
inside a compile_commands.json enough to query it for its own
default include behavior -- deliberately, since a project-committed
config file blindly executing whatever binary it names would be a
real, exploitable risk. This is `--query-driver`, and it has to be a
clangd *launch* argument, not something `.clangd` (or any other
project file) can carry -- confirmed directly, the hard way: without
it, clangd silently falls back to its own bundled, generic system
headers instead of the real `-nostdinc`/`-isystem`/`-I` flags
actually used to build this project, and every NuttX header (down to
`<nuttx/config.h>` itself) fails to resolve, which is almost
certainly the exact symptom you're seeing.

Add this once, wherever your editor configures clangd's own launch
arguments:

```
--query-driver=/usr/bin/cc,/usr/bin/gcc*,/usr/bin/clang*
```

(Widen or narrow the glob to match whatever `cc`/`gcc` actually
resolves to on your machine -- `which cc` will tell you.)

- **VS Code (clangd extension)**: Settings -> `clangd.arguments`,
  add `--query-driver=/usr/bin/cc,/usr/bin/gcc*,/usr/bin/clang*` as
  its own entry.
- **Neovim (nvim-lspconfig)**: pass it via the `cmd` table, e.g.
  `cmd = { "clangd", "--query-driver=/usr/bin/cc,/usr/bin/gcc*,/usr/bin/clang*" }`.
- **CLion**: Settings -> Languages & Frameworks -> C/C++ -> Clangd ->
  "Clangd command-line options".
- Any other editor: wherever it lets you pass clangd its own
  command-line arguments -- this is a clangd flag, not an editor- or
  extension-specific one, so the same value works everywhere.

## Why this can't just be automatic

This isn't a config file the project could have shipped and didn't:
`--query-driver` is a security-relevant clangd *launch* flag by
design, deliberately kept out of project-local config files clangd
would otherwise read and trust automatically. Everything else in
this setup *is* now automatic (`.clangd` in each repo, the generation
script) -- this one setting is a genuine, unavoidable, one-time
per-editor step, confirmed by testing clangd directly against this
project's own real compile_commands.json, both with and without it.

## Troubleshooting

- **Headers still unresolved after all of the above**: confirm
  `nuttx/compile_commands.json` actually exists and is recent
  (`ls -la`) -- if `gen-compile-commands.sh` hasn't been run since the
  last time you added a file, entries for it won't exist at all.
- **A specific new file's own headers don't resolve, everything else
  does**: that file has no entry in the database yet (see above) --
  re-run `gen-compile-commands.sh`.
- Relevant clangd docs, for anything not covered here:
  [troubleshooting](https://clangd.llvm.org/troubleshooting#cant-find-standard-library-headers-map-stdioh-etc),
  [config file reference](https://clangd.llvm.org/config#files).
