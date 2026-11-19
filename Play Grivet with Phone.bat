@echo off
rem Grivet with a phone as an extra controller (Docs/PhonePad.md).
rem Starts the PhonePad server in its own window (QR codes to scan), then the
rem game, as Play Grivet.bat does. Keyboard and mouse keep working alongside.
cd /d "%~dp0tools\phonepad"
where node >nul 2>nul
if errorlevel 1 (
  echo PhonePad needs Node.js 18 or newer: https://nodejs.org
  pause
  exit /b 1
)
if not exist node_modules (
  echo Installing PhonePad's locked dependencies ^(npm ci, install scripts disabled^)...
  call npm ci --ignore-scripts
  if errorlevel 1 (
    echo npm ci failed. Check the network, then run this again.
    pause
    exit /b 1
  )
)
start "PhonePad - scan a QR code with the phone" cmd /k node server.js
start "" "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
