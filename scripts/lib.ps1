# Shared by build.ps1 and clean.ps1. Call from inside nuttx/.
# PowerShell translation of lib.sh -- see that file for why this
# exists (GitHub rate-limit risk from lua's tarball being deleted on
# every distclean otherwise).

function Invoke-DistcleanPreservingLua {
    $luaDir = "..\apps\interpreters\lua"
    $tarball = Get-ChildItem "$luaDir\v*.tar.gz" -ErrorAction SilentlyContinue | Select-Object -First 1
    $unpacked = "$luaDir\lua"

    if ($tarball) {
        Move-Item $tarball.FullName "$env:TEMP\vaporos-lua.tar.gz" -Force
    }
    if ((Test-Path $unpacked) -and (Test-Path "$unpacked\lualib.h")) {
        Remove-Item "$env:TEMP\vaporos-lua-dir" -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item $unpacked "$env:TEMP\vaporos-lua-dir" -Force
    } elseif (Test-Path $unpacked) {
        Remove-Item $unpacked -Recurse -Force  # incomplete/wrong layout, don't cache it
    }

    make distclean

    if (Test-Path "$env:TEMP\vaporos-lua.tar.gz") {
        Move-Item "$env:TEMP\vaporos-lua.tar.gz" "$luaDir\$($tarball.Name)" -Force
    }
    if (Test-Path "$env:TEMP\vaporos-lua-dir") {
        Move-Item "$env:TEMP\vaporos-lua-dir" $unpacked -Force
    }

    # Tarball present but never unpacked (e.g. manually placed): unpack it.
    # Handles both GitHub's flat layout and lua.org's src/ layout.
    if ($tarball -and -not (Test-Path "$unpacked\lualib.h")) {
        $ver = $tarball.Name -replace '^v','' -replace '\.tar\.gz$',''
        Push-Location $luaDir
        tar -xzf $tarball.Name
        if (Test-Path "lua-$ver\src") {
            Move-Item "lua-$ver\src\*.c", "lua-$ver\src\*.h" "lua-$ver\"
        }
        Move-Item "lua-$ver" "lua"
        Pop-Location
    }
}
