# Pedir hostname al usuario
$PC = Read-Host "Ingrese el nombre del equipo"

# 1) Obtener usuario activo del remoto
$query = (query user /server:$PC | Select-String "Activo|Active")
if ($null -eq $query) { Write-Host "No hay usuario activo"; exit }
$user = ($query.ToString().Trim() -replace ">", "").Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[0]

Write-Host "Usuario activo detectado: [$user]"

# 2) Crear tarea interactiva en el remoto
schtasks /create /s $PC /tn "\LockScreenInteractive" /tr "%SystemRoot%\System32\rundll32.exe user32.dll,LockWorkStation" /sc once /st 23:59 /ru $user /it /f | Out-Null

# 3) Ejecutar tarea
Write-Host "Bloqueando pantalla..."
schtasks /run /s $PC /tn "\LockScreenInteractive" | Out-Null
Start-Sleep -Seconds 1

# 4) Validación
Write-Host "Proceso completado. Pantalla bloqueada y tarea eliminada." -ForegroundColor Green

# 5) Eliminar la tarea una vez ejecutada
schtasks /delete /s $PC /tn "\LockScreenInteractive" /f | Out-Null