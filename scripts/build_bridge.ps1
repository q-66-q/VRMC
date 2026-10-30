param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $root
try {
    cmake -S bridge -B build/bridge-windows -G "Visual Studio 17 2022" -A x64
    cmake --build build/bridge-windows --config $Configuration --parallel
    ctest --test-dir build/bridge-windows -C $Configuration --output-on-failure
    Write-Host "Bridge build complete: build/bridge-windows/bin/win64"
} finally {
    Pop-Location
}
