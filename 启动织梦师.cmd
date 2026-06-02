@echo off
cd /d "%~dp0"
echo 正在启动《织梦师》本地版...
echo 浏览器地址：http://localhost:3000
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
