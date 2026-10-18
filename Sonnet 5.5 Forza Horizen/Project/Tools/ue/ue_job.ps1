<#
.SYNOPSIS
  Run a Python script inside a PERSISTENT Unreal editor ("job server"): much faster than starting UnrealEditor-Cmd per run
  (an editor start costs 1-8 minutes here). The server starts automatically when needed, yields automatically to builds and to
  other Unreal runs of this folder (Tools/build_editor.ps1 and Tools/ue_cmd.ps1 create Saved/MatJobs/quit; jobs submitted
  afterwards wait for the build (Saved/MatJobs/build_lock) and restart the server), and exits after 300 s without jobs.
  Jobs run on the game thread; JOB_ARGS (string) is injected from -Args0; a job must NOT call QUIT_EDITOR.
  Same as Tools/ue/materials_job.ps1 (kept for compatibility).
.EXAMPLES
  powershell -NoProfile -ExecutionPolicy Bypass -File Tools/ue/ue_job.ps1 Tools/ue/world_build.py -TimeoutSec 3600 -Args0 "steps=landscape"
#>
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Script,
  [int]$TimeoutSec = 1200,
  [string]$Filter = "MATJOB|MAT_|ROAM|LogPython|Error:|Warning: .*[Mm]aterial|LogMaterial|LogShaderCompilers",
  [string]$LogName = "matserver",
  [string]$Args0 = ""
)
& (Join-Path $PSScriptRoot "materials_job.ps1") -Script $Script -TimeoutSec $TimeoutSec -Filter $Filter -LogName $LogName -Args0 $Args0
exit $LASTEXITCODE
