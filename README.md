# vaporOS-nuttx

Experimental vaporOS foundation built on [Apache NuttX](https://nuttx.apache.org/)
instead of Zephyr. This is a separate track from the original
[vaporOS](https://github.com/tibocub/vaporOS) repo, which stays intact and
untouched while this is evaluated.

## Why NuttX

Real POSIX conformance out of the box -- `chdir`/`getcwd`, `lseek`,
`dup`/`dup2`, `fcntl`, `chmod`/`chown` all work without hand-building a
compatibility layer, unlike Zephyr where several of these are simply absent.
NuttX also ships an in-tree Lua interpreter and a POSIX-shaped
(`open`/`read`/`write`/`ioctl` on `/dev/*`) device driver model, both directly
relevant to vaporOS's ComputerCraft-inspired goals.

The plan is to mobilize as much of this as possible directly -- NSH as the
shell, NuttX's own VFS and filesystem support, the in-tree Lua interpreter --
rather than rebuild what NuttX already provides well.

## Getting started

No real hardware needed to start. NuttX has its own simulator (`sim`
target) that runs as a native host binary -- this is what `setup.sh` builds
by default.

```
./setup.sh
```

This clones `nuttx` and `apps` (pinned to known-good commits, see the top of
the script) as siblings of this repo, symlinks this repo in as `apps/external`
(NuttX's supported mechanism for out-of-tree custom apps -- see
`apps/README.md`, "Adding Applications Outside the Apps Directory"), enables
this repo's apps, and builds the `sim:nsh` config.

```
../nuttx/nuttx
```

boots into a real NSH shell, entirely on your machine, no board required.

## Layout

```
vaporOS-nuttx/
  vhello/       proof-of-concept app: confirms the apps/external
                mechanism actually reaches this repo and a custom
                command shows up in NSH (`Builtin Apps: ... vhello`)
  setup.sh      clones nuttx+apps, wires this repo in, builds sim:nsh
  Makefile      required by NuttX's app-directory convention
                (delegates to apps/Directory.mk)
  Make.defs     registers this repo's apps with NuttX's build
  .gitignore    excludes Kconfig/.kconfig -- these get auto-generated
                by NuttX's mkkconfig every time this repo is symlinked
                in as apps/external and configured; never hand-edit
                them (their own header says so)
```

Each vaporOS command/app gets its own subdirectory here, following the
same `Makefile`/`Kconfig`/`<name>_main.c` shape as `vhello/` -- this
mirrors NuttX's own convention (see `apps/examples/hello/` upstream) so
nothing about the pattern is vaporOS-specific.

## Status

Early evaluation. `vhello` is a minimal proof that the toolchain and the
apps/external mechanism work end-to-end -- not a real vaporOS command yet.
