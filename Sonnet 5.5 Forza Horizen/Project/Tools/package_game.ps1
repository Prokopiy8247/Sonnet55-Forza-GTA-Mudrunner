<#
.SYNOPSIS
  Build, cook, stage and archive a standalone Windows game of this project (Development configuration, pak file).
  Takes the per-project mutex (preempting the editor job server) so no editor runs while cooking.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/package_game.ps1
  -> W:\...\UnrealSonnet55Forza\Packaged\Windows\Sonnet55Forza.exe (and Sonnet55Forza\Binaries\Win64\Sonnet55Forza.exe)
#>
param(
  [string]$Config = "Development",
  [string]$Out = "",
  [string]$LogName = "package",
  [int]$MutexWaitSec = 3600
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ($Out -eq "") { $Out = Join-Path $root "Packaged" }
$proj = Join-Path $root "Sonnet55Forza.uproject"
$log  = Join-Path $root "Tools\Logs\$LogName.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
$uat = "W:\Unreal Engine 5\UE_5.8\Engine\Build\BatchFiles\RunUAT.bat"

$sha = [System.Security.Cryptography.SHA1]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLower()))) -replace '-','').Substring(0,12)
$mutex = New-Object System.Threading.Mutex($false, "Global\Roamline_UE_$hash")
$jobBase = Join-Path $root "Saved\MatJobs"
New-Item -ItemType Directory -Force $jobBase | Out-Null
Set-Content -Path (Join-Path $jobBase "build_lock") -Value (Get-Date).ToString("o")
$srv = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*materials_server.py*" -and $_.CommandLine -like "*$root*" }
if ($srv) { New-Item -ItemType File -Force (Join-Path $jobBase "quit") | Out-Null; Write-Host "asked the editor job server to quit" }
Write-Host "Waiting for project mutex ..."
if (-not $mutex.WaitOne($MutexWaitSec * 1000)) { Write-Host "Could not get project mutex"; exit 125 }
try {
  Write-Host "PACKAGE $Config -> $Out   (log: $log)"
  & $uat BuildCookRun "-project=$proj" -noP4 -platform=Win64 "-clientconfig=$Config" -build -cook -stage -pak -archive "-archivedirectory=$Out" -utf8output -unattended -nodebuginfo *>&1 | Out-File -FilePath $log -Encoding utf8
  $code = $LASTEXITCODE
} finally {
  $mutex.ReleaseMutex()
  Remove-Item (Join-Path $jobBase "build_lock") -ErrorAction SilentlyContinue
}
$lines = Get-Content $log
$lines | Select-String -Pattern "Error:|error C\d+|BUILD FAILED|ERROR:" | Select-Object -First 30 | ForEach-Object { Write-Host $_.Line }
$lines | Select-Object -Last 8 | ForEach-Object { Write-Host $_ }
Write-Host "PACKAGE EXIT CODE: $code"
exit $code
