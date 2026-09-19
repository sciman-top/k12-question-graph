@echo off
rem Double-click entry for one-stop local dev start: starts API + Web,
rem opens the login page and copies the admin key to the clipboard.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-local-dev.ps1" %*
pause
