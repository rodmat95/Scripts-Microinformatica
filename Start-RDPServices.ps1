# Solicitar el nombre del equipo o IP
$remote = Read-Host "Ingrese el nombre o IP del equipo remoto"

Invoke-Command -ComputerName $remote -ScriptBlock {
    $services = @("WinRM", "TermService", "SessionEnv", "RasMan", "RemoteRegistry", "LanmanServer")
    $finalReport = @()

    # Verificacion de Servicios de Remoteo
    Write-Host "===== VALIDACIÓN DE SERVICIOS DE REMOTO =====" -ForegroundColor Yellow
    Write-Host "===== EN EL EQUIPO: $env:COMPUTERNAME =====" -ForegroundColor Yellow    
    Write-Host ""

    foreach ($ServiceName in $services) {
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction Stop

            if ($service.Status -eq "Stopped") {
                Write-Host "Servicio detenido encontrado: $ServiceName" -ForegroundColor Red
                Write-Host " → Cambiando el Tipo de inicio a Manual..." -ForegroundColor White
                Set-Service -Name $ServiceName -StartupType Manual

                Write-Host " → Iniciando servicio..." -ForegroundColor White
                Start-Service -Name $ServiceName -ErrorAction SilentlyContinue

                $newState = (Get-Service -Name $ServiceName).Status
                if ($newState -eq "Running") {
                    $finalReport += "El servicio $ServiceName se inicio correctamente."
                } else {
                    $finalReport += "El servicio $ServiceName NO se pudo iniciar. Estado final: $newState"
                }

                Write-Host ""
            } else {
                $finalReport += "El servicio $ServiceName está en ejecución. No se requirió acción."
            }
        } catch {
            $finalReport += "El servicio $ServiceName tuvo error: $($_.Exception.Message)"
        }
    }

    Write-Host "===== ESTADO FINAL DE LOS SERVICIOS =====" -ForegroundColor Cyan
    Write-Host ""

    foreach ($line in $finalReport) {
        if ($line -like "*NO se pudo iniciar*") {
            Write-Host $line -ForegroundColor Red
        } else {
            Write-Host $line -ForegroundColor Green
        }
    }
}

# SIG # Begin signature block
# MIIFfwYJKoZIhvcNAQcCoIIFcDCCBWwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUD+EI+lXdDq9bBLNJA/P9kctF
# bRygggMUMIIDEDCCAfigAwIBAgIQOxXWzv310LtNUY9OArWLhjANBgkqhkiG9w0B
# AQUFADAgMR4wHAYDVQQDDBVGaXJtYSBTY3JpcHRzIFNPUE9SVEUwHhcNMjYwMTIy
# MjA0ODAyWhcNMjcwMTIyMjEwODAyWjAgMR4wHAYDVQQDDBVGaXJtYSBTY3JpcHRz
# IFNPUE9SVEUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC3CzEDZmK3
# jNiRy1i+w1aXKaxbqtPyJfvBDBKzCBCDMbSmlNv0Y2ceDvD5kvBkUbdRStqzUzDR
# tjja//8SpKMYDM8gB+Jh8E03DdqSn6Np1QEZtQhRc1oK7xA7LOyV1pTIJQAsumZy
# LQ6sW5rLBljVg71Mwzo05iJRaxOcnafa2wEkfEUe6ifbxjbnJxy704TyPH2KfNXw
# YefdxIBH5q4CkqalnpeHO8QCMEmi1j9kwxHvxXXubsNG8Lf5tEqQ0kPSeW34gRZb
# DOAvr9KaMeyXVqOj0y+ShXz/s/ZtEmJGMU2xiZ7I7n/XIfAH+3nhcA4E/F212RHk
# Ate8IQJg53uBAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAdBgNVHQ4EFgQUSqR57IxubDQmBYikR51iOg0KrbAwDQYJKoZIhvcN
# AQEFBQADggEBAH3zz/fBHec2lhe0uYMNq1/GxQ88huA1fwy2hhjQyaS5FqEDH6NN
# zDqKC9f9T01HCvfMTp80FbdenBwgO1x5zlvSSQeI19RWenyMz/4IT55NlpLtFnyf
# sRdN6Q0KGBpdSkJzxSrcxgJWyXgQjtokpzht5nbRfl+0yQtOqEiBWazcLzkFOW0B
# qUpZs8cIfpp4+LV5bgc7iShCnG6x0oxvh43Xl/aAyGSY0puC6bETrw0TrOuH3T7M
# W1Rb8LVVnH8whL/vpEsAVtx6xlx9ISFwNgQd3RhGaLvhbU5L8H+wO709Y6sWtsWg
# jX8Rzs6E6WbGvTyLDzg7qhBBohiPo7GihO0xggHVMIIB0QIBATA0MCAxHjAcBgNV
# BAMMFUZpcm1hIFNjcmlwdHMgU09QT1JURQIQOxXWzv310LtNUY9OArWLhjAJBgUr
# DgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMx
# DAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkq
# hkiG9w0BCQQxFgQU4A6gdHduVlWAxO6aBeoNuRvCUHowDQYJKoZIhvcNAQEBBQAE
# ggEAM4fU5dMtTdB1/OfnyL5ZURcsvBWQC9mdh/qKPULl8aStrRmYHnlPcV2Mmg5z
# WBWazQ/CV6F+7B9lmS+QLfHuA64MmyJ+E0S1j6E0sraLkDe9Kux9ony30bDxoJ9f
# +YLt2zqBj0RPaeDYTRF0fzmRXoaLv1ybFMGHihlizYKp2mgGTYUYg46IAtnJbohP
# PlrRWC3KPqGKgRsNj6svNgQv6+crzP2UeUpKd23LLkuwz+wfuAae/5igsC4UbKz2
# NLpBQ80OQzQsWSc5wv529xbbGOVFON3ng7ndfNppomrYy2TvcQK4zfk37y6YuvFn
# e5uTat9G2wuXnhfcnYXhrhYZVw==
# SIG # End signature block
