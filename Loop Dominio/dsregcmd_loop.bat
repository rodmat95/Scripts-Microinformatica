@echo off

cls 
echo Saliendo del registro
echo Ejecutando dsregcmd /debug /leave...
dsregcmd /debug /leave

echo.
ping -n 5 127.0.0.1 >nul

:loop
cls
echo Volviendo a integrar al registro
echo Ejecutando dsregcmd /debug /join...
dsregcmd /debug /join

echo.
ping -n 30 127.0.0.1 >nul
goto loop