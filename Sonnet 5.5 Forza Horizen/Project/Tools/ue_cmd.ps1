<#
.SYNOPSIS
  Reproducible headless/windowed Unreal Editor runner for this project (UE 5.8, paths contain spaces).

.EXAMPLES
  # run a python script in the editor commandlet host and exit
  .\Tools\ue_cmd.ps1 -PythonScript Tools\ue\hello.py -LogName hello
  # run console commands (semicolon separated) in the editor, then quit
  .\Tools\ue_cmd.ps1 -ExecCmds "Automation RunTests Sonnet55Forza; Quit" -LogName tests
  # game run with a map, screenshots through ExecCmds
  .\Tools\ue_cmd.ps1 -Game -Map /Game/Forza/Maps/Main -ExecCmds "HighResShot 1920x1080; Quit" -LogName game
#>
param(
  [string]$PythonScript = "",
  [string]$ExecCmds = "",
  [string]$LogName = "ue_cmd",
  [int]$TimeoutSec = 1800,
  [string]$Map = "",
  [string]$ExtraArgs = "",
  [switch]$Game,        # run as -game (UnrealEditor.exe) instead of commandlet-style editor
  [switch]$Editor,      # run full UnrealEditor.exe (windowed) rather than -Cmd
  [switch]$NullRHI,
  [int]$ResX = 1920,
  [int]$ResY = 1080
)
$ErrorActionPreference = "Stop"
$root   = Split-Path -Parent $PSScriptRoot
$engine = "W:\Unreal Engine 5\UE_5.8\Engine\Binaries\Win64"
$proj   = Join-Path $root "Sonnet55Forza.uproject"
$logDir = Join-Path $root "Tools\Logs"
New-Item -ItemType Directory -Force $logDir | Out-Null
$log    = Join-Path $logDir "$LogName.log"

if ($Game -or $Editor) { $exe = Join-Path $engine "UnrealEditor.exe" } else { $exe = Join-Path $engine "UnrealEditor-Cmd.exe" }

$a = New-Object System.Collections.Generic.List[string]
$a.Add('"' + $proj + '"')
if ($Map -ne "") { $a.Add($Map) }
if ($Game) { $a.Add("-game"); $a.Add("-windowed"); $a.Add("-ResX=$ResX"); $a.Add("-ResY=$ResY"); $a.Add("-ForceRes"); $a.Add("-NoSound") }
if ($PythonScript -ne "") {
  $ps = $PythonScript
  if (-not [System.IO.Path]::IsPathRooted($ps)) { $ps = Join-Path $root $ps }
  $ps = $ps -replace '\\','/'   # UE's python arg parser mangles some backslash sequences (e.g. \ue)
  $a.Add('-ExecutePythonScript="' + $ps + '"')
}
if ($ExecCmds -ne "") { $a.Add('-ExecCmds="' + $ExecCmds + '"') }
$a.Add("-unattended"); $a.Add("-nosplash"); $a.Add("-nopause"); $a.Add("-stdout"); $a.Add("-FullStdOutLogOutput")
$a.Add('-abslog="' + $log + '"')
if ($NullRHI) { $a.Add("-nullrhi") }
if ($ExtraArgs -ne "") { $a.Add($ExtraArgs) }
$argLine = ($a -join " ")
Write-Host "EXE: $exe"
Write-Host "ARGS: $argLine"

# one editor/game/build per project folder at a time (shared mutex with build_editor.ps1)
$sha = [System.Security.Cryptography.SHA1]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLower()))) -replace '-','').Substring(0,12)
$mutex = New-Object System.Threading.Mutex($false, "Global\Roamline_UE_$hash")
# yield-to-us: a running persistent editor job server (Tools/ue/ue_job.ps1) is asked to quit so this run can start
if ($PythonScript -notlike "*materials_server.py*") {
  $jobBase = Join-Path $root "Saved\MatJobs"
  $srv = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*materials_server.py*" -and $_.CommandLine -like "*$root*" }
  if ($srv) { New-Item -ItemType Directory -Force $jobBase | Out-Null; New-Item -ItemType File -Force (Join-Path $jobBase "quit") | Out-Null; Write-Host "asked the editor job server to quit" }
}
Write-Host "Waiting for project mutex ..."
if (-not $mutex.WaitOne(3600 * 1000)) { Write-Host "Could not get project mutex"; exit 125 }
try {
  $p = Start-Process -FilePath $exe -ArgumentList $argLine -PassThru -WindowStyle Hidden `
         -RedirectStandardOutput ($log + ".stdout.txt") -RedirectStandardError ($log + ".stderr.txt")
  $null = $p.Handle   # cache the handle so ExitCode is available after exit
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    Write-Host "TIMEOUT after $TimeoutSec s - killing PID $($p.Id)"
    try { $p.Kill($true) } catch {}
    $code = 124
  } else { $code = $p.ExitCode }
} finally {
  $mutex.ReleaseMutex()
}
Write-Host "EXIT CODE: $code  LOG: $log"
exit $code
