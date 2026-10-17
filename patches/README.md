# patches/

vaporOS's changes to NuttX and nuttx-apps, as one patch per concern:

    patches/nuttx/        -> applied to ../nuttx        (apache/nuttx, releases/13.0)
    patches/nuttx-apps/   -> applied to ../nuttx-apps   (apache/nuttx-apps, releases/13.0)

`tools/apply-patches.sh` applies them, idempotently (an already-applied patch is
recognised and skipped); `setup.sh` runs it, and so does every build for the
patches the board lists in its `[patches]` section.

**Why each patch exists, how sure we are, and whether it could be contributed
upstream: [UPSTREAM.md](UPSTREAM.md).** Each patch file also starts with the same
information (Problem / Evidence / Fix / Upstream) before its first `diff`, which
`git apply` ignores.

To change a patch: edit the tree in `../nuttx` (or `../nuttx-apps`), then regenerate
only that patch's files with `git diff -- <files> > patches/<repo>/<name>.patch`,
keeping its header. Check that every patch still matches the tree with
`git -C ../nuttx apply -R --check ../vaporOS/patches/nuttx/<name>.patch`.
