# Compatibility fix log

Every compatibility fix *actually required* to compile and run a
program or library on vaporOS/NuttX gets logged here -- not everything
compat-scan merely flags , but confirmed, real fixes, verified against
the actual source before being logged.

This will help improve two things:

**Incompatibility detection**:
An issue that keeps showing will end up getting it own detection check
and will make compat-scan more reliable to estimate the compatibility
of a program with vaporOS without investing much time.

**Compatibility**
We'll be able to see clearly which parts of NuttX cause the more problems
and find which problems would be the more rewarding to solve.

## Format

One `[program]` section per ported program/library. Each entry is
`(count) issue-id -- note`, starting at the left margin (no leading
whitespace) -- a wrapped note's continuation lines are indented, which
is also how the parser tells a new entry apart from a continuation.
`issue-id` matches one of compat-scan's own check ids wherever
possible; an issue-id that *isn't* one yet is fine too -- that's
exactly the signal a new check might be worth adding. `count` is the
number of real, confirmed occurrences -- not a raw, unverified
compat-scan match count, which can include comments, help text, and
code that's never actually compiled for the applets/programs actually
in use.

The `---- COUNTER ----` section is entirely generated from `---- LOGS
----` below it -- run `python3 tools/update-compat-log.py` after
adding or editing entries by hand; never hand-edit COUNTER itself, it
gets fully overwritten on the next run. That same run also prints any
issue-id used in LOGS that doesn't match a known compat-scan check, as
a "not yet automated" list.

---- COUNTER ----------------------------
xattr                     = 11
raw-syscall               = 4
mount-table-introspection = 4
environ-replace           = 4
inotify                   = 3
getdelim-uninit-size      = 2
paths-h                   = 1
has-include-probe         = 1
utmpx-h                   = 1
statfs-frsize             = 1
chroot-call               = 1
shared-globals            = 1
app-name-collision        = 1
regex-disabled            = 1

---- LOGS -------------------------------
[toybox]
(11) xattr -- getxattr/setxattr/listxattr (backing cp -p/-a's
     attribute preservation, lib/portability.c); no NuttX equivalent
     at all, stubbed out.
(4) raw-syscall -- used as an escape hatch for timer_create/
    timer_settime/renameat2-equivalent functionality
    (lib/portability.c); no NuttX syscall() at all, needed
    NuttX-native replacements for each.
(4) mount-table-introspection -- mntent.h-style mount enumeration
    (lib/portability.c); no NuttX equivalent, stubbed.
(4) environ-replace -- direct assignment to environ (lib/env.c, a
    glibc/BSD whole-array-replacement pattern); NuttX only has
    per-variable setenv/unsetenv, rewritten against those.
(3) inotify -- file-watching support some applet infra assumes
    (lib/portability.c); no NuttX equivalent. Initially stubbed
    (error_exit); xnotify_*() now polls fstat() size/mtime every
    250 ms instead, which is what makes tail -f work.
(1) paths-h -- toys.h's own #include <paths.h>; no equivalent header
    on NuttX at all, needed a small compat shim for the _PATH_*
    macros actually referenced.
(1) has-include-probe -- the __has_include(<utmpx.h>) probe itself
    (lib/portability.h) assumed "reachable" meant "usable," which
    wasn't true even once the general host-header-leakage problem
    (see docs/c-posix-compatibility.md) was fixed; needed an explicit
    __NuttX__ guard on top of the general fix.
(1) utmpx-h -- confirmed absent from NuttX entirely.
(1) statfs-frsize -- struct statfs has no f_frsize on NuttX
    (lib/portability.h); the one real accessor rewritten to use
    f_bsize for both, matching the pre-f_frsize Unix convention.
(1) chroot-call -- confirmed absent on NuttX (lib/xwrap.c); the one
    real call site stubbed.
(2) getdelim-uninit-size -- getdelim()/getline() with a NULL buffer and
    an uninitialized size (lib/lib.c do_lines(), toys/posix/uniq.c).
    POSIX says *n is ignored then; NuttX mallocs *n bytes, so sort,
    cut and uniq silently printed nothing or one line depending on
    stack garbage. Fixed once in nuttx-shims/vapor_libc.h (zero *n
    when *lineptr is NULL) instead of at each call site.
(1) shared-globals -- toybox's toys/this/toybuf/libbuf are process-
    private on Unix; in NuttX's flat build concurrent tbx tasks
    (pipelines) share them. `yes | head > file` segfaulted the sim
    (head's read() clobbered yes's iovec array in toybuf). Now
    per-task heap contexts via task-local storage
    (nuttx-shims/vapor_ctx.h, needs CONFIG_TLS_TASK_NELEM >= 1).
(1) app-name-collision -- NuttX renames an app's main() to
    <PROGNAME>_main(); portable_wc's wc_main collided with toybox's
    wc applet at link time (`tbx wc` ran portable_wc_main, argc=0).
    portable_wc renamed to vwc.
(1) regex-disabled -- CONFIG_LIBC_REGEX (TRE) is off unless
    CONFIG_ALLOW_MIT_COMPONENTS is set; cut -F needs it, grep/sed
    will too. Enabled in scripts/build.sh.
