<#
 Art-pass render cost probe: runs content_perf.gd (PERFRT cpu/gpu ms, draw calls) in 4 representative views.
 powershell -NoProfile -File tools\art_perf.ps1 -Tag before
#>
param([string]$Tag = 'after')
$gd = Join-Path $PSScriptRoot 'gd.ps1'
$views = [ordered]@{
	'spawn_day'    = '--time=9.5'
	'downtown_day' = '--time=12 --cam=-31,2.6,108,-35,14,10'
	'air_noon'     = '--time=12 --fov=62 --cam=70,190,340,0,0,10'
	'night_street' = '--time=22 --cam=-31,2.6,108,-35,14,10'
	'rain_dusk'    = '--time=18.5 --weather=rain --cam=-31,2.6,108,-35,14,10'
}
foreach ($n in $views.Keys) {
	$r = & powershell -NoProfile -File $gd game -Seconds 28 -Resolution 1600x900 -GameArgs ("--exec=res://gta/tests/content_perf.gd --no-traffic --no-peds --delay=6 --keep " + $views[$n])
	$l = $r | Select-String 'PERFRT' | Select-Object -Last 1
	Write-Output ("{0} {1,-14} {2}" -f $Tag, $n, $l)
}
