$modo = Read-Host "Modo de ingreso: (M)anual o (R)ango"

if ($modo.ToUpper() -eq 'R') {
    $inicio = Read-Host "Ingrese número inicial"
    $fin    = Read-Host "Ingrese número final"
    $prefijo = Read-Host "Ingrese prefijo del hostname"

    $ComputerName = $inicio..$fin | ForEach-Object { "$prefijo$_" }
}
else {
    $inputStr = Read-Host "Ingrese uno o varios equipos (hostname o IP), separados por coma"
    $ComputerName = ($inputStr -split '\s*,\s*') | Where-Object { $_ -ne '' }
}

if (-not $ComputerName -or $ComputerName.Count -eq 0) {
    Write-Error "No se ingresaron equipos válidos."
    return
}

# Configurar TrustedHosts en '*'
# Si trabajas en dominio y no lo necesitas, puedes omitir esta línea.
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force

# Credenciales
$user = "EM72647765"
$password = ConvertTo-SecureString "M1c01\\M1b@nC0" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($user, $password)

# Crear sesiones remotas
$sessions = @()
foreach ($c in $ComputerName) {
    try {
        $s = New-PSSession -ComputerName $c -Credential $cred -Authentication Negotiate -ErrorAction Stop
        $sessions += $s
        Write-Host "Sesión creada: Id=$($s.Id) Equipo=$c" -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo crear sesión con '$c': $($_.Exception.Message)"
    }
}

if (-not $sessions -or $sessions.Count -eq 0) {
    Write-Error "No hay sesiones disponibles."
    return
}

Write-Host ""
Write-Host "Modo BROADCAST iniciado." -ForegroundColor Cyan
# ---Todo lo que escribas se ejecutará en TODOS los equipos---
Write-Host "Escribe 'exit' o 'salir' para terminar." -ForegroundColor Yellow

while ($true) {
	Write-Host ""
    $cmd = Read-Host "PS-BROADCAST"
	Write-Host ""

    if ($cmd -eq 'exit' -or $cmd -eq 'salir') {
        break
    }

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        continue
    }

    try {
        $results = Invoke-Command -Session $sessions -ScriptBlock {
            param($code)

            try {
                $sb = [ScriptBlock]::Create($code)
                $output = (& $sb *>&1 | Out-String)

                [PSCustomObject]@{
                    Equipo = $env:COMPUTERNAME
                    Salida = $output.TrimEnd()
                }
            }
            catch {
                [PSCustomObject]@{
                    Equipo = $env:COMPUTERNAME
                    Salida = "[ERROR] $($_.Exception.Message)"
                }
            }
        } -ArgumentList $cmd -ErrorAction Continue

        foreach ($r in $results) {
            if ([string]::IsNullOrWhiteSpace($r.Salida)) {
                Write-Host "[$($r.Equipo)]: (Sin salida)" -ForegroundColor DarkGray
            } else {
                $lineas = $r.Salida -split "(`r`n|`n|`r)"
                foreach ($linea in $lineas) {
                    if (-not [string]::IsNullOrWhiteSpace($linea)) {
                        Write-Host "[$($r.Equipo)]: " -NoNewline -ForegroundColor Cyan
                        Write-Host $linea
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Error al ejecutar el comando: $($_.Exception.Message)"
    }
}

# Cerrar sesiones
Remove-PSSession -Session $sessions -ErrorAction SilentlyContinue
Write-Host "Sesiones cerradas." -ForegroundColor Yellow