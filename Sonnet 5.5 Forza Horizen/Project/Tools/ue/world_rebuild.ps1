<#
.SYNOPSIS
  ONE COMMAND that rebuilds the whole open world in Unreal from the current generator output (Content/Forza/World/Source/*):
    1. Tools/ue/world_regions.json  (python, 8 s)
    2. world_build.py  phys layers material data map landscape wp lighting ocean playerstart roads nanite save verify   (editor, ~25 min)
    3. prints the ROAM_WORLD / ROAM_VERIFY summary lines of the log
  Idempotent: the `map` step deletes and recreates /Game/Forza/Maps/L_Main; assets are overwritten in place.
  Owner: F1.  Docs/Tech/WORLD_BUILD.md

.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_rebuild.ps1                  # dedicated editor process (safest; start-up 2-8 min)
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_rebuild.ps1 -Job             # in the shared editor job server (no extra start when it runs)
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_rebuild.ps1 -Steps "map landscape wp lighting ocean playerstart nanite save verify"
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_rebuild.ps1 -NoNanite        # skips the Nanite landscape build (faster, only for quick looks)

  Afterwards: Tools/ue/world_tour.ps1 for screenshots + frame rate in a real game run.
#>
param(
  [string]$Steps = "phys layers material data map landscape wp lighting ocean playerstart roads nanite save verify",
  [switch]$Job,
  [switch]$SkipRegions,
  [switch]$NoNanite,
  [string]$LogName = "world_rebuild",
  [int]$TimeoutSec = 7200
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$py = "W:\Blender\5.2\python\bin\python.exe"
$t0 = Get-Date

if (-not $SkipRegions) {
  Write-Host "== regions =="
  $regionsOut = & $py -I (Join-Path $root "Tools\ue\world_regions_gen.py")
  if ($LASTEXITCODE -ne 0) { Write-Host "world_regions_gen.py failed"; exit 1 }
  Write-Host ($regionsOut | Select-Object -First 1)
}
$stepList = ($Steps -split "[,; ]+" | Where-Object { $_ -ne "" })
if ($NoNanite) { $stepList = $stepList | Where-Object { $_ -ne "nanite" }; $env:ROAM_WORLD_NANITE = "0" }
$csv = $stepList -join ","
Write-Host "== world_build: $csv =="
if ($Job) {
  $log = Join-Path $root "Tools\Logs\matserver.log"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "Tools\ue\ue_job.ps1") "Tools/ue/world_build.py" -TimeoutSec $TimeoutSec -Args0 $csv -Filter "ROAM_WORLD|ROAM_VERIFY|ROAM_LANDSCAPE|ROAM_ROADNET|ROAM_WORLDDEF|ROAM_WP|MATJOB_EXC|Traceback"
} else {
  $env:ROAM_WORLD_STEPS = $csv
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "Tools\ue_cmd.ps1") -PythonScript "Tools/ue/world_build.py" -LogName $LogName -TimeoutSec $TimeoutSec | Out-Null
  $log = Join-Path $root "Tools\Logs\$LogName.log"
  if (-not (Test-Path $log)) { Write-Host "NO LOG: $log"; exit 2 }
  Select-String -Path $log -Pattern "ROAM_WORLD|ROAM_VERIFY|ROAM_LANDSCAPE|ROAM_ROADNET|ROAM_WORLDDEF|ROAM_WP|STEP_FAILED|Traceback" |
    ForEach-Object { $_.Line } | Where-Object { $_ -notmatch "ROAM_VERIFY POI " }
}
Write-Host ("== done in {0:0} s ==" -f ((Get-Date) - $t0).TotalSeconds)
