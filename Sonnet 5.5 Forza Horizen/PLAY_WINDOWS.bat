@echo off
setlocal
cd /d "%~dp0"
title Roamline: Open Roads
if exist "Game\Sonnet55Forza.exe" goto run
echo.
echo  First launch: unpacking the game (about 1.5 GB, 2-5 minutes). Please wait...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $z='Build\game.zip'; $o=[IO.File]::Create($z); Get-ChildItem 'Build\game.zip.*' | Sort-Object Name | ForEach-Object { $b=[IO.File]::ReadAllBytes($_.FullName); $o.Write($b,0,$b.Length) }; $o.Close(); Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory($z,'Game'); Remove-Item $z"
if errorlevel 1 (
  echo.
  echo  Unpacking failed. Make sure the whole repository was downloaded and there is 5 GB of free disk space.
  pause
  exit /b 1
)
:run
echo  Starting the game...
start "" "Game\Sonnet55Forza.exe" -windowed -ResX=1920 -ResY=1080
exit /b 0
