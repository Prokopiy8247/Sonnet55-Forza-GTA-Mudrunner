<#
.SYNOPSIS
  Art-pass reference screenshot set (Halcyon Bay): 18 fixed views shot in ONE Godot session (gta/tests/art_batch.gd).
.USAGE (from the project root)
  powershell -NoProfile -File tools\art_shots.ps1 -Tag after                    # all reference views -> screenshots\art\after_<view>.png
  powershell -NoProfile -File tools\art_shots.ps1 -Tag t1 -Only spawn_1200,car_night
  powershell -NoProfile -File tools\art_shots.ps1 -Tag t1 -Only x_cloudy,x_park  # extra tuning views (x_*), see art_batch.gd VIEWS
  -EnvOver 'tonemap_mode:3,tonemap_white:6' applies numeric Environment property overrides (tuning experiments).
  Add -Hud to keep the HUD in the frame. -Settle <sec> = wait per view (default 2.2). Window size = -Resolution (default 1600x900).
  View names / cameras / hours / weather are in gta/tests/art_batch.gd (VIEWS). Perf probe: tools\art_perf.ps1.
#>
param(
	[string]$Tag = 'after',
	[string[]]$Only = @(),
	[string]$Resolution = '1600x900',
	[double]$Settle = 2.2,
	[string]$EnvOver = '',
	[switch]$NoShadow,
	[switch]$Hud
)
$gd = Join-Path $PSScriptRoot 'gd.ps1'
$ga = "--exec=res://gta/tests/art_batch.gd --no-traffic --no-peds --tag=$Tag --settle=$Settle"
if ($Only.Count -gt 0) { $ga += " --views=" + ($Only -join ',') }
if ($Hud) { $ga += ' --hud' }
if ($NoShadow) { $ga += ' --noshadow' }
if ($EnvOver -ne '') { $ga += " --env=$EnvOver" }
$r = & powershell -NoProfile -File $gd game -Seconds 900 -Resolution $Resolution -GameArgs $ga
$r | Select-String 'TEST art|SCRIPT ERROR|Parse Error|ERROR' | Select-Object -First 80 | ForEach-Object { $_.Line }
