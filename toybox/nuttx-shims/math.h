#ifndef NUTTX_SHIM_MATH_H
#define NUTTX_SHIM_MATH_H
// Minimal math.h for NuttX. Confirmed by grepping this project's full
// 20-file toybox scope: fabs() and sin() are the ONLY math.h symbols
// referenced anywhere in it, both from a single call site in
// lib/hash.c (SHA1 round-constant setup), itself inside a runtime
// `if (CFG_TOYBOX_FLOAT)` check -- and CFG_TOYBOX_FLOAT is 0 in this
// project's generated/config.h, so that call is unreachable for the
// current true/false/echo/pwd applet set.
//
// fabs() is trivial for any IEEE754 double, and GCC already recognizes
// it as a compiler intrinsic (confirmed: without any declaration at
// all, GCC still treats calls to `fabs` as its own builtin, just warns
// the implicit declaration doesn't match). A plain prototype is enough
// to satisfy that match -- no hand-rolled body needed, and no shim
// implementation to be wrong. Providing a real inline body here (an
// earlier version of this shim did) shadows GCC's own builtin instead.
double fabs(double x);

// sin() is a genuine transcendental function. Hand-rolling an
// approximation here would be exactly the kind of unverified,
// possibly-subtly-wrong implementation this project avoids -- so this
// is a DECLARATION ONLY, no body. Whether that's sufficient depends on
// whether the final link actually needs a resolvable `sin` symbol,
// which depends on whether the linker's --gc-sections (toybox is
// built with -ffunction-sections -fdata-sections) eliminates the
// otherwise-unreachable lib/hash.c:hash_by_name() for this applet set
// -- NOT verified here, only compile-checked. If the real link fails
// with "undefined reference to sin", that's the next real thing to
// solve (likely: expand this shim's scope, or reconsider whether this
// applet set can avoid pulling in lib/hash.c's float path at all).
double sin(double x);
#endif
