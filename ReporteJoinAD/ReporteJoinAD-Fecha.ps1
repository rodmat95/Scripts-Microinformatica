# Solicita la fecha
$fechaIngresada = Read-Host "Ingrese la fecha a consultar (yyyy-MM-dd)"

# Convierte la fecha ingresada a tipo [datetime]
try {
    $fechaInicio = [datetime]::ParseExact($fechaIngresada, "yyyy-MM-dd", $null)
    $fechaFin = $fechaInicio.AddDays(1)
} catch {
    Write-Host "Fecha inválida. Use formato yyyy-MM-dd (ej: 2024-02-15)" -ForegroundColor Red
    exit
}

# Obtener dominio
$dominio = (Get-ADDomain).NetBIOSName

# FILTRO DIRECTO EN AD (gran mejora)
$computers = Get-ADComputer -Filter {
    WhenCreated -ge $fechaInicio -and WhenCreated -lt $fechaFin
} -Property Name, WhenCreated, DistinguishedName

$resultados = @()

foreach ($computer in $computers) {

    try {
        # Obtener Owner (DOMINIO\usuario)
        $owner = (Get-Acl "AD:\$($computer.DistinguishedName)").Owner

        # Extraer usuario
        $userSam = $owner.Split('\')[1]

        # Obtener datos del usuario UNA sola vez
        $usuario = Get-ADUser -Identity $userSam -ErrorAction SilentlyContinue

        if ($usuario -and ($usuario.Name -like "SAPIA*" -or $usuario.Name -like "STEFANINI*")) {

            # Validar si el equipo sigue existiendo
            $exists = Get-ADComputer -Identity $computer.DistinguishedName -ErrorAction SilentlyContinue

            $resultados += [PSCustomObject]@{
                Hostname   = $computer.Name
                FechaHora  = $computer.WhenCreated
                Analista   = $usuario.Name
                ExisteEnAD = if ($exists) { "Sí" } else { "No" }
            }
        }

    } catch {
        Write-Warning "Error en $($computer.Name)"
    }
}

# Ordenar resultados
$resultados = $resultados | Sort-Object Analista, FechaHora -Descending

# Mostrar resultados
Write-Host "`n"
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " LISTA DE EQUIPOS UNIDOS EL $($fechaInicio.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Cyan

# Si no hay resultados
if ($resultados.Count -eq 0) {
    Write-Host "No se encontraron equipos unidos en la fecha seleccionada." -ForegroundColor Red
    return
}

# Muestra los resultados con formato visual
$resultados | Format-Table `
    @{Label="Hostname";Expression={$_.Hostname};Alignment="Left"},
    @{Label="Fecha-Hora";Expression={$_.FechaHora.ToString("yyyy-MM-dd HH:mm")};Alignment="Center"},
    @{Label="Analista";Expression={$_.Analista};Alignment="Left"},
    @{Label="Existe en AD";Expression={$_.ExisteEnAD};Alignment="Center"} `
    -AutoSize

Write-Host "==============================================================" -ForegroundColor DarkCyan
Write-Host " Total: $($resultados.Count)" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor DarkCyan