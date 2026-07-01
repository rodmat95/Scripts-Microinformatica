@echo off

:loop
cls 
echo Actualizando politicas 
echo Ejecutando gpupdate /force...
echo N|gpupdate /force

echo.
ping -n 5 127.0.0.1 >nul
goto loop