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
link-chmod-enosys         = 2
fork-call                 = 2
exec-family               = 2
arg-max-sysconf           = 2
paths-h                   = 1
has-include-probe         = 1
utmpx-h                   = 1
statfs-frsize             = 1
chroot-call               = 1
shared-globals            = 1
app-name-collision        = 1
regex-disabled            = 1
st-ino-identity           = 1
lseek-seekable-probe      = 1
strftime-zone-name        = 1
utsname-field-stride      = 1
signed-char-index         = 1
open-dot                  = 1
environ-null-when-empty   = 1
dot-path-in-fat           = 1

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
(1) st-ino-identity -- NuttX filesystems never fill st_ino/st_dev, so
    same_file() (lib/lib.c) is true for every pair of files: cp/mv
    refused every copy ("'dst' is 'src'") since batch 3. cp.c now
    compares resolved paths on NuttX (vapor_same_node(),
    lib/portability.c). test -ef and tail -F's dev/ino check have the
    same latent problem, not fixed yet.
(1) lseek-seekable-probe -- grep's binary check does read(256) +
    lseek(-len) on any fd where lseek(fd,0,SEEK_CUR) succeeds; on
    NuttX that is true for pipes too, so `cat f | grep x` lost its
    input. Fixed once by vapor_lseek() (nuttx-shims/vapor_libc.h):
    ESPIPE for FIFOs, sockets and ttys.
(2) link-chmod-enosys -- ln (link/symlink) and chmod fail with ENOSYS
    on the sim's FAT /tmp. Not worked around: the applets report the
    error, which is honest. Not yet checked on hostfs.
(1) strftime-zone-name -- date's default format and +%Z printed an empty
    zone (bare %Z: "bad format"). nx_strftime() in date.c expands %Z
    from tm_zone/tzname first.
(1) utsname-field-stride -- toybox uname walks struct utsname in
    sizeof(sysname) strides (assumes equal field sizes); NuttX's
    fields differ, so `uname -a`/`-m` printed garbage. uname.c now
    indexes fields by name. Not a compat-scan check: too specific.
(1) signed-char-index -- tr indexes TT.map[] with plain (signed) char:
    bytes >= 0x80 (always for tr -c) hit TT.map[-128..-1], a heap
    corruption that hung the whole sim on NuttX (harmless-looking on
    glibc). Cast to unsigned char. A real bug upstream too.
(2) fork-call -- vfork()/XVFORK() + exec in toybox's xpopen_setup() and
    xargs, where the child runs our code (redirections, environment)
    before exec. Replaced by vapor_spawn()
    (posix_spawnp + file actions; falls back to `tbx <name>` for tbx
    commands) in lib/portability.c. `timeout` needs the child callback
    and re-run-self paths and is not ported (neither is `time`, which uses
    XVFORK and wait4).
(2) exec-family -- execve()/execvp() in env.c and xexec(): run the
    target as a child and exit with its status instead.
(2) arg-max-sysconf -- xargs and find derived their batch size from
    sysconf(_SC_ARG_MAX) (4096 on NuttX) minus the environment: negative,
    "command too long". argv is copied onto the spawned task's small
    stack; VAPOR_ARGS_MAX (a quarter of the tbx stack) replaces it.
(1) open-dot -- find -exec's open(".") fails (trailing "." is never
    resolved; same class as the dirtree.c fixes). Uses the real cwd path.
(1) environ-null-when-empty -- get_environ_ptr() is NULL while a task has
    no environment variables (`env -i cmd`); every `for (e = environ; *e;
    ...)` dereferenced NULL and hung the sim. vapor_environ() in
    nuttx-shims/vapor_libc.h returns an empty array instead.
(1) dot-path-in-fat -- paths with a "." or ".." component inside a FAT
    directory fail with ENOTDIR (`cat sub/./q.txt`, `cat ../p.txt` from
    /tmp/sub). Reproduced on the sim's FAT /tmp; not fixed, cause
    unknown, not checked on hostfs. Breaks `find . -exec cat {} \;`
    from a subdirectory.

