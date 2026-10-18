# Shared helpers for the persistent editor job server (see Tools/ue/ue_job.ps1). Dot-source this file.
function Get-JobServerBase([string]$root) { Join-Path $root "Saved\MatJobs" }

function Test-JobServerAlive([string]$root) {
  $p = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor-Cmd.exe'" -ErrorAction SilentlyContinue |
       Where-Object { $_.CommandLine -like "*materials_server.py*" -and $_.CommandLine -like "*$root*" }
  return [bool]$p
}

function Test-JobServerStarting([string]$root) {
  # a hidden ue_cmd.ps1 wrapper for materials_server.py exists (it may still wait for the project mutex held by another Unreal run)
  $p = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
       Where-Object { $_.CommandLine -like "*ue_cmd.ps1*" -and $_.CommandLine -like "*materials_server.py*" -and $_.CommandLine -like "*$root*" }
  return [bool]$p
}

function Ensure-JobServer([string]$root, [string]$LogName = "matserver") {
  $base = Get-JobServerBase $root
  New-Item -ItemType Directory -Force $base | Out-Null
  $idleFile = Join-Path $base "idle_limit_s"
  if (-not (Test-Path $idleFile)) { Set-Content -Path $idleFile -Value "300" -Encoding ascii }
  # 1. wait while a build is running
  $lock = Join-Path $base "build_lock"
  $t0 = Get-Date
  while ((Test-Path $lock) -and ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 45) {
    Write-Host "waiting for the build in progress to finish ..."; Start-Sleep -Seconds 10
    if (((Get-Date) - $t0).TotalSeconds -gt 3600) { break }
  }
  # 2. a server that is shutting down (quit flag) must exit first
  if ((Test-JobServerAlive $root) -and (Test-Path (Join-Path $base "quit"))) {
    Write-Host "job server is shutting down (quit flag) - waiting for it to exit ..."
    while (Test-JobServerAlive $root) { Start-Sleep -Seconds 3 }
  }
  # 3. start it if needed (a start that is already queued behind another Unreal run is reused: every extra start costs another editor launch)
  if (-not (Test-JobServerAlive $root)) {
    Remove-Item (Join-Path $base "quit") -ErrorAction SilentlyContinue
    $startTime = Get-Date
    if (Test-JobServerStarting $root) {
      Write-Host "a job server start is already queued/in progress - waiting for it ..."
    } else {
      Write-Host "starting the editor job server ..."
      $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$root\Tools\ue_cmd.ps1`"", "-PythonScript", "Tools/ue/materials_server.py", "-LogName", $LogName, "-TimeoutSec", "21600")
      Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden | Out-Null
    }
    $log = Join-Path $root "Tools\Logs\$LogName.log"
    $ready = $false
    while (((Get-Date) - $startTime).TotalSeconds -lt 1500) {
      Start-Sleep -Seconds 5
      if ((Test-Path $log) -and ((Get-Item $log).LastWriteTime -gt $startTime)) {
        if (Select-String -Path $log -Pattern "MATJOB_SERVER_READY" -Quiet) { $ready = $true; break }
      }
    }
    if (-not $ready) { Write-Host "job server did not become ready (see $log)"; return $false }
    Write-Host "job server ready"
  }
  return $true
}
