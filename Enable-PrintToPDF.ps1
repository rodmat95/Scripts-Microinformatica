# Solicitar el nombre del equipo o IP
$remote = Read-Host "Ingrese el nombre o IP del equipo remoto"

Invoke-Command -ComputerName $remote -ScriptBlock {
    $printerName = 'Microsoft Print to PDF'
    $featureName = 'Printing-PrintToPDFServices-Features'
    $driverName  = 'Microsoft Print To PDF'       # Nombre EXACTO del driver
    $portName    = 'PORTPROMPT:'                  # Puerto para solicitar ubicación/archivo
    $infPath     = 'C:\Windows\INF\prnms003.inf'  # INF inbox del driver de Microsoft Print to PDF

    Write-Host "=== $env:COMPUTERNAME ==="

    # 0) Asegurar Spooler arriba
    try {
        $spooler = Get-Service -Name Spooler -ErrorAction Stop
        if ($spooler.Status -ne 'Running') {
            Start-Service Spooler -ErrorAction Stop
        }
    } catch {
        Write-Host "No se pudo iniciar/verificar el servicio Spooler: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # 1) Habilitar la característica (instala los binarios/driver inbox)
    try {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop
        if ($feat.State -ne 'Enabled') {
            Write-Host "Habilitando feature '$featureName'..." -ForegroundColor Yellow
            Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart -ErrorAction Stop | Out-Null
            # Pequeña espera para que el driver se registre
            Start-Sleep -Seconds 2
        } else {
            Write-Host "El feature '$featureName' ya está habilitado." -ForegroundColor Green
        }
    } catch {
        Write-Host "Error habilitando el feature: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # 2) Verificar/instalar driver Microsoft Print To PDF
    $drv = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
    if (-not $drv) {
        Write-Host "El driver '$driverName' no está cargado. Intentando agregarlo..." -ForegroundColor Yellow

        try {
            if (Test-Path $infPath) {
                # Método 1: cargar desde INF inbox (recomendado si Add-PrinterDriver por nombre falla)
                Add-PrinterDriver -Name $driverName -InfPath $infPath -ErrorAction Stop
            } else {
                # Método 2: intentar por nombre (si ya quedó registrado tras habilitar el feature)
                Add-PrinterDriver -Name $driverName -ErrorAction Stop
            }
            Write-Host "Driver '$driverName' instalado/cargado." -ForegroundColor Green
        } catch {
            Write-Host "No se pudo agregar el driver '$driverName': $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    } else {
        Write-Host "Driver '$driverName' presente." -ForegroundColor Green
    }

    # 3) Crear puerto y la impresora, si no existe
    $printer = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
    if (-not $printer) {
        try {
            if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                Add-PrinterPort -Name $portName -ErrorAction Stop
            }
            Add-Printer -Name $printerName -DriverName $driverName -PortName $portName -ErrorAction Stop
            Write-Host "Impresora '$printerName' creada correctamente." -ForegroundColor Green
        } catch {
            Write-Host "No se pudo crear la impresora '$printerName': $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    } else {
        Write-Host "La impresora '$printerName' ya existía." -ForegroundColor Green
    }

    # 4) Confirmación final
    $final = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
    if ($final) {
        Write-Host "Estado final: OK (impresora presente y feature habilitado)." -ForegroundColor Green
    } else {
        Write-Host "Estado final: La impresora sigue ausente." -ForegroundColor Red
    }
}