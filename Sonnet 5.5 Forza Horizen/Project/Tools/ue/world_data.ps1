<#
.SYNOPSIS
  Re-imports the generated world DATA into Unreal after Tools/world/build_world.py has produced new roads / regions / sites:
    1. regenerates Tools/ue/world_regions.json from region_id.r8 (plain python, deterministic, 8 s)
    2. job `world_build.py data`  -> /Game/Forza/Data/DA_RoadNetwork + DA_WorldDefinition (C++ importers; seconds once the editor job server runs)
    3. job `world_verify.py data` -> loads both assets back, prints counts / POI list / default-spawn road check
  Owner: F1-B.  Docs/Tech/WORLD_BUILD.md.  The landscape is NOT touched (use Tools/ue/world_build.py steps for that).

.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_data.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/world_data.ps1 -SkipRegions
#>
param(
  [switch]$SkipRegions,
  [int]$TimeoutSec = 1800
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$py = "W:\Blender\5.2\python\bin\python.exe"
$job = Join-Path $root "Tools\ue\ue_job.ps1"

if (-not $SkipRegions) {
  Write-Host "== regions =="
  & $py -I (Join-Path $root "Tools\ue\world_regions_gen.py")
  if ($LASTEXITCODE -ne 0) { Write-Host "world_regions_gen.py failed"; exit 1 }
}
Write-Host "== import (DA_RoadNetwork, DA_WorldDefinition) =="
& powershell -NoProfile -ExecutionPolicy Bypass -File $job "Tools/ue/world_build.py" -TimeoutSec $TimeoutSec -Args0 "data" -Filter "ROAM_WORLD|ROAM_ROADNET|ROAM_WORLDDEF|MATJOB_EXC|Error: .*(Roam|ROAM)|Traceback"
Write-Host "== verify =="
& powershell -NoProfile -ExecutionPolicy Bypass -File $job "Tools/ue/world_verify.py" -TimeoutSec $TimeoutSec -Args0 "data" -Filter "ROAM_VERIFY|MATJOB_EXC|Traceback"
