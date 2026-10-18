@echo off
setlocal
title Mire and Iron - launcher
cd /d "%~dp0"
set "ZIP=%~dp0Game\MireAndIron-Windows.zip"
set "GAME=%~dp0Game\MireAndIron-Windows\MireAndIron.exe"
if exist "%GAME%" goto run
if not exist "%ZIP%" (
  echo.
  echo ERROR: file Game\MireAndIron-Windows.zip was not found next to this file.
  echo Please extract the WHOLE downloaded folder first ^(right click - Extract All^), then run PLAY-Windows.bat again.
  echo.
  pause
  exit /b 1
)
echo.
echo First launch: unpacking the game. This takes about a minute, please wait...
echo.
tar -xf "%ZIP%" -C "%~dp0Game" 2>nul
if not exist "%GAME%" powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%~dp0Game' -Force"
if not exist "%GAME%" (
  echo.
  echo ERROR: could not unpack the game. Please extract Game\MireAndIron-Windows.zip manually and run MireAndIron.exe inside.
  echo.
  pause
  exit /b 1
)
:run
echo Starting Mire and Iron...
start "" "%GAME%"
exit /b 0
