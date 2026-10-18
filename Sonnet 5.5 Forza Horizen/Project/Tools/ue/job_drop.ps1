<#
.SYNOPSIS
  Drop a python job into the RUNNING editor job server inbox without Ensure-JobServer logic (use when the server is alive; prints the job name).
  Result lines: grep the job between "MATJOB_START <name>" and "MATJOB_DONE <name>" in Tools/Logs/matserver.log (or the newest matserver-backup-*.log if the
  server restarted meanwhile).   Example:  powershell -NoProfile -File Tools/ue/job_drop.ps1 Tools/ue/materials_build.py "masters=M_Roam_Road instances"
#>
param([Parameter(Mandatory = $true, Position = 0)][string]$Script, [Parameter(Position = 1)][string]$Args0 = "", [string]$Tag = "")
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$inbox = Join-Path $root "Saved\MatJobs\inbox"
New-Item -ItemType Directory -Force $inbox | Out-Null
$src = $Script
if (-not [System.IO.Path]::IsPathRooted($src)) { $src = Join-Path $root $src }
if ($Tag -eq "") { $Tag = [IO.Path]::GetFileNameWithoutExtension($src) }
$name = "{0}_{1}.py" -f (Get-Date -Format "HHmmss_fff"), $Tag
$text = "JOB_ARGS = r'''$Args0'''`n" + (Get-Content $src -Raw -Encoding UTF8)
[IO.File]::WriteAllText((Join-Path $inbox ($name + ".tmp")), $text, (New-Object Text.UTF8Encoding($false)))
Move-Item (Join-Path $inbox ($name + ".tmp")) (Join-Path $inbox $name)
Write-Output $name
