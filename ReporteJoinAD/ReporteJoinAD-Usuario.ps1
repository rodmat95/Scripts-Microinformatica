# Solicita el usuario de red (SamAccountName)
$usuarioBusqueda = Read-Host "Ingrese el usuario de red"

# Rango de fechas (últimos 30 días)
$fechaFin = Get-Date
$fechaInicio = $fechaFin.AddDays(-30)

# Obtener usuario desde AD
$usuarioAD = Get-ADUser -Identity $usuarioBusqueda -ErrorAction Stop

# Construir formato DOMINIO\usuario
$dominio = (Get-ADDomain).NetBIOSName
$usuarioDominio = "$dominio\$usuarioBusqueda"

# Obtener todos los equipos creados en los últimos 30 días
$computers = Get-ADComputer -Filter {
    WhenCreated -ge $fechaInicio -and WhenCreated -le $fechaFin
} -Property Name, WhenCreated, DistinguishedName

$resultados = @()

foreach ($computer in $computers) {

    try {
        # Obtener Owner del objeto
        $owner = (Get-Acl "AD:\$($computer.DistinguishedName)").Owner

        # Validar si coincide con el usuario buscado
        if ($owner -eq $usuarioDominio) {

            # Verificar si existe en AD
            $exists = Get-ADComputer -Identity $computer.DistinguishedName -ErrorAction SilentlyContinue

            $resultados += [PSCustomObject]@{
                Hostname   = $computer.Name
                FechaHora  = $computer.WhenCreated
                Analista   = $usuarioAD.Name
                ExisteEnAD = if ($exists) { "Sí" } else { "No" }
            }
        }

    } catch {
        Write-Warning "Error en equipo $($computer.Name)"
    }
}

# Ordenar resultados
$resultados = $resultados | Sort-Object FechaHora -Descending

# Mostrar resultados
Write-Host "`n"
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " LISTA DE EQUIPOS UNIDOS AL DOMINIO POR $($usuarioAD.Name) (últimos 30 días)" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Cyan

# Si no hay resultados
if ($resultados.Count -eq 0) {
    Write-Host "No se encontraron equipos unidos por el usuario ingresado." -ForegroundColor Red
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
Write-Host " Total de equipos encontrados: $($resultados.Count)" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor DarkCyan