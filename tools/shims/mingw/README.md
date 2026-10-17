# tools/shims/mingw

Wrappers that let NuttX's sim build with a mingw-w64 cross compiler on Linux
(spike, see docs/windows-sim.md). Put this directory on PATH and build with
`CROSSDEV=<triplet>- HOSTEXEEXT=`.

- `x86_64-w64-mingw32-cc`: NuttX asks for `$(CROSSDEV)cc`, mingw only ships `-gcc`;
  also drops `-U_WIN32` (see the comment in the script). Make a copy named
  `i686-w64-mingw32-cc` for the 32-bit target.
