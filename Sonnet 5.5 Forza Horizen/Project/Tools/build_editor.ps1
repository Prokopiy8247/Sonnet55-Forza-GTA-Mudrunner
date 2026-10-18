<#
.SYNOPSIS
  Build the project's C++ (Editor target by default) with UnrealBuildTool. Serialised per project folder (a named mutex
  shared with ue_cmd.ps1) so builds never run while an editor/commandlet from the same folder is running.

.EXAMPLES
  powershell -NoProfile -File Tools/build_editor.ps1                    # Sonnet55ForzaEditor Win64 Development
  powershell -NoProfile -File Tools/build_editor.ps1 -Target Sonnet55Forza -Config Development   # game target
  powershell -NoProfile -File Tools/build_editor.ps1 -LogName build_vehicle
Exit code 0 = success. Full log in Tools/Logs/<LogName>.log ; last lines printed. Errors are also summarised.
#>
param(
  [string]$Target = "Sonnet55ForzaEditor",
  [string]$Config = "Development",
  [string]$Platform = "Win64",
  [string]$LogName = "build",
  [int]$MutexWaitSec = 3600
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "Sonnet55Forza.uproject"
$log  = Join-Path $root "Tools\Logs\$LogName.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
$bat  = "W:\Unreal Engine 5\UE_5.8\Engine\Build\BatchFiles\Build.bat"

$sha = [System.Security.Cryptography.SHA1]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLower()))) -replace '-','').Substring(0,12)
$mutex = New-Object System.Threading.Mutex($false, "Global\Roamline_UE_$hash")
# preempt the persistent editor job server (Tools/ue/ue_job.ps1): it finishes its queue, quits and frees the mutex
$jobBase = Join-Path $root "Saved\MatJobs"
New-Item -ItemType Directory -Force $jobBase | Out-Null
$buildLock = Join-Path $jobBase "build_lock"
Set-Content -Path $buildLock -Value (Get-Date).ToString("o")
$srv = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*materials_server.py*" -and $_.CommandLine -like "*$root*" }
if ($srv) { New-Item -ItemType File -Force (Join-Path $jobBase "quit") | Out-Null; Write-Host "asked the editor job server to quit (build preempts it)" }
Write-Host "Waiting for project mutex ..."
if (-not $mutex.WaitOne($MutexWaitSec * 1000)) { Write-Host "Could not get project mutex"; exit 125 }
try {
  Write-Host "BUILD $Target $Platform $Config  (log: $log)"
  & $bat $Target $Platform $Config "-Project=$proj" -WaitMutex -NoHotReloadFromIDE *>&1 | Out-File -FilePath $log -Encoding utf8
  $code = $LASTEXITCODE
} finally {
  $mutex.ReleaseMutex()
  Remove-Item $buildLock -ErrorAction SilentlyContinue
}
$lines = Get-Content $log
$err = $lines | Select-String -Pattern "error C\d+|error LNK|fatal error|: error :|Result: Failed|UnrealHeaderTool.*error|Error: " | Select-Object -First 40
if ($err) { Write-Host "---- ERRORS ----"; $err | ForEach-Object { Write-Host $_.Line } }
$lines | Select-Object -Last 6 | ForEach-Object { Write-Host $_ }
Write-Host "BUILD EXIT CODE: $code"
exit $code
