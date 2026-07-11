# Equipos destino
$computers = 146..158 | ForEach-Object { "A12NEG01-$_" }

# BAT local
$sourceBat = "D:\Depurador_C_v2.bat"

Write-Host ""
Write-Host "===== Despliegue y ejecución de $(Split-Path $sourceBat -Leaf) =====" -ForegroundColor Cyan
Write-Host ""

$resultados = foreach ($pc in $computers) {

    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    try {

        # Validar origen
        if (-not (Test-Path $sourceBat)) {
            throw "No existe el archivo local: $sourceBat"
        }

        # Validar acceso administrativo
        if (-not (Test-Path "\\$pc\C$")) {
            throw "Sin acceso a \\$pc\C$"
        }

        # Crear C:\Temp remoto
        $destFolder = "\\$pc\C$\Temp"

        if (-not (Test-Path $destFolder)) {
            New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        }

        # Copiar BAT
        $batName = Split-Path $sourceBat -Leaf
        $destBat = Join-Path $destFolder $batName

        Copy-Item `
            -Path $sourceBat `
            -Destination $destBat `
            -Force `
            -ErrorAction Stop

        # Ejecutar remotamente
        $ejecucion = Invoke-Command `
            -ComputerName $pc `
            -ArgumentList $batName `
            -ErrorAction Stop `
            -ScriptBlock {

                param($NombreBat)

                $rutaBat = "C:\Temp\$NombreBat"

                # Estado ANTES
                $discoA = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

                $AntesUsadoGB = (($discoA.Size - $discoA.FreeSpace) / 1GB)
                $AntesLibreGB = ($discoA.FreeSpace / 1GB)

                # Ejecutar BAT y esperar a que finalice
                Start-Process `
                    -FilePath "cmd.exe" `
                    -ArgumentList "/c `"$rutaBat`"" `
                    -Wait `
                    -WindowStyle Hidden

                # Estado DESPUÉS
                $discoB = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

                $DespuesUsadoGB = (($discoB.Size - $discoB.FreeSpace) / 1GB)
                $DespuesLibreGB = ($discoB.FreeSpace / 1GB)

                [PSCustomObject]@{
                    Equipo          = $env:COMPUTERNAME

                    AntesUsadoGB    = $AntesUsadoGB
                    AntesLibreGB    = $AntesLibreGB

                    DespuesUsadoGB  = $DespuesUsadoGB
                    DespuesLibreGB  = $DespuesLibreGB

                    RecuperadoGB    = ($DespuesLibreGB - $AntesLibreGB)
                }
            }

        [PSCustomObject]@{
            Equipo          = $ejecucion.Equipo

            AntesUsadoGB    = $ejecucion.AntesUsadoGB
            AntesLibreGB    = $ejecucion.AntesLibreGB

            DespuesUsadoGB  = $ejecucion.DespuesUsadoGB
            DespuesLibreGB  = $ejecucion.DespuesLibreGB

            RecuperadoGB    = $ejecucion.RecuperadoGB

            Copiado         = "SI"
            Estado          = "COMPLETADO"
            Fecha           = $fecha
            Mensaje         = ""
        }

    }
    catch {

        [PSCustomObject]@{
            Equipo          = $pc

            AntesUsadoGB    = $null
            AntesLibreGB    = $null

            DespuesUsadoGB  = $null
            DespuesLibreGB  = $null

            RecuperadoGB    = $null

            Copiado         = "NO"
            Estado          = "ERROR"
            Fecha           = $fecha
            Mensaje         = $_.Exception.Message
        }
    }
}

# Formatear salida
$vista = $resultados | Select-Object `
    Equipo,
    Estado,
    Copiado,
    @{Name='AntesUsadoGB';Expression={"{0:N2}" -f $_.AntesUsadoGB}},
    @{Name='AntesLibreGB';Expression={"{0:N2}" -f $_.AntesLibreGB}},
    @{Name='DespuesUsadoGB';Expression={"{0:N2}" -f $_.DespuesUsadoGB}},
    @{Name='DespuesLibreGB';Expression={"{0:N2}" -f $_.DespuesLibreGB}},
    @{Name='RecuperadoGB';Expression={"{0:N2}" -f $_.RecuperadoGB}},
    Fecha,
    Mensaje

# Ventana interactiva
$vista | Out-GridView -Title "Resultado de Limpieza"

# Consola
$vista | Format-Table -AutoSize