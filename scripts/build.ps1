# scripts/build.ps1 [board] -- called by `make -f dev.mk build`.
# Untested on real Windows -- report back if this doesn't work.
#
# configure.sh itself is a real bash script shipped by upstream
# NuttX (not something reimplemented here) -- bash needs to be on
# PATH even on Windows (Git Bash/WSL/MSYS2) for that one call.
param([string]$Board = "nsh")

$ErrorActionPreference = "Stop"
$Dir = Split-Path -Parent $PSScriptRoot
$Workspace = Split-Path -Parent $Dir
Set-Location $Workspace

if (-not (Test-Path "apps\external")) {
    Write-Error "apps\external missing -- run setup.ps1 first."
    exit 1
}

. "$Dir\scripts\lib.ps1"
Set-Location nuttx

# Pick up any new app directories / config changes since last build.
if (Test-Path ".config") { Invoke-DistcleanPreservingLua }

switch ($Board) {
    "nxterm" {
        bash ./tools/configure.sh sim:nx11
        kconfig-tweak --disable CONFIG_EXAMPLES_NX
        kconfig-tweak --enable CONFIG_NXTERM
        kconfig-tweak --enable CONFIG_EXAMPLES_NXTERM
        kconfig-tweak --set-str CONFIG_INIT_ENTRYPOINT nxterm_main
        # CLE (NSH's default line editor) assumes a full VT100 terminal;
        # NxTerm's own VT100 support is minimal. NSH_READLINE avoids that.
        kconfig-tweak --enable CONFIG_NSH_READLINE
    }
    "vterm_fb" {
        bash ./tools/configure.sh sim:nx11
        kconfig-tweak --disable CONFIG_EXAMPLES_NX
        kconfig-tweak --set-str CONFIG_INIT_ENTRYPOINT vterm_fb_main
        kconfig-tweak --enable CONFIG_NSH_READLINE
        kconfig-tweak --enable CONFIG_PSEUDOTERM
        kconfig-tweak --enable CONFIG_DRIVERS_VIDEO
        kconfig-tweak --enable CONFIG_VIDEO_FB
        kconfig-tweak --enable CONFIG_SIM_FRAMEBUFFER
        kconfig-tweak --enable CONFIG_NXFONTS
        kconfig-tweak --enable CONFIG_NXFONT_X11_MISC_FIXED_10X20
        kconfig-tweak --set-val CONFIG_SIM_FBWIDTH 800
        kconfig-tweak --set-val CONFIG_SIM_FBHEIGHT 600
        kconfig-tweak --enable CONFIG_BOARDCTL_POWEROFF
        kconfig-tweak --disable CONFIG_DISABLE_MOUNTPOINT
        kconfig-tweak --enable CONFIG_FS_HOSTFS
        kconfig-tweak --enable CONFIG_SIM_HOSTFS
        kconfig-tweak --enable CONFIG_VAPOROS_VTERM_FB
    }
    default {
        bash ./tools/configure.sh "sim:$Board"
    }
}

kconfig-tweak --enable CONFIG_VAPOROS_VHELLO
kconfig-tweak --enable CONFIG_VAPOROS_PORTABLE_WC
kconfig-tweak --enable CONFIG_VAPOROS_PORTABLE_CAT
kconfig-tweak --enable CONFIG_VAPOROS_VLUA
kconfig-tweak --enable CONFIG_VAPOROS_VAPORSHELL
kconfig-tweak --enable CONFIG_VAPOROS_TOYBOX
kconfig-tweak --enable CONFIG_VAPOROS_VTERMTEST
kconfig-tweak --enable CONFIG_INTERPRETERS_LUA
kconfig-tweak --enable CONFIG_NSH_LIBRARY     # INTERPRETERS_LUA needs this; not auto-selected on every board
kconfig-tweak --enable CONFIG_SYSTEM_READLINE # nsh_script.c needs this declared
kconfig-tweak --enable CONFIG_SYSTEM_VI
kconfig-tweak --enable CONFIG_LIBC_STRERROR
kconfig-tweak --enable CONFIG_LIBC_LOCALTIME

make olddefconfig
make -j"$env:NUMBER_OF_PROCESSORS"

Write-Host "Done. Run with: make -f dev.mk run"
