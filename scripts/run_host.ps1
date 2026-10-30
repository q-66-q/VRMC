param(
    [string]$HostAddress = "0.0.0.0",
    [string]$WindowTitle = "Minecraft",
    [string]$Video = "",
    [int]$Fps = 90,
    [int]$Bitrate = 90000,
    [switch]$H264
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$exe = Join-Path $root "build\bridge-windows\bin\win64\vrmc_host.exe"
if (-not (Test-Path $exe)) { throw "Host not built. Run pwsh .\scripts\build_bridge.ps1 -Configuration Release" }
 $hostArgs = @("--host", $HostAddress, "--window-title", $WindowTitle, "--fps", "$Fps", "--bitrate", "$Bitrate")
if ($Video) { $args += @("--video", $Video) }
if ($H264) { $args += "--h264" }
& $exe @hostArgs
