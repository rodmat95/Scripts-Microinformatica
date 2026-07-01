# Solicitar el nombre del equipo o IP
$remote = Read-Host "Ingrese el nombre o IP del equipo remoto"


Invoke-Command -ComputerName $remote -ScriptBlock {

    Start-Process powershell.exe `
        -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "D:\Reset-Network.ps1"' `
        -WindowStyle Hidden

    "Reset de red lanzado correctamente en el equipo $($env:COMPUTERNAME) - $(Get-Date)"
}