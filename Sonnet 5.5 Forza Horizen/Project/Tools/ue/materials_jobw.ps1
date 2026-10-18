<#
.SYNOPSIS
  materials_job.ps1 with a watchdog: while the submitted job is not finished it restarts the job server whenever it is not alive
  (the server exits for builds / other Unreal runs; a job already sitting in the inbox would otherwise wait forever).
  Same parameters as materials_job.ps1.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Script,
  [int]$TimeoutSec = 1200,
  [string]$Filter = "MATJOB|MAT_|LogPython|Error:|Warning: .*[Mm]aterial|LogMaterial|LogShaderCompilers",
  [string]$LogName = "matserver",
  [string]$Args0 = ""
)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot "_server_lib.ps1")
$inbox = Join-Path $root "Saved\MatJobs\inbox"
$outbox = Join-Path $root "Saved\MatJobs\outbox"
$log = Join-Path $root "Tools\Logs\$LogName.log"
if (-not (Ensure-JobServer $root $LogName)) { exit 4 }
$src = $Script
if (-not [System.IO.Path]::IsPathRooted($src)) { $src = Join-Path $root $src }
if (-not (Test-Path $src)) { Write-Host "No such script $src"; exit 2 }
$name = "{0}_{1}.py" -f (Get-Date -Format "HHmmss_fff"), [IO.Path]::GetFileNameWithoutExtension($src)
$dest = Join-Path $inbox $name
$done = Join-Path $outbox ($name + ".done")
$text = "JOB_ARGS = r'''$Args0'''`n" + (Get-Content $src -Raw -Encoding UTF8)
[IO.File]::WriteAllText($dest + ".tmp", $text, (New-Object Text.UTF8Encoding($false)))
Move-Item ($dest + ".tmp") $dest
Write-Host "submitted $name"
$t0 = Get-Date
$lastCheck = Get-Date
$seenStart = $false
while (-not (Test-Path $done)) {
  Start-Sleep -Seconds 3
  if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { Write-Host "TIMEOUT waiting for job (still queued / running)"; break }
  if (((Get-Date) - $lastCheck).TotalSeconds -gt 20) {
    $lastCheck = Get-Date
    if ((Test-Path $dest) -and -not (Test-JobServerAlive $root)) {
      Write-Host "job server is not running and the job is still queued - restarting it"
      if (-not (Ensure-JobServer $root $LogName)) { exit 4 }
    }
  }
}
Start-Sleep -Milliseconds 800
if (Test-Path $log) {
  # print the log section from this job's start marker on
  $all = Get-Content $log -Encoding UTF8
  $idx = -1
  for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match "MATJOB_START $([regex]::Escape($name))") { $idx = $i; break } }
  if ($idx -ge 0) { $all | Select-Object -Skip $idx | Where-Object { $_ -match $Filter } | ForEach-Object { $_ } }
}
if (Test-Path $done) { Write-Host "---- job result ----"; Get-Content $done }
