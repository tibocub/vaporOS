include $(APPDIR)/Make.defs

PROGNAME  = $(CONFIG_VAPOROS_TOYBOX_PROGNAME)
PRIORITY  = $(CONFIG_VAPOROS_TOYBOX_PRIORITY)
STACKSIZE = $(CONFIG_VAPOROS_TOYBOX_STACKSIZE)
MODULE    = $(CONFIG_VAPOROS_TOYBOX)

# Vendored toybox (codeberg.org/landley/toybox, commit
# e76971b0a7919f13ce9c5eb4b194f93d8c8a9645) plus a NuttX portability
# patch (see docs/vaporshell.md) -- same "vendored source, not fetched
# dependency" approach as vterm/libvterm, for the same reason: no
# network fetch step to fail mid-build.
#
# generated/*.[ch] are PRE-GENERATED, not produced by this build.
# Toybox's own scripts/genconfig.sh + scripts/make.sh normally generate
# these on the build host from a .config applet selection -- doing that
# here would mean invoking $(HOSTCC) from inside this Makefile, which
# apps/external doesn't have a clean hook for. Vendoring the generated
# output directly is simpler and matches how vterm/libvterm is already
# handled. Real consequence: adding applets beyond this 4-command scope
# means regenerating generated/*.h on a host toybox checkout (with the
# new .config) and recommitting them here -- not something this build
# does automatically. See docs/vaporshell.md for the regeneration
# steps once that's needed.
CFLAGS += ${INCDIR_PREFIX}$(APPDIR)/external/toybox
CFLAGS += ${INCDIR_PREFIX}$(APPDIR)/external/toybox/nuttx-shims

# CRITICAL, and the actual root cause of a real build failure this had
# without it: apps/external builds do NOT pass -nostdinc (confirmed
# empirically -- dumped the real cc invocation via `make -n` against
# this Makefile). NuttX's own headers are found first via an earlier
# -isystem, but the *host's* /usr/include is still searched as a
# fallback for anything NuttX doesn't provide. Toybox's own
# portability.h uses __has_include(<utmpx.h>) to decide whether to
# include it -- NuttX has no utmpx.h at all, so without -nostdinc that
# probe finds the *host's* glibc utmpx.h instead (which assumes
# glibc's own __pid_t chain and fails to parse against NuttX's pid_t).
# lib/portability.h itself now also guards that one probe with an
# explicit __NuttX__ check as belt-and-suspenders, since __has_include
# alone can't tell "NuttX genuinely lacks this" apart from "this
# apps/external build happens to leak host headers" -- but -nostdinc
# stays here too, since removing it reopens a *different* class of the
# same problem: __GLIBC__ (defined by glibc's own headers, not the
# compiler) gets transitively defined once host headers are reachable
# again, which silently selects portability.c's Linux-syscall-based
# timer code instead of NuttX's. Once host headers are blocked, the
# compiler's own freestanding headers (stdarg.h and friends, which
# NuttX's include/ doesn't provide -- confirmed directly, only
# stddef.h/float.h are NuttX's own) have to be added back explicitly.
CFLAGS += -nostdinc
CFLAGS += ${INCDIR_PREFIX}$(shell $(CC) -print-file-name=include)

CSRCS  = lib/args.c
CSRCS += lib/commas.c
CSRCS += lib/deflate.c
CSRCS += lib/dirtree.c
CSRCS += lib/elf.c
CSRCS += lib/env.c
CSRCS += lib/hash.c
CSRCS += lib/lib.c
CSRCS += lib/llist.c
CSRCS += lib/net.c
CSRCS += lib/password.c
CSRCS += lib/portability.c
CSRCS += lib/tty.c
CSRCS += lib/utf8.c
CSRCS += lib/xwrap.c

CSRCS += toys/posix/true.c
CSRCS += toys/posix/false.c
CSRCS += toys/posix/echo.c
CSRCS += toys/posix/pwd.c

# toybox's own main.c is compiled as a plain CSRCS file, not MAINSRC --
# its own "int main(argc, argv)" is left completely unrenamed (a
# normal, ordinary, un-exported function named "main"), never called
# by anyone; vapor_entry.c's toy_exec(argv+1) call is the real
# dispatch path. See vapor_entry.c's own comment for the full
# reasoning -- this is deliberate, not an oversight: toybox's own
# main() unconditionally calls its internal toybox_main() multiplexer,
# whose naming requirements collide with NuttX's own <PROGNAME>_main
# renaming convention if main.c is used as MAINSRC directly (confirmed
# directly by a real build).
CSRCS += main.c

MAINSRC = vapor_entry.c

include $(APPDIR)/Application.mk
