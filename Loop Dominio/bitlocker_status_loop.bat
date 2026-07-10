@echo off

:loop
cls
echo Consultando estado de BitLocker
echo Ejecutando manage-bde -status C: y D:...

manage-bde -status

echo.
ping -n 5 127.0.0.1 >nul
goto loop