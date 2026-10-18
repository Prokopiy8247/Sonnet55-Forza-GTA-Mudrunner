<#
.SYNOPSIS
  Boots the game on a map (windowed 1280x720), drives the placeholder/real car for a few seconds with scripted input, prints the
  fixed-step physics statistics, takes a HighResShot and quits. Verifies from the log that the core systems came up.

.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/game_smoke.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/game_smoke.ps1 -Map /Game/Forza/Maps/Main -DriveSeconds 15 -LogName game_main
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/game_smoke.ps1 -Extra "roam delay 5 car 3, roam delay 6 ue HighResShot 1280x720"

  Exit code 0 = all checks passed. The screenshot path is printed (view it with the Read tool).
  Why 'roam delay': -ExecCmds runs every command in the very first frame and has no "wait"; the Roam console's `delay <s> <cmd>`
  schedules on the real-time ticker. -ExecCmds separates commands by COMMAS (not semicolons).
#>
param(
  [string]$Map = "/Game/Forza/Maps/L_Test",
  [string]$LogName = "game_smoke",
  [int]$DriveSeconds = 8,
  [string]$Throttle = "0.5",
  [string]$Steer = "0.0",
  [string]$Extra = "",
  [int]$TimeoutSec = 900
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runner = Join-Path $root "Tools\ue_cmd.ps1"
$shotDir = Join-Path $root "Saved\Screenshots\WindowsEditor"
$start = Get-Date

$cmds = @(
  "roam delay 3 drive $Throttle $Steer",
  "roam delay $DriveSeconds phys",
  "roam delay $($DriveSeconds + 0.5) ue HighResShot 1280x720"
)
if ($Extra -ne "") { $cmds += $Extra }
$cmds += "roam delay $($DriveSeconds + 4) ue Quit"
$execCmds = $cmds -join ", "

& powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Game -Map $Map -ResX 1280 -ResY 720 -ExecCmds $execCmds -LogName $LogName -TimeoutSec $TimeoutSec | Out-Null
$exit = $LASTEXITCODE
$log = Join-Path $root "Tools\Logs\$LogName.log"
if (-not (Test-Path $log)) { Write-Host "NO LOG: $log"; exit 2 }
$text = Get-Content $log -Raw

function Check([string]$name, [bool]$ok, [string]$detail = "") {
  Write-Host ("{0,-44} {1} {2}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" }), $detail)
  return $ok
}

$allOk = $true
$allOk = (Check "process exit code" ($exit -eq 0) "($exit)") -and $allOk
$allOk = (Check "game instance initialised" ($text -match "ROAM_GAME_INSTANCE_INIT")) -and $allOk
$allOk = (Check "game mode spawned the vehicle" ($text -match "ROAM_SPAWN car=")) -and $allOk
$allOk = (Check "vehicle begin play" ($text -match "ROAM_VEHICLE_READY")) -and $allOk
$allOk = (Check "HUD shell ready" ($text -match "ROAM_UI_READY")) -and $allOk
$phys = [regex]::Match($text, "ROAM_PHYS_STEPS steps=(\d+) avgHz=([\d\.]+)")
$allOk = (Check "fixed-step physics callback runs" ($phys.Success -and [double]$phys.Groups[2].Value -gt 100) $(if ($phys.Success) { "$($phys.Groups[1].Value) steps, $($phys.Groups[2].Value) Hz" } else { "no stats" })) -and $allOk
$crash = $text -match "Fatal error|Assertion failed|Unhandled Exception"
$allOk = (Check "no crash / assertion in the log" (-not $crash)) -and $allOk

$shot = Get-ChildItem $shotDir -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start } | Sort-Object LastWriteTime | Select-Object -Last 1
$allOk = (Check "screenshot written" ($null -ne $shot) $(if ($shot) { $shot.FullName } else { "" })) -and $allOk
Write-Host "---- key log lines ----"
Select-String -Path $log -Pattern "ROAM_(SPAWN|CAR_APPLIED|VEHICLE_READY|UI_READY|PHYS_STEPS|GROUND_DROP)" | ForEach-Object { Write-Host $_.Line }
if ($allOk) { exit 0 } else { exit 1 }
