<#
.SYNOPSIS
  Submit a python job to the running materials editor server (Tools/ue/materials_server.py), wait for it and print its log lines.

.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 Tools/ue/materials_build.py
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/materials_job.ps1 C:/tmp/x.py -TimeoutSec 1800 -Filter "ROAM_MAT|MATJOB|Error"
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Script,
  [int]$TimeoutSec = 1200,
  [string]$Filter = "MATJOB|MAT_|LogPython|Error:|Warning: .*[Mm]aterial|LogMaterial|LogShaderCompilers",
  [string]$LogName = "matserver",
  [string]$Args0 = ""
)
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$inbox = Join-Path $root "Saved\MatJobs\inbox"
$outbox = Join-Path $root "Saved\MatJobs\outbox"
$log = Join-Path $root "Tools\Logs\$LogName.log"
. (Join-Path $PSScriptRoot "_server_lib.ps1")
if (-not (Ensure-JobServer $root $LogName)) { exit 4 }
$src = $Script
if (-not [System.IO.Path]::IsPathRooted($src)) { $src = Join-Path $root $src }
if (-not (Test-Path $src)) { Write-Host "No such script $src"; exit 2 }
$name = "{0}_{1}.py" -f (Get-Date -Format "HHmmss_fff"), [IO.Path]::GetFileNameWithoutExtension($src)
$dest = Join-Path $inbox $name
$done = Join-Path $outbox ($name + ".done")
$lineStart = 0
if (Test-Path $log) { $lineStart = (Get-Content $log -ReadCount 100000 | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum }
# job text: optional args are injected as JOB_ARGS
$text = "JOB_ARGS = r'''$Args0'''`n" + (Get-Content $src -Raw -Encoding UTF8)
[IO.File]::WriteAllText($dest + ".tmp", $text, (New-Object Text.UTF8Encoding($false)))
Move-Item $dest".tmp" $dest
Write-Host "submitted $name"
$t0 = Get-Date
while (-not (Test-Path $done)) {
  Start-Sleep -Seconds 2
  if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) { Write-Host "TIMEOUT waiting for job (still running?)"; break }
}
Start-Sleep -Milliseconds 800
if (Test-Path $log) {
  $all = Get-Content $log -Encoding UTF8
  $new = $all | Select-Object -Skip $lineStart
  $new | Where-Object { $_ -match $Filter } | ForEach-Object { $_ }
}
if (Test-Path $done) { Write-Host "---- job result ----"; Get-Content $done }
