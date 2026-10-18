<#
.SYNOPSIS
  Teleport tour of the open world in a real game run (windowed 1920x1080, real RHI): `tp <poi>` + HighResShot per stop, optional frame-time
  chart while driving, then collects the screenshots into Saved/Screenshots/world_tour/<LogName>/NN_<poi>.png (view them with the Read tool).
  Owner: F1-B.  Docs/Tech/WORLD_BUILD.md

.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_tour.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_tour.ps1 -Pois "loop_start,crossroads" -LogName tour_a -Settle 5
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_tour.ps1 -Pois "" -DriveSeconds 40     # frame-rate run only

  Needs: /Game/Forza/Maps/L_Main saved, DA_WorldDefinition (POI ids: run `roam regions` or Tools/ue/world_verify.py data).
  Log markers to grep afterwards:  ROAM_CONSOLE / "teleported to" (ground z of every stop; z = 20000 means the ground trace missed),
  ROAM_GROUND_DROP (spawn), "LogChartCreation" / "FPSChart" (frame-rate summary), ROAM_PHYS_STEPS.
#>
param(
  [string]$Pois = "loop_start,highway_plateau,pass_switchbacks,great_bay_bridge,crossroads,summit_viewpoint,tidewick",
  [string]$Map = "/Game/Forza/Maps/L_Main",
  [string]$LogName = "world_tour",
  [double]$Settle = 4.0,          # seconds between teleport and screenshot (streaming + TSR/Lumen settle)
  [double]$StartDelay = 14.0,     # seconds before the first teleport (map load + first frames). Checkerboard terrain = a material failed to compile (see WORLD_BUILD.md section 7)
  [int]$DriveSeconds = 0,         # >0: after the tour start the frame chart, drive straight for this long, stop the chart
  [string]$DriveCommand = "drive 0.8 0",
  [string]$Extra = "",
  [int]$ResX = 1920,
  [int]$ResY = 1080,
  [int]$TimeoutSec = 1800
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runner = Join-Path $root "Tools\ue_cmd.ps1"
$shotDir = Join-Path $root "Saved\Screenshots\WindowsEditor"
$outDir = Join-Path $root "Saved\Screenshots\world_tour\$LogName"
New-Item -ItemType Directory -Force $outDir | Out-Null
$start = Get-Date

# the machine locale is Russian: "{0:0.0}" would print a decimal COMMA and -ExecCmds splits on commas - always format invariant
function F([double]$v) { return $v.ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture) }
$poiList = @($Pois -split "[,; ]+" | Where-Object { $_ -ne "" })
$cmds = New-Object System.Collections.Generic.List[string]
$t = $StartDelay
foreach ($poi in $poiList) {
  $cmds.Add(("roam delay {0} tp {1}" -f (F $t), $poi))
  $cmds.Add(("roam delay {0} ue HighResShot {1}x{2}" -f (F ($t + $Settle)), $ResX, $ResY))
  $t += $Settle + 1.5
}
if ($DriveSeconds -gt 0) {
  $cmds.Add(("roam delay {0} ue StartFPSChart" -f (F $t)))
  $cmds.Add(("roam delay {0} {1}" -f (F ($t + 0.2)), $DriveCommand))
  $cmds.Add(("roam delay {0} ue HighResShot {1}x{2}" -f (F ($t + $DriveSeconds * 0.5)), $ResX, $ResY))
  $cmds.Add(("roam delay {0} phys" -f (F ($t + $DriveSeconds))))
  $cmds.Add(("roam delay {0} ue StopFPSChart" -f (F ($t + $DriveSeconds + 0.3))))
  $t += $DriveSeconds + 1.0
}
if ($Extra -ne "") { $cmds.Add($Extra) }
$cmds.Add(("roam delay {0} ue Quit" -f (F ($t + 3.0))))
$execCmds = $cmds -join ", "
Write-Host "ExecCmds: $execCmds"

& powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Game -Map $Map -ResX $ResX -ResY $ResY -ExecCmds $execCmds -LogName $LogName -TimeoutSec $TimeoutSec | Out-Null
$exit = $LASTEXITCODE
$log = Join-Path $root "Tools\Logs\$LogName.log"
if (-not (Test-Path $log)) { Write-Host "NO LOG: $log"; exit 2 }
$text = Get-Content $log -Raw

# pair screenshots with stops (written in order)
$shots = @(Get-ChildItem $shotDir -Filter *.png -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start } | Sort-Object LastWriteTime)
$names = @($poiList)
if ($DriveSeconds -gt 0) { $names += "drive" }
# another agent's game run may have written screenshots into the same folder while we waited for the project mutex: keep the LAST N (ours)
if ($shots.Count -gt $names.Count -and $names.Count -gt 0) { $shots = @($shots | Select-Object -Last $names.Count) }
for ($i = 0; $i -lt $shots.Count; $i++) {
  $label = if ($i -lt $names.Count) { $names[$i] } else { "extra$i" }
  $dest = Join-Path $outDir ("{0:00}_{1}.png" -f ($i + 1), $label)
  Copy-Item $shots[$i].FullName $dest -Force
  Write-Host "SHOT $dest"
}
Write-Host "---- key log lines ----"
Select-String -Path $log -Pattern "ROAM_(SPAWN|GROUND_DROP|PHYS_STEPS|VEHICLE_READY)|teleported to|unknown poi|Fatal error|Assertion failed|LogChartCreation|FPSChart|Avg(erage)? FPS|MVP" | ForEach-Object { Write-Host $_.Line }
$crash = $text -match "Fatal error|Assertion failed|Unhandled Exception"
Write-Host ("exit code {0}, crash={1}, screenshots={2}/{3}" -f $exit, $crash, $shots.Count, $names.Count)
if ($crash -or $shots.Count -lt $names.Count) { exit 1 } else { exit 0 }
