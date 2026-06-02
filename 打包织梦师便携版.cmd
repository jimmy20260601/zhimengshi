@echo off
cd /d "%~dp0"
echo 正在打包《织梦师》便携版...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-portable.ps1"
pause
