# patches/

Small, targeted patches to upstream, pinned repos (currently just
`nuttx-apps`) that `setup.sh` applies automatically, once, right after
cloning fresh -- not a fork of the upstream repo, since the changes
here are narrow and specific enough that a full fork's own ongoing
maintenance (rebasing onto newer upstream commits, etc.) isn't worth
it yet. Revisit this convention if the number or size of patches here
grows much further; a real fork might become the better tradeoff at
that point.

Each patch's own top-of-file comment (in whichever `vaporOS-nuttx`
source called `git apply` on it -- currently `setup.sh`) explains what
it does and why it isn't upstream instead.
