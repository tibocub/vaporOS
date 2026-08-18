# vaporOS-nuttx/setup.ps1 -- Windows equivalent of setup.sh.
# Clones nuttx+apps, wires this repo in as apps/external. Does not
# build -- build from WSL/MSYS2/Cygwin with `make -f dev.mk build`
# (untested on real Windows -- report back if this doesn't work).
$ErrorActionPreference = "Stop"

$NuttxCommit = "a0fcbb7957e916d03e346de9bdf5d1be2dd4ccd0"
$AppsCommit = "569d8f31dbd7934a7e20606db311fcfb1e86b59d"

$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $Dir)

if (-not (Test-Path "nuttx")) {
    git clone https://github.com/apache/nuttx.git
    git -C nuttx checkout $NuttxCommit
}

if (-not (Test-Path "apps")) {
    git clone https://github.com/apache/nuttx-apps.git apps
    git -C apps checkout $AppsCommit
}

if (-not (Test-Path "apps\external")) {
    Write-Host "Create apps\external as a symlink to this repo, then re-run:"
    Write-Host "  New-Item -ItemType SymbolicLink -Path apps\external -Target `"$Dir`""
    Write-Host "(needs an elevated PowerShell), or from WSL/MSYS2/Cygwin:"
    Write-Host "  ln -s <path-to-this-repo> apps/external"
    exit 1
}

Write-Host "Done. Build from WSL/MSYS2/Cygwin: make -f dev.mk build"
