# Package manager: design notes (DRAFT, no code yet)

Status 2026-10-27: ideas and open questions only. Nothing here is decided until it says so.
Context: [lua-runtime.md](lua-runtime.md) (module search path), [rp2040.md](rp2040.md) (RAM).

## What exists today

`require` searches `<script dir>/lua_modules`, then the system directory (`/flash/lib/lua` on the RP2040,
a mounted host folder on the sim), then the script's own directory. Installing a library means copying
`.lua` files into one of those. Native libraries (lfs, lpeg, cjson) are linked into the firmware and are
not packages.

## Constraints that shape the design

1. **RAM is the scarce resource** (about 187 KB free on the RP2040, a 24 KB task stack). Anything that runs
   on the device must be small and must not hold an index in memory.
2. **The RP2040 has no network.** Its only links are USB serial and, later, an SD card. Downloading on the
   device is an ESP32-class feature. The design must work offline first.
3. **No dynamic linking.** A package can be pure Lua or it can need a native library; the second kind can only
   be satisfied by what the firmware was built with.
4. **Flash is small and wears** (about 1 MB of littlefs on the RP2040).
5. **The same layout must work on the sim, on Linux/macOS/BSD hosts and on boards** (portability priority).

## Main idea: do the work on the host, keep the device dumb

Dependency resolution, downloading, version checks and building an index are all easy on a PC and expensive
on 187 KB. So split the job:

| part | where | size | does |
|---|---|---|---|
| package format and install layout | everywhere | spec only | what a package is, where files go |
| host tool | PC | any | fetch, resolve, verify, stage a tree, push it to a device or folder |
| device installer | board/sim | tiny Lua script | install/remove/list a *local* package archive or directory, check `requires` |
| registry | later | static files | an index to resolve names (can start as none) |

## Reuse before building

LuaRocks already exists, has thousands of pure-Lua packages and a rockspec format. Proposal: **do not write
a luarocks alternative first.** On the host run `luarocks --tree stage install <pkg>` and push the staged
tree. For that to work the search path only needs the LuaRocks tree layout added (`share/lua/5.4/?.lua`
and `?/init.lua`), a two-line change. We would build our own format only where LuaRocks cannot help:
packages that need vapor APIs, device-side install from SD card, and the "this board lacks lpeg" check.

Limits of reusing it: a rock with C code cannot be installed on a device (no dynamic linking), and LuaRocks
assumes it can run a compiler, so it will refuse or produce host-only binaries. The host tool must reject
those clearly.

## Package format (proposal)

A package is a directory or a tar/zip of one:

```
mypkg/
  package.lua        -- returns a table: name, version, description, license, deps, requires, files
  mypkg.lua          -- or mypkg/init.lua and submodules
  bin/tool.lua       -- optional commands (see Open questions)
```

`package.lua` is plain Lua (no new parser on a 24 KB stack; it is data, loaded with an empty environment):

```lua
return {
  name = "mypkg", version = "1.2.0",
  deps = { penlight = ">=1.13" },        -- other packages, resolved on the host
  requires = { "lpeg", "cjson" },        -- native libraries this firmware must provide
  api = 1,                               -- vapor API level it needs, if any
}
```

`requires` is checked on the device against `package.preload`, which is exactly the set of built-in native
libraries, so "install failed: this board has no lpeg" is cheap and accurate.

## Install layout and bookkeeping

- Global: `<system dir>/` gets the package's modules; a record `<system dir>/.pkg/<name>.lua` lists version,
  files and checksums, so remove and upgrade can delete exactly what was installed.
- Per project: `./lua_modules/` same layout, same records. Project copies win over system ones (already true).
- One version of a package per tree. Two projects that need different versions use their own `lua_modules`.
  This is the npm/luarocks compromise and it costs nothing on the device.
- Module name clashes between two packages are an install-time error (the records make this detectable).

## Integrity and trust

- Checksums of every file in the package record, verified by the host tool before pushing and by the device
  installer after writing (needs a small SHA-256; a few hundred bytes of Lua is too slow, so probably C in the
  firmware or a CRC32 as a first step).
- Signing is a later question. Be clear that packages run with the program's full privileges: there is no
  sandbox, and a Lua package can do anything `os`, `io` and the vapor API can.

## Bytecode (optional, later)

Installing precompiled, stripped bytecode (`luac -s`) saves flash and removes compile cost and RAM on the
device (we hit the limit compiling a 50 KB file). Bytecode is tied to the exact Lua version and number
format, which is one more reason to keep 64-bit numbers. Source stays the default; bytecode would be an
install option the host tool can produce.

## Phases

0. (done) Search path and system directory.
1. Add the LuaRocks tree layout to the search path; document "stage on host with luarocks, then copy".
2. A host script (`tools/vpkg`) that pushes a staged tree to a board (using `rp2040-send.py`) or to the sim's
   host folder, and rejects native-code rocks.
3. The `package.lua` format and the small device installer (Lua) for local archives, SD card or serial.
4. Network fetch on boards that have one; a static index (a git repo of `package.lua` files) if LuaRocks'
   own index is not good enough.

## Open questions

1. **Reuse LuaRocks or define our own manifest from the start?** My recommendation is reuse (phase 1-2) and add
   our manifest only when a real need appears. The risk is depending on a tool we do not control.
2. **Where do commands go?** If a package ships `bin/tool.lua`, something has to put it on the shell's PATH
   (vaporshell and tbx know nothing about Lua scripts yet). Related: `#!/usr/bin/env lua`.
3. **Is the sim's system directory the host's real library folder?** Sharing the host's `~/.luarocks` would let
   the sim use packages for free but mixes C rocks the sim cannot load.
4. **Which sources are first-class:** git URL, tarball URL, local path, SD card? Offline-first says local
   path first.
5. **Quotas and cleanup on a 1 MB flash:** do we need `vpkg gc`, size reporting, refusal to fill the disk?
6. **Native libraries as "packages":** should the build system (setup.sh/features) get a `requires`-aware way
   to add a C library, or stay a manual build-time feature? They are firmware, not installable, and that
   difference should be visible to users.
7. **Naming:** `vpkg`? Tied to whether it ends up as a vaporshell builtin or a Lua program.
