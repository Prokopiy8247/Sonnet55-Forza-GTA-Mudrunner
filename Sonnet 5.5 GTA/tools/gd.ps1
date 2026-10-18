<#
.SYNOPSIS
  Godot wrapper for this project (Windows PowerShell 5.1). Serialises import/check runs between parallel agents
  with a cross-process mutex so the shared .godot cache is never written concurrently, applies timeouts, writes a
  full log to logs\ and prints only the interesting lines.

.USAGE (always from the project root, via -File)
  powershell -NoProfile -File tools\gd.ps1 import                      # update class_name cache + import new assets (GLB, textures)
  powershell -NoProfile -File tools\gd.ps1 check                       # import + parse/load EVERY script/scene under res://gta (VALIDATE OK/FAIL)
  powershell -NoProfile -File tools\gd.ps1 run -Seconds 20             # headless simulation of the main scene (fixed 60 fps, no rendering)
  powershell -NoProfile -File tools\gd.ps1 run -Seconds 30 -GameArgs "--teleport=0,2,0 --perf"
  powershell -NoProfile -File tools\gd.ps1 exec -Script res://gta/tests/my_test.gd [-Seconds 60]   # headless: boots Main, awaits Script.run(main)
  powershell -NoProfile -File tools\gd.ps1 shot -Out screenshots\a.png -GameArgs "--teleport=10,2,5,90 --time=20 --delay=4"
                                                                      # windowed GPU render, saves a PNG (read it with the Read tool)
  powershell -NoProfile -File tools\gd.ps1 game -Seconds 60 -GameArgs "--perf"    # windowed run without screenshot
  Add -Full to print the whole log. -Lock makes run/exec/shot/game also take the mutex (use if you import in the same call).

  GameArgs are the DevHarness options (see gta/code/debug/dev_harness.gd). In `exec`/`run` the harness quits by itself.
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][ValidateSet('import', 'check', 'run', 'exec', 'shot', 'game', 'script')][string]$Cmd,
	[int]$Seconds = 30,
	[string]$Out = '',
	[string]$Script = '',
	[string]$GameArgs = '',
	[string]$Resolution = '1280x720',
	[switch]$Full,
	[switch]$Lock
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Godot = 'W:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$LogDir = Join-Path $Root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

function Invoke-Locked([scriptblock]$Body) {
	$m = New-Object System.Threading.Mutex($false, 'GtaGodotProjectLock')
	$got = $false
	try {
		$got = $m.WaitOne(900000)
		if (-not $got) { throw 'Timed out waiting for the Godot project lock (another agent is importing).' }
		& $Body
	}
	catch [System.Threading.AbandonedMutexException] { & $Body }
	finally { if ($got) { try { $m.ReleaseMutex() } catch {} }; $m.Dispose() }
}

function Invoke-Godot([string]$ArgLine, [int]$TimeoutSec, [string]$Tag) {
	$stamp = (Get-Date -Format 'HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
	$o = Join-Path $LogDir "$Tag-$stamp.stdout.tmp"
	$e = Join-Path $LogDir "$Tag-$stamp.stderr.tmp"
	$log = Join-Path $LogDir "$Tag-$stamp.log"
	$p = Start-Process -FilePath $Godot -ArgumentList $ArgLine -WorkingDirectory $Root -RedirectStandardOutput $o -RedirectStandardError $e -PassThru -NoNewWindow
	$timedOut = $false
	$null = $p.Handle   # caches the process handle so ExitCode is readable after exit
	if (-not $p.WaitForExit($TimeoutSec * 1000)) { $timedOut = $true; try { $p.Kill() } catch {} ; Start-Sleep -Milliseconds 500 }
	else { $p.WaitForExit() }   # second call flushes async output + populates ExitCode
	$lines = @()
	if (Test-Path $o) { $lines += Get-Content $o -ErrorAction SilentlyContinue }
	if (Test-Path $e) { $lines += Get-Content $e -ErrorAction SilentlyContinue }
	Remove-Item $o, $e -ErrorAction SilentlyContinue
	$lines | Set-Content -Path $log -Encoding utf8
	return [pscustomobject]@{ ExitCode = $(if ($timedOut) { -999 } else { $p.ExitCode }); TimedOut = $timedOut; Log = $log; Lines = $lines }
}

function Show-Result($r, [string]$Title) {
	$pattern = 'ERROR|SCRIPT ERROR|Parse Error|WARNING|HARNESS|PERF|PROBE|VALIDATE|TEST |FAIL|PASS|\[Main\]|Failed|Cannot|Invalid|Identifier|not declared|Condition'
	$noise = 'first_scan_filesystem|_update_scan_actions|loading_editor_layout|\[ DONE \]|\[\s*\d+% \]|^\s*$|Godot Engine v|Vulkan|D3D12|OpenGL|Jolt Physics'
	$sel = $r.Lines | Where-Object { ($_ -match $pattern) -and ($_ -notmatch $noise) } | Select-Object -Unique
	Write-Output ("=== {0}: exit={1}{2} log={3}" -f $Title, $r.ExitCode, $(if ($r.TimedOut) { ' (TIMEOUT - killed)' } else { '' }), $r.Log)
	if ($Full) { $r.Lines | Select-Object -First 400 | ForEach-Object { Write-Output $_ } }
	else {
		$sel | Select-Object -First 80 | ForEach-Object { Write-Output $_ }
		if (($sel | Measure-Object).Count -gt 80) { Write-Output '... (more lines in the log; use -Full)' }
	}
}

$base = "--path `"$Root`" --locale en"
$userArgs = if ($GameArgs) { " -- $GameArgs" } else { '' }

switch ($Cmd) {
	'import' {
		Invoke-Locked {
			$r = Invoke-Godot "--headless $base --import --quit" 300 'import'
			Show-Result $r 'import'
		}
	}
	'check' {
		Invoke-Locked {
			$r = Invoke-Godot "--headless $base --import --quit" 300 'import'
			Show-Result $r 'import'
			$r2 = Invoke-Godot "--headless $base --script res://gta/tests/validate_scripts.gd" 300 'validate'
			Show-Result $r2 'validate'
		}
	}
	'script' {
		if (-not $Script) { throw 'script needs -Script res://path.gd' }
		$r = Invoke-Godot "--headless $base --script $Script$userArgs" ($Seconds + 30) 'script'
		Show-Result $r "script $Script"
	}
	'run' {
		$frames = $Seconds * 60
		$body = {
			$r = Invoke-Godot "--headless $base --fixed-fps 60 --quit-after $frames$userArgs" ($Seconds * 4 + 60) 'run'
			Show-Result $r 'run'
		}
		if ($Lock) { Invoke-Locked $body } else { & $body }
	}
	'exec' {
		if (-not $Script) { throw 'exec needs -Script res://path.gd' }
		$frames = $Seconds * 60
		$body = {
			$r = Invoke-Godot "--headless $base --fixed-fps 60 --quit-after $frames -- --exec=$Script $GameArgs" ($Seconds * 4 + 60) 'exec'
			Show-Result $r "exec $Script"
		}
		if ($Lock) { Invoke-Locked $body } else { & $body }
	}
	'shot' {
		if (-not $Out) { throw 'shot needs -Out file.png' }
		$outAbs = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $Root $Out }
		$dir = Split-Path -Parent $outAbs
		if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
		$body = {
			$r = Invoke-Godot "$base --resolution $Resolution -- --shot=`"$outAbs`" $GameArgs" ($Seconds + 60) 'shot'
			Show-Result $r 'shot'
			if (Test-Path $outAbs) { Write-Output "SCREENSHOT: $outAbs" } else { Write-Output "SCREENSHOT MISSING: $outAbs" }
		}
		if ($Lock) { Invoke-Locked $body } else { & $body }
	}
	'game' {
		$body = {
			$r = Invoke-Godot "$base --resolution $Resolution --quit-after $($Seconds * 60)$userArgs" ($Seconds + 60) 'game'
			Show-Result $r 'game'
		}
		if ($Lock) { Invoke-Locked $body } else { & $body }
	}
}
