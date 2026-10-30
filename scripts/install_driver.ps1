param(
    [string]$SteamVR = $env:STEAMVR_HOME,
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $SteamVR) {
    $SteamVR = "C:\Program Files (x86)\Steam\steamapps\common\SteamVR"
}
if (-not (Test-Path (Join-Path $SteamVR "bin\win64\vrserver.exe"))) {
    throw "SteamVR not found at $SteamVR. Pass -SteamVR 'C:\path\to\SteamVR'."
}
$source = Join-Path $root "build\bridge-windows\bin\win64"
if (-not (Test-Path (Join-Path $source "driver_vrmc.dll"))) {
    throw "Build the driver first: pwsh .\scripts\build_bridge.ps1 -Configuration Release"
}
$dest = Join-Path $SteamVR "drivers\vrmc"
if (Test-Path $dest) {
    if (-not $Force) { throw "$dest already exists; pass -Force to replace it." }
    $backup = "$dest.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dest $backup
    Write-Host "Backed up previous driver to $backup"
}
New-Item -ItemType Directory -Path (Join-Path $dest "bin\win64") -Force | Out-Null
Copy-Item (Join-Path $source "driver_vrmc.dll") (Join-Path $dest "bin\win64\driver_vrmc.dll")
Copy-Item (Join-Path $root "bridge\driver\resources\driver.vrdrivermanifest") $dest
Copy-Item (Join-Path $source "resources\*") $dest -Recurse -Force -ErrorAction SilentlyContinue
if (-not (Test-Path (Join-Path $dest "input\vrmc_knuckles_profile.json"))) {
    Copy-Item (Join-Path $root "bridge\driver\resources\input") (Join-Path $dest "input") -Recurse -Force
}

$settingsPath = Join-Path (Split-Path (Split-Path (Split-Path $SteamVR -Parent) -Parent) -Parent) "config\steamvr.vrsettings"
if (-not (Test-Path $settingsPath)) {
    Write-Warning "SteamVR settings not found at $settingsPath; enable the driver in SteamVR settings manually."
} else {
    Copy-Item $settingsPath "$settingsPath.vrmc-backup" -Force
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if (-not $settings.steamvr) {
        $settings | Add-Member -MemberType NoteProperty -Name steamvr -Value ([pscustomobject]@{})
    }
    $settings.steamvr | Add-Member -MemberType NoteProperty -Name activateMultipleDrivers -Value $true -Force
    if (-not $settings.driver_vrmc) {
        $settings | Add-Member -MemberType NoteProperty -Name driver_vrmc -Value ([pscustomobject]@{ enable = $true })
    } else {
        $settings.driver_vrmc | Add-Member -MemberType NoteProperty -Name enable -Value $true -Force
    }
    $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "Enabled driver_vrmc in $settingsPath (backup: $settingsPath.vrmc-backup)"
}
Write-Host "Restart SteamVR. Verify VRMC Virtual HMD and two controllers in the SteamVR device report."
