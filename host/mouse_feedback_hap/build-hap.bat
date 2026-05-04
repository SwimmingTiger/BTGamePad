cd /d "%~dp0"
hvigorw assembleHap -p buildMode=release
echo.
echo HAP built. Check %~dp0entry\build\default\outputs\default\
pause
