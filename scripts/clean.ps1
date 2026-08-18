# scripts/clean.ps1 -- called by `make -f dev.mk clean`.
$ErrorActionPreference = "Stop"
$Dir = Split-Path -Parent $PSScriptRoot
$Workspace = Split-Path -Parent $Dir
Set-Location $Workspace

if (-not (Test-Path "nuttx")) {
    Write-Host "nuttx\ doesn't exist -- nothing to clean."
    exit 0
}

. "$Dir\scripts\lib.ps1"
Set-Location nuttx

if (Test-Path ".config") {
    Invoke-DistcleanPreservingLua
} else {
    Write-Host "No .config -- nothing to clean."
}
