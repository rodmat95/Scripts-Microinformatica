# Solicitar el nombre del equipo o IP
$remote = Read-Host "Ingrese el nombre o IP del equipo remoto"

# Elegir acción: Reiniciar o Apagar
$opcion = (Read-Host "¿Qué deseas hacer en $remote? [R]einiciar o [A]pagar").Trim().ToUpper()
switch ($opcion) {
    'R' { $flag = '/r'; $accion = 'reinicio' }
    'A' { $flag = '/s'; $accion = 'apagado' }
    'C' { $flag = '/l'; $accion = 'cierre de sesión' }
    'H' { $flag = '/h'; $accion = 'hibernación' }
    default {
        Write-Host "Opción inválida. Elige 'R' para reiniciar o 'A' para apagar." -ForegroundColor Red
        exit 1
    }
}
<#
$opcion = (Read-Host "¿Qué deseas hacer en $remote? [R]einiciar, [A]pagar, [L]ogout o [H]ibernar").Trim().ToUpper()

switch ($opcion) {
    default {
        Write-Host "Opción inválida. Elige: R (reiniciar), A (apagar), L (logout) o H (hibernar)." -ForegroundColor Red
        exit 1
    }
}
#>

$horaEntrada = (Read-Host "Ingresa la hora para $accion en el equipo $remote, HH:mm:ss (24 horas)").Trim()

# === Ejecución remota ===
Invoke-Command -ComputerName $remote -ErrorAction Stop -ScriptBlock {
    param(
        [string]$HoraRemota,
        [string]$FlagAccion,   # '/r' o '/s'
        [string]$AccionNombre  # 'reinicio' o 'apagado' - solo para mensajes
    )

    # Validar formato estricto HH:mm:ss
    if ($HoraRemota -notmatch '^(?:[01]?\d|2[0-3]):[0-5]\d:[0-5]\d$') {
        Write-Host "Formato inválido. Usa estrictamente HH:mm:ss (24 horas)." -ForegroundColor Red
        exit 1
    }

    try {
        $ahora = Get-Date

        # Construir fecha objetivo para hoy con la hora dada
        $objetivoHoy = Get-Date -Hour ($HoraRemota.Split(':')[0]) -Minute ($HoraRemota.Split(':')[1]) -Second ($HoraRemota.Split(':')[2])
        
        # Si ya pasó hoy, programar para mañana
        if ($objetivoHoy -le $ahora) {
            $objetivo = $objetivoHoy.AddDays(1)
        } else {
            $objetivo = $objetivoHoy
        }  

        # Calcular segundos restantes (entero)
        $segundosRestantes = [int][Math]::Ceiling(($objetivo - $ahora).TotalSeconds)
        
        if ($segundosRestantes -le 0) {
            Write-Host "La hora indicada no permite programar el $AccionNombre." -ForegroundColor Red
            exit 1
        }

        # Mostrar tiempo restante legible
        $ts = New-TimeSpan -Seconds $segundosRestantes
        $horasTotales = [int][math]::Floor($ts.TotalHours)
        $restanteLegible = "{0:00}:{1:00}:{2:00}" -f $horasTotales, $ts.Minutes, $ts.Seconds

        Write-Host "Falta: $restanteLegible (≈ $segundosRestantes segundos) para el $AccionNombre." -ForegroundColor Yellow
        Write-Host "Se programó el $AccionNombre del equipo $env:COMPUTERNAME para las $($objetivo.ToString('HH:mm:ss'))" -ForegroundColor Green

        # Programar acción (igual que el original)
        # Nota: Incluye /f para forzar cierre de apps. Quita /f si no quieres forzar.
        shutdown.exe $FlagAccion /f /t $segundosRestantes

        Write-Host "Para ABORTAR el $AccionNombre programado:" -ForegroundColor Cyan
        Write-Host " 1) En el equipo $env:COMPUTERNAME, ejecuta: " -NoNewline -ForegroundColor Cyan
        Write-Host "shutdown -a" -ForegroundColor DarkCyan
        Write-Host " 2) Desde este equipo, ejecuta: " -NoNewline -ForegroundColor Cyan
        Write-Host "Invoke-Command -ComputerName $env:COMPUTERNAME -ScriptBlock { shutdown -a }" -ForegroundColor DarkCyan
    }
    catch {
        Write-Host "Ocurrió un error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} -ArgumentList $horaEntrada, $flag, $accion

<#
# === MODO LOCAL ===

# Elegir acción: Reiniciar o Apagar
$opcion = (Read-Host "¿Qué deseas hacer? [R]einiciar o [A]pagar").Trim().ToUpper()

switch ($opcion) {
    'R' { 
        $flag = '/r' 
        $accion = 'reinicio'
        $accionGerundio = 'reiniciando'
        $accionInfinitivo = 'reiniciar'
    }
    'A' { 
        $flag = '/s' 
        $accion = 'apagado'
        $accionGerundio = 'apagando'
        $accionInfinitivo = 'apagar'
    }
    default {
        Write-Host "Opción inválida. Elige 'R' para reiniciar o 'A' para apagar." -ForegroundColor Red
        exit 1
    }
}

# Solicitar hora objetivo
$horaEntrada = (Read-Host "Ingresa la hora para $accion, HH:mm:ss (24 horas)").Trim()

# Validar formato estricto HH:mm:ss
if ($horaEntrada -notmatch '^(?:[01]?\d|2[0-3]):[0-5]\d:[0-5]\d$') {
    Write-Host "Formato inválido. Usa estrictamente HH:mm:ss (24 horas)." -ForegroundColor Red
    exit 1
}

try {
    $ahora = Get-Date

    # Construir fecha objetivo para hoy con la hora dada
    $objetivoHoy = Get-Date -Hour ($horaEntrada.Split(':')[0]) -Minute ($horaEntrada.Split(':')[1]) -Second ($horaEntrada.Split(':')[2])
    
    # Si ya pasó hoy, programar para mañana
    if ($objetivoHoy -le $ahora) {
        $objetivo = $objetivoHoy.AddDays(1)
    } else {
        $objetivo = $objetivoHoy
    }  

    # Calcular segundos restantes (entero)
    $segundosRestantes = [int][Math]::Ceiling(($objetivo - $ahora).TotalSeconds)
    
    if ($segundosRestantes -le 0) {
        Write-Host "La hora indicada no permite programar el $accion." -ForegroundColor Red
        exit 1
    }

    # Mostrar tiempo restante legible
    $ts = New-TimeSpan -Seconds $segundosRestantes
    $horasTotales = [int][math]::Floor($ts.TotalHours)
    $restanteLegible = "{0:00}:{1:00}:{2:00}" -f $horasTotales, $ts.Minutes, $ts.Seconds

    Write-Host "Falta: $restanteLegible (≈ $segundosRestantes segundos) para el $accion." -ForegroundColor Yellow
    Write-Host "Se programó el $accion del equipo $env:COMPUTERNAME para las $($objetivo.ToString('HH:mm:ss'))" -ForegroundColor Green

    # Programar acción (aquí se mantiene la lógica original: usar shutdown con temporizador)
    # Nota: Incluye /f para forzar cierre de apps. Quita /f si no quieres forzar.
    shutdown.exe $flag /f /t $segundosRestantes

    Write-Host "Para ABORTAR el $accion programado: shutdown -a" -ForegroundColor Cyan
}
catch {
    Write-Host "Ocurrió un error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
#>